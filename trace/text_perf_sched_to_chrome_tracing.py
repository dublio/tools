#!/usr/bin/python3

import json
import argparse

# convert "perf script" to "chrome tracing json"
# focus on sched_wakeup,sched_wakeup_new,sched_switch,sched_migrate_task
# Author: zwp10758@gmail.com
# Date:   2021-06-10
# Bug report: https://github.com/dublio/tools/issues
#
# example:
# 1. sudo perf sched record -- sleep 1
# 2. sudo perf sched script > s.log
# 3. sudo ./text_perf_sched_to_chrome_tracing.py -i s.log -o test.json -n 100
# 4. open Google Chrome we browser and goto chrome://tracing
# 5. click the load button to load test.json
# 
# please make sure your kernel patched with the following commit, otherwise
# you use this wrokaround script "sched_switch_prev_state_fixup.sh" to correct to the right prev_state.
# https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=3054426dc68e5d63aa6a6e9b91ac4ec78e3f3805

#sched:sched_switch: trace_fields: prev_comm,prev_pid,prev_prio,prev_state,next_comm,next_pid,next_prio
#sched:sched_stat_wait: trace_fields: comm,pid,delay
#sched:sched_stat_sleep: trace_fields: comm,pid,delay
#sched:sched_stat_iowait: trace_fields: comm,pid,delay
#sched:sched_stat_runtime: trace_fields: comm,pid,runtime,vruntime
#sched:sched_process_fork: trace_fields: parent_comm,parent_pid,child_comm,child_pid
#sched:sched_wakeup: trace_fields: comm,pid,prio,success,target_cpu
#sched:sched_wakeup_new: trace_fields: comm,pid,prio,success,target_cpu
#sched:sched_migrate_task: trace_fields: comm,pid,prio,orig_cpu,dest_cpu


# swapper     0 [002]  9113.660136:       sched:sched_switch: prev_comm=swapper/2 prev_pid=0 prev_prio=120 prev_state=S ==> next_comm=lidar_node next_pid=21302 next_prio=120
# swapper     0 [002]  9113.660967:       sched:sched_wakeup: comm=lidar_node pid=21302 prio=120 target_cpu=002
# swapper  2196 [001]  9113.810904:   sched:sched_wakeup_new: comm=voy_network_mon pid=35456 prio=120 target_cpu=017
# sensing_node 21350 [023]  9113.668473: sched:sched_migrate_task: comm=sensing_node pid=21639 prio=120 orig_cpu=4 dest_cpu=23

# key: tid+comm
# val:
#   key: state
#   val:
#	     R: Running
#        Q: Runable but waiting in queue
#        S: Sleeping
#        D: Uninterruptble Sleep
#   key: event
#   val: json string of the 'B' event of this tid
# insert both 'B' and 'E' to file if find a 'B' & 'E' pair
_STATE_R = "Running"
_STATE_Q = "Queuing"
_STATE_W = "Wakeup"
_STATE_I = "cpu_idle"

_COLOR_Q = "terrible"	# red:    queuing
_COLOR_R = "good"		# green:  running
_COLOR_I = "olive"		# olive:  idle
_COLOR_M = "yellow"		# yellow:  migration
_COLOR_W = "thread_state_runnable"		# FIXME: set to blue:  wakeup

# Attention: fixed 1us only for show instant event, like wakeup, migrate
# shoule use 'I' instant event, instead of 'X' duration event,
# The reason why we now use 'X' instead of 'I' is that 'I' event is
# hard to see it from web browser, it nearly show a line not a rectangle.
# 'X' show as a rectangle.
_MARKER_DUR = 1
_LAST_STATE = 'state'
_LAST_EVENT = 'event'

# only a fake marker, no useful
_LAST_EVENT_DUMMY =  "dummy"
g_pid_last_state = {}

g_event = []
g_event_nr = 0

def append_event(evt):
	global g_event
	global g_event_nr
	g_event.append(evt)
	g_event_nr += 1

def get_last_state(tid):
	if tid in g_pid_last_state.keys():
		# remove last state_event
		se = g_pid_last_state.pop(tid)
		return se
	else:
		return None

def set_last_state(tid, state, event):
	se = {}
	se[_LAST_STATE] = state
	se[_LAST_EVENT] = event
	g_pid_last_state[tid] = se

