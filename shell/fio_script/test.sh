#!/bin/bash
ROOT=$(cd `dirname $0` && pwd -P)
cd $ROOT
source $ROOT/conf.sh
source $ROOT/nvme_wrr.sh

set -e

# default test setting
g_policy=none
g_test=rr
g_num_jobs=8
g_iodepth=32
g_cgroup_ver=v1
#g_cgroup_ver=v2

g_all_policy="none bfq iocost wrr"
g_all_test="rr rw sr sw"

function log()
{
	local func=${FUNCNAME[1]}
	local pid=`sh -c 'echo $PPID'`
	echo "[$pid] $func $@"
}

# $1: file
# $2: val
function write_file()
{
	local file=$1
	local val=$2
	local func=${FUNCNAME[1]}
	local pid=`sh -c 'echo $PPID'`
	echo "[$pid] $func echo $val > $file"
	echo $val > $file
}

# $1: disk name
function get_all_slave_disk()
{
	local l_disk=$1

	# have slaves?
	local slaves=`ls /sys/block/$l_disk/slaves`
	local s
	for s in $slaves
	do
		g_all_disk[$g_disk_nr]=$s
		let g_disk_nr++
		get_all_slave_disk $s
	done
}

# align with test_file_name
function get_all_disk_name_by_test_file()
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

	g_all_disk[0]=$g_disk
	g_disk_nr=1

	get_all_slave_disk $g_disk

	echo "All disks realated to test file: $test_file_name"
	local i
	for ((i=0;i<$g_disk_nr;i++))
	do
		echo "disk[$i]: ${g_all_disk[$i]}"
	done
}

# $1: 0 disable v2 ,1 enable v2
function config_cgroup_version()
{
	if [ x$g_cgroup_ver == xv1 ]; then
		g_cg_prefix=/sys/fs/cgroup/blkio
		g_bfq_weight_file=blkio.bfq.weight
		g_ioc_weight_file=""
		g_wrr_weight_file=blkio.wrr
	else
		g_cg_prefix=/sys/fs/cgroup
		g_bfq_weight_file=io.bfq.weight
		g_ioc_weight_file=io.weight
		g_wrr_weight_file=io.wrr
	fi

}

function config_policy()
{
	local val=none

	if [ x$g_policy == xbfq ]; then
		val=bfq
	fi

	local i
	for ((i=0;i<$g_disk_nr;i++))
	do
		local l_disk=${g_all_disk[$i]}
		local file=/sys/block/$l_disk/queue/scheduler
		# change scheduler
		write_file $file "$val"
		# disable merge
		# file=/sys/block/$l_disk/queue/nomerges
		# write_file $file 1
	done
}

# $1: cgroup
# $2: weight
function config_weight()
{
	if [ x$g_policy == xbfq ]; then
		g_weight_file=$g_bfq_weight_file
	elif [ x$g_policy == xiocost ]; then
		g_weight_file=$g_ioc_weight_file
	elif [ x$g_policy == xwrr ]; then
		g_weight_file=$g_wrr_weight_file
	else
		g_weight_file=""
		return
	fi

	if [ -z $g_weight_file ]; then
		log "g_weith_file is null, exit"
		exit
	fi

	local path=$1
	local wt=$2
	local file=$path/$g_weight_file


	if [ x$g_policy == xwrr ]; then
		local i
		for ((i=0;i<$g_disk_nr;i++))
		do
			local l_disk=${g_all_disk[$i]}
			local val="`cat /sys/block/$l_disk/dev` $wt"
			write_file $file "$val"
		done
	else
		write_file $file "$wt"
	fi
}

function reset_cgroup() {
	local path=$1
	local file val i 
	# reset wrr
	for ((i=0;i<$g_disk_nr;i++))
	do
		local l_disk=${g_all_disk[$i]}
		local val="`cat /sys/block/$l_disk/dev` none"

		file=$path/$g_wrr_weight_file
		if [ -e $file ]; then
			write_file $file "$val"
		fi
	done

	# reset iocost
	if [ -n "$g_ioc_weight_file" ];then
		file=$path/$g_ioc_weight_file
		if [ -e $file ]; then
			val=100
			write_file $file "$val"
		fi
	fi

	# reset bfq
	if [ -n "$g_bfq_weight_file" ];then
		file=$path/$g_bfq_weight_file
		if [ -e $file ]; then
			val=100
			write_file $file "$val"
		fi
	fi
}

