#!/bin/bash
ROOT=$(cd `dirname $0` && pwd -P)
cd $ROOT
source $ROOT/conf.sh


# align with test_file_name
function get_disk_name_by_test_file()
{
	local path_name
	# a block device ?
	if [ -b $test_file_name ]; then
		echo "Block device"
		path_name=$test_file_name
	else
		# create it fir
		touch $test_file_name
		echo "Normal file detect block device"
		path_name=`df --output=source $test_file_name | tail -1`
	fi

	# get the last field seperated by /
	g_disk=${path_name##*/}

	echo "g_disk: $g_disk"
}

# $1: 0 disable v2 ,1 enable v2
function config_cgroup_v2()
{
	g_cgroup_v2=$1

	if [ $g_cgroup_v2 -eq 0 ]; then
		g_cg_prefix=/sys/fs/cgroup/blkio
		g_bfq_weight_file=blkio.bfq.weight
		g_ioc_weight_file=""
		g_wrr_file=blkio.wrr
	else
		g_cg_prefix=/sys/fs/cgroup
		g_bfq_weight_file=io.bfq.weight
		g_ioc_weight_file=io.weight
		g_wrr_file=io.wrr
	fi

}

function enable_cgroup_v2()
{
	config_cgroup_v2 1
}

function diable_cgroup_v2()
{
	config_cgroup_v2 0
}

# scheduler name
function config_scheduler()
{
	local sched=$1
	local val=none

	if [ x$sched == xbfq ]; then
		g_weight_file=$g_bfq_weight_file
		val=bfq
	elif [ x$sched == xiocost ]; then
		g_weight_file=$g_ioc_weight_file
	else
		g_weight_file=$g_wrr_file
	fi

	echo $val > /sys/block/$g_disk/queue/scheduler
}

function reset_all()
{
	local path=$1
	local file val
	local dev=`cat /sys/block/$g_disk/dev`

	# reset wrr
	file=$path/$g_wrr_file
	val="$dev none"
	echo $val > $file
	echo "reset $val > $file"

	# reset iocost
	file=$path/$g_ioc_weight_file
	val=100
	echo "$val" > $file
	echo "reset $val > $file"

	# reset bfq
	file=$path/$g_bfq_weight_file
	val=100
	echo "$val" > $file
	echo "reset $val > $file"
}

# $1: script to run
# $2: cgroup
# $3: weight of cgroup
# $4: output file name
function run_test()
{
	local test=$1
	local cg=$2
	local wt="$3"
	local out=$4
	local pid=`sh -c 'echo $PPID'`
	local path=$g_cg_prefix/$cg
	local file
	local val

	mkdir -p $path

	reset_all $path

	export test_logfile=$out

	file=$path/cgroup.procs
	val=$pid

	echo $val > $file
	echo "$pid > $file"

	file=$path/$g_weight_file
	val=$wt
	echo $val > $file
	echo "$val > $file"
	$test
}


function bfq()
{
	config_scheduler bfq
	g_weight1=800
	g_weight2=100
}

function iocost()
{
	config_scheduler iocost
	g_weight1=800
	g_weight2=100
}

function wrr()
{
	local h=64
	local m=32
	local l=8
	local ab=0
	local dev=`cat /sys/block/$g_disk/dev`

	nvme set-feature /dev/$g_disk -f 1 -v `printf "0x%x\n" $(($ab<<0|$l<<8|$m<<16|$h<<24))`

	config_scheduler wrr
	g_weight1="$dev high"
	g_weight2="$dev low"
}

function main()
{
	local sched=$1
	local test=$2
	local threads=$3
	local depth=$4

	if [ $# -lt 4 ]; then
		echo "Please give sched, test, threads, io depth"
		echo "test.sh bfq rr 8 32"
		exit
	fi

	echo "Test start ..."
	echo "scheduler:$sched, test:$test, thread_nr:$threads, io depth: $depth"
	get_disk_name_by_test_file

	enable_cgroup_v2

	#bfq
	#iocost
	#wrr

	$sched

	# disable merge
	echo 1 > /sys/block/$g_disk/queue/nomerges

	g_test1="$ROOT/${test}.sh $threads $depth"
	g_test2="$ROOT/${test}.sh $threads $depth"

	run_test "$g_test1" test1 "$g_weight1" ${sched}_test1 &
	#sleep 30
	run_test "$g_test2" test2 "$g_weight2" ${sched}_test2 &

	wait

	echo "Test done"
}

main $@