# sensing_node 21350 [023]  9113.668473: sched:sched_migrate_task: comm=sensing_node pid=21639 prio=120 orig_cpu=4 dest_cpu=23
# keep wait from one cpu to another
def handle_migrate(line):
	comm1,tid1,cpu1,ts,event,comm,tid,prio,orig_cpu,dest_cpu = line.split()

	ts = int(float(ts.split(":")[0]) * 1000000)
	comm = comm.split('=')[1]
	tid = tid.split('=')[1]
	prio = prio.split('=')[1]
	orig_cpu = "%03d" % int(orig_cpu.split('=')[1])
	dest_cpu = "%03d" % int(dest_cpu.split('=')[1])

	last_state_event = get_last_state(tid+comm)
	if last_state_event:
		last_state = last_state_event[_LAST_STATE]
		last_event = last_state_event[_LAST_EVENT]
		# if no last_state, that means this is the first event of this tid,
		# just save it's state
		# if last_state is R, record the end of this tid
		if last_state == _STATE_Q:
			dur = ts - last_event['ts']
			if dur > 0:
				tmp = {
					"name"  : last_state,
					"pid"   : orig_cpu,
					"tid"  : "%s prio:%s %s" % (tid, prio, comm),
					"ph"   : "X",
					"ts"   : last_event['ts'],
					"dur"  : dur,
					"cname" : _COLOR_Q,
				}
				append_event(tmp)
			# add marker for migration
			mig = {
				"name"  : "mig to cpu-%s" % dest_cpu,
				"pid"   : orig_cpu,
				"tid"  : "%s prio:%s %s" % (tid, prio, comm),
				"ph"   : "X",
				"s"    : "t",
				"ts"   : ts,
				"dur"  : _MARKER_DUR,
				"cname" : _COLOR_M,
			}
			append_event(mig)
	# add marker for migration
	mig = {
		"name"  : "mig from cpu-%s" % orig_cpu,
		"pid"   : dest_cpu,
		"tid"  : "%s prio:%s %s" % (tid, prio, comm),
		"ph"   : "X",
		"s"    : "t",
		"ts"   : ts - _MARKER_DUR,
		"dur"  : _MARKER_DUR,
		"cname" : _COLOR_M,
	}
	append_event(mig)
	# new start of wait
	tmp = {
		"name"  : _STATE_Q,
		"pid"   : dest_cpu,
		"tid"  : "%s prio:%s %s" % (tid, prio, comm),
		"ph"   : "B",
		"ts"   : ts,
		"cname" : _COLOR_Q,
	}
	set_last_state(tid + comm, _STATE_Q, tmp)

def handle_switch_prev(cpu, ts, prev_tid, prev_prio, prev_comm, prev_state):
	last_state_event = get_last_state(prev_tid + prev_comm)
	if last_state_event:
		last_state = last_state_event[_LAST_STATE]
		last_event = last_state_event[_LAST_EVENT]
		# if no last_state, that means this is the first event of this tid,
		# just save it's state
		# if last_state is R, record the end of this tid
		if last_state == _STATE_R:
			# prev
			if prev_tid != "0":
				color = _COLOR_R
				name = _STATE_R
			else:
				color = _COLOR_I
				name = _STATE_I
			dur = ts - last_event['ts']
			if dur > 0:
				tmp = {
					"name"  : name,
					"pid"   : cpu,
					"tid"  : "%s prio:%s %s" % (prev_tid, prev_prio, prev_comm),
					"ph"   : "X",
					"ts"   : last_event['ts'],
					"dur"  : dur,
					"cname" : color,
				}
				append_event(tmp)

	# if prev_sate is R, it enter Q state
	if prev_state.startswith("R"):
		if prev_tid != "0":
			prev_out2 = {
				"name"  : _STATE_Q,
				"pid"   : cpu,
				"tid"  : "%s prio:%s %s" % (prev_tid, prev_prio, prev_comm),
				"ph"   : "B",
				"ts"   : ts,
				"cname" : _COLOR_Q,
			}
			set_last_state(prev_tid + prev_comm, _STATE_Q, prev_out2)
	else:
		if prev_tid != "0":
			set_last_state(prev_tid + prev_comm, prev_state, _LAST_EVENT_DUMMY)

def handle_switch_next(cpu, ts, next_tid, next_prio, next_comm):
	# get last state of this thread, if Q add a end of Q, otherwise do nothing
	last_state_event = get_last_state(next_tid + next_comm)
	if last_state_event:
		last_state = last_state_event[_LAST_STATE]
		last_event = last_state_event[_LAST_EVENT]
# the reason why check ts !=  last_event['ts'] is that, wakeup.ts = sched_switch.ts
# basler_camera 21275 [000]  9113.673906:       sched:sched_wakeup: comm=basler_camera pid=21935 prio=120 target_cpu=000
# basler_camera 21275 [000]  9113.673906:       sched:sched_switch: prev_comm=basler_camera prev_pid=21275 prev_prio=120 prev_state=R ==> next_comm=basler_camera next_pid=21935 next_prio=120
		if last_state == _STATE_Q:
			dur = ts - last_event['ts']
			if dur > 0:
				tmp = {
					"name"  : last_state,
					"pid"   : cpu,
					"tid"  : "%s prio:%s %s" % (next_tid, next_prio, next_comm),
					"ph"   : "X",
					"ts"   : last_event['ts'],
					"dur"  : dur,
					"cname" : _COLOR_Q,
				}
				append_event(tmp)

	if next_tid != "0":
		color = _COLOR_R
	else:
		color = _COLOR_I
	next_out2 = {
		"name"  : _STATE_R,
		"pid"   : cpu,
		"tid"  : "%s prio:%s %s" % (next_tid, next_prio, next_comm),
		"ph"   : "B",
		"ts"   : ts,
		"cname" : color,
	}
	set_last_state(next_tid + next_comm, _STATE_R, next_out2)