# $1: script to run
# $2: cgroup
# $3: weight of cgroup
# $4: output file name
function run_test()
{
	local test=$1
	local cg=$2
	local wt=$3
	local out=$4
	local pid=`sh -c 'echo $PPID'`
	local path=$g_cg_prefix/$cg
	local file
	local val

	mkdir -p $path

	reset_cgroup $path

	export test_logfile=$out

	file=$path/cgroup.procs
	write_file $file $pid

	config_weight $path $wt

	$test
}

function usage()
{
cat << EOF
	Usage: $g_app -p policy -t test_case -j fio_jobs -d iodepth [-g cgroup_versoin]

	-p policy: scheduler can be "none" "iocost" "bfq" "wrr"

	-t test_case: rr, rw, sr or sw. rr=randread, rw=randwrite, sr=read, sw=write

	-j fio_jobs: --num_jobs for fio arguments

	-d iodepth: --iodepth for fio arguments

	-g cgroup_version: v1 or v2, default on cgroup v2


	Example:

		sh test.sh -p none -t rr -j 8 -d 32

		# test on cgroup v1
		sh test.sh -p none -t rr -j 8 -d 32 -g v1
EOF

	exit
}

function parse_args()
{
	local false_arg
	while [ $# -gt 0 ];
	do
		case $1 in
		"-p") g_policy=$2; shift;; # set policy: iocost, bfq, wrr, none
		"-t") g_test=$2; shift;; # set test case: rr, rw, sr, sw. rr=randread, sw=write
		"-j") g_num_jobs=$2; shift;; # --num_jobs for fio arguments
		"-d") g_iodepth=$2; shift;; # --iodepth for fio arguments
		"-g") g_cgroup_ver=$2; shift;; # cgroup version: v1 or v2
		"-h") usage;;
		*) usage;
		esac

		shift
	done

	# check policy
	false_arg=1
	local t
	for t in $g_all_policy
	do
		if [ x$t == x$g_policy ]; then
			false_arg=0
			break
		fi
	done

	if [ $false_arg -eq 1 ]; then
		log "wrong policy ($g_policy), exit"
		exit
	fi

	false_arg=1
	local t
	for t in $g_all_test
	do
		if [ x$t == x$g_test ]; then
			false_arg=0
			break
		fi
	done

	if [ $false_arg -eq 1 ]; then
		log "wrong test ($g_test), exit"
		exit
	fi

	date
	echo "============================================================"
	echo "isolation policy: $g_policy"
	echo "test case:        $g_test"
	echo "fio num_jobs:     $g_num_jobs"
	echo "fio io depth:     $g_iodepth"
	echo "cgroup version:   $g_cgroup_ver"
	echo "============================================================"
}

function main()
{
	g_app=$0

	parse_args $@

	echo "Test start ..."
	get_all_disk_name_by_test_file

	# cgroup v1 or v2
	config_cgroup_version

	config_policy


	g_test1="$ROOT/${g_test}.sh $g_num_jobs $g_iodepth"
	g_test2="$ROOT/${g_test}.sh $g_num_jobs $g_iodepth"

	g_weight1=800
	g_weight2=100

	if [ x$g_policy == xwrr ]; then
		g_weight1=64
		g_weight2=8
		config_weight_wrr $g_weight1 32 $g_weight2

		# wrapper to nvme wrr
		g_weight1="high"
		g_weight2="low"
	fi

	run_test "$g_test1" test1 $g_weight1 ${g_policy}_test1 &
	#sleep 30
	run_test "$g_test2" test2 $g_weight2 ${g_policy}_test2 &

	wait

	echo "Test done"
}

main $@
