#!/bin/bash
ROOT=$(cd `dirname $0` && pwd -P)
cd $ROOT
source $ROOT/conf.sh

WEIGHT_NONE="none"

# default test setting
g_policy=none
g_test=rr
g_numjobs=8
g_iodepth=32
g_cgroup_ver=v2

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
		g_wrr_weight_file=blkio.wrr
	else
		g_cg_prefix=/sys/fs/cgroup
		g_bfq_weight_file=io.bfq.weight
		g_ioc_weight_file=io.weight
		g_wrr_weight_file=io.wrr
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
function config_policy()
{
	local sched=$1
	local val=none

	if [ x$sched == xbfq ]; then
		g_weight_file=$g_bfq_weight_file
		val=bfq
	elif [ x$sched == xiocost ]; then
		g_weight_file=$g_ioc_weight_file
	elif [ x$sched == xwrr ]; then
		g_weight_file=$g_wrr_weight_file
	else
		g_weight_file=$WEIGHT_NONE
	fi

	echo $val > /sys/block/$g_disk/queue/scheduler
}

function reset_all()
{
	local path=$1
	local file val
	local dev=`cat /sys/block/$g_disk/dev`

	# reset wrr
	file=$path/$g_wrr_weight_file
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

	if [ ! x"$g_weight_file" == x"$WEIGHT_NONE" ]; then
		file=$path/$g_weight_file
		val=$wt
		echo $val > $file
		echo "$val > $file"
	fi
	$test
}


function bfq()
{
	config_policy bfq
	g_weight1=800
	g_weight2=100
}

function iocost()
{
	config_policy iocost
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

	config_policy wrr
	g_weight1="$dev high"
	g_weight2="$dev low"
}

function none()
{
	config_policy none
	g_weight1="$WEIGHT_NONE"
	g_weight2="$WEIGHT_NONE"
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
	while [ $# -gt 0 ];
	do
		case $1 in
		"-p") g_policy=$2; shift;; # set policy: iocost, bfq, wrr, none
		"-t") g_test=$2; shift;; # set test case: rr, rw, sr, sw. rr=randread, sw=write
		"-j") g_num_jobs=$2; shift;; # --num_jobs for fio arguments
		"-d") g_iodepth=$2; shift;; # --iodepth for fio arguments
		"-g") g_cgroup_ver=$2; shift;; # cgroup version: v1 or v2
		*) usage;
		esac

		shift
	done

	echo "plicy:$g_policy"
	echo "test case:$g_test"
	echo "num_jobs:$g_g_num_jobs"
	echo "io depth: $g_iodepth"
	echo "cgroup version: $g_cgroup_ver"
}

function main()
{
	g_app=$0

	parse_args $@

	echo "Test start ..."
	get_disk_name_by_test_file

	# cgroup v1 or v2
	if [ x$g_cgroup_ver == xv2 ]; then
		enable_cgroup_v2
	else
		disale_cgroup_v2
	fi

	#bfq #iocost #wrr #node
	$g_policy

	# disable merge
	echo 1 > /sys/block/$g_disk/queue/nomerges

	g_test1="$ROOT/${g_test}.sh $g_num_jobs $g_iodepth"
	g_test2="$ROOT/${g_test}.sh $g_num_jobs $g_iodepth"

	run_test "$g_test1" test1 "$g_weight1" ${g_policy}_test1 &
	#sleep 30
	run_test "$g_test2" test2 "$g_weight2" ${g_policy}_test2 &

	wait

	echo "Test done"
}

main $@
