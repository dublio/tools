#!/bin/bash
ROOT=$(cd $(dirname $0) && pwd -P)
cd $ROOT

g_app=$0
g_trace_time_s=5
g_top_nr=10
g_dir="$ROOT/trace_$(date '+%Y.%m.%d_%H.%M.%S')"
mkdir -p $g_dir

function log()
{
	local dt=$(date '+%F %T')
	#local pid=$(sh -c "echo $PPID")
	#printf "$dt $pid $@\n"
	printf "[$dt] $@\n"
}

function verify_dev()
{
	local d

	if [[ $# -eq 0 ]]; then
		log "please input device name, like: sh $g_app /dev/sda /dev/sdb /dev/nvme0n1"
		exit
	fi

	for d in $@
	do
		if [[ ! -e $d ]]; then
			log "$d does not exist, skip it."
			continue
		fi

		g_devs="$g_devs $d"
	done
}

function start_trace()
{
	log "start trace $g_devs"
	blktrace -w $g_trace_time_s -d $g_devs
	log "finished to trace $g_devs"
}

function parse_trace()
{
	local d
	local maj min
	local dev

	for d in $g_devs
	do
		dev=${d:5}
		eval $(cat /sys/block/$dev/dev | awk -F : '{printf("maj=%s;min=%s;", $1, $2)}')
		log "============================================================"
		log "start parse $d $maj $min"
		log "============================================================"
		blkparse -i ${dev}.blktrace. -s -q -o "${dev}.parse" -d "${dev}.bin"
		btt -i "${dev}.bin" -l $dev -q $dev -p "${dev}.pio" > "${dev}.btt"
		mv $dev.blktrace.* $g_dir

		# top q2c
		log "============================================================"
		log "top $g_top_nr Q2C $d $maj $min"
		log "============================================================"
		sort -rnk 2 "${dev}_${maj},${min}_q2c.dat" | head -$g_top_nr

		# top D2c
		log "============================================================"
		log "top $g_top_nr D2C $d $maj $min"
		log "============================================================"
		sort -rnk 2 "${dev}_${maj},${min}_d2c.dat" | head -$g_top_nr

		# btt summary
		log "============================================================"
		log "btt summary $d $maj $min"
		log "============================================================"
		head -20 ${dev}.btt
		log "============================================================"
		log "finshed to parse $d $maj $min\n\n"
	done
}

verify_dev $@
start_trace
parse_trace