# swapper     0 [002]  9113.660136:       sched:sched_switch: prev_comm=swapper/2 prev_pid=0 prev_prio=120 prev_state=S ==> next_comm=lidar_node next_pid=21302 next_prio=120
def handle_switch(line):
	comm1,tid1,cpu1,ts,event,prev_comm,prev_tid,prev_prio,prev_state,reserv1,next_comm,next_tid,next_prio = line.split()

	cpu = cpu1[1:-1]
	prev_comm = prev_comm.split('=')[1]
	prev_tid = prev_tid.split('=')[1]
	prev_prio = prev_prio.split('=')[1]
	prev_state = prev_state.split('=')[1]
	next_comm = next_comm.split('=')[1]
	next_tid = next_tid.split('=')[1]
	next_prio = next_prio.split('=')[1]
	ts = int(float(ts.split(":")[0]) * 1000000)

	handle_switch_prev(cpu, ts, prev_tid, prev_prio, prev_comm, prev_state)
	handle_switch_next(cpu, ts, next_tid, next_prio, next_comm)


# swapper     0 [002]  9113.660967:       sched:sched_wakeup: comm=lidar_node pid=21302 prio=120 target_cpu=002
# swapper  2196 [001]  9113.810904:   sched:sched_wakeup_new: comm=voy_network_mon pid=35456 prio=120 target_cpu=017
def handle_wakeup(line):
	# parse fields
	comm1,tid1,cpu1,ts,event,comm,tid,prio,cpu = line.split()
	
	# ts: use us
	ts = int(float(ts.split(":")[0]) * 1000000)
	comm = comm.split('=')[-1]
	tid = tid.split('=')[-1]
	prio = prio.split('=')[-1]
	cpu = cpu.split('=')[-1]
	
	# get last state of this tid:
	# save its state and write a start waiting for this tid and cpu

	if tid != "0":
		# chrome tracing format
		tmp = {
			"name"  : _STATE_Q,
			"pid"  : cpu,
			"tid"  : "%s prio:%s %s" % (tid, prio, comm),
			"ph"   : "B",
			"ts"   : ts,
			"cname" : _COLOR_Q,
		}
		set_last_state(tid + comm, _STATE_Q, tmp)
		# add marker for wakup
		wake = {
			"name"  : _STATE_W,
			"pid"   : cpu,
			"tid"  : "%s prio:%s %s" % (tid, prio, comm),
			"ph"   : "X",
			"s"    : "t",
			"ts"   : ts - _MARKER_DUR,
			"dur"  : _MARKER_DUR,
			"cname" : _COLOR_W,
		}
		append_event(wake)

def handle_line(line):
	# get event
	if "sched:sched_wakeup:" in line or "sched:sched_wakeup_new:" in line:
		handle_wakeup(line)
	elif "sched:sched_migrate_task:" in line:
		handle_migrate(line)
	elif "sched:sched_switch:" in line:
		handle_switch(line)

def parse_cpu_sched(file_in, file_out, event_num):
	# need check error
	try:
		fin = open(file_in, 'r')
	except:
		print("Exit, Not found file:", file_in)
		exit()
	fout = open(file_out, 'w+')

	# write begin
	nr_event = 0
	while True:
		line = fin.readline()
		if not line:
			break
		handle_line(line)
		if event_num > 0:
			if g_event_nr >= event_num:
				break

	json.dump(g_event, fout)
	fout.close()
	fin.close()

if __name__ == '__main__' :
	ps = argparse.ArgumentParser(
		formatter_class=argparse.RawTextHelpFormatter,
		description=
			'''
Convert perf sched script to chrome tracing json

example:
1. sudo perf sched record -- sleep 1
2. sudo perf sched script > s.log
3. sudo ./schedule.py -i s.log -o test.json -n 100
4. open Google Chrome we browser and goto chrome://tracing
5. click the load button to load test.json

please make sure your kernel patched with the following commit, otherwise
the schedule delay may not show correctly.
https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=3054426dc68e5d63aa6a6e9b91ac4ec78e3f3805
			''')
	ps.add_argument("-i", "--input", dest="input", type=str, required=True, metavar="input_file",
		help = "the input file path of perf sched script")
	ps.add_argument("-o", "--output", dest="output", type=str, required=False, metavar="output_file",
		default = "trace.json", # default output
		help = "the output file")
	ps.add_argument("-n", "--num", dest="num", type=int, required=False, metavar="event_number",
		default = 0, # parse all event
		help = "the number of events need to be parsed")

	args = ps.parse_args()
	parse_cpu_sched(args.input, args.output, args.num)
