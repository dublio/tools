#!/bin/bash
root=$(cd `dirname $0` && pwd -P)
cd $root

mkdir -p $root/log

if [ -z $test_file_size ]; then
#export test_file_size=100%
export test_file_size=10G
fi

if [ -z $test_file_name ]; then
#export test_file_name=/dev/nvme1n1
export test_file_name=fio.test.file
fi

if [ -z $test_time ]; then
export test_time=60
fi

if [ -z $test_ioengine ]; then
export test_ioengine=libaio
fi

if [ -z $test_nr_jobs ]; then
export test_nr_jobs=1
fi

if [ -z $test_io_depth ]; then
export test_io_depth=1
fi

if [ -z $test_cpus_allow ]; then
export test_cpus_allow=`cat /sys/devices/system/cpu/online`
fi

if [ -z $test_direct ]; then
export test_direct=1
fi

if [ -z $test_time_based ]; then
export test_time_based=1
fi

if [ -z $test_group_reporting ]; then
export test_group_reporting=1
fi

function update_jobs_and_depth()
{
	if [ $# -ge 1 ]; then
		test_nr_jobs=$1
	fi
	if [ $# -ge 2 ]; then
		test_io_depth=$2
	fi
}

function run_fio()
{
	local base="${test_name}_${test_nr_jobs}_${test_io_depth}"

	if [ -n "$test_logfile" ]; then
		base="$test_logfile"
	fi

	local logfile="log/${base}.log"
	local parsefile="${logfile}.parse"

	rm -f $logfile $parsefile
	touch $logfile $parsefile

	fio \
	-cpus_allowed=$test_cpus_allow \
	--output=$logfile \
	-group_reporting=$test_group_reporting \
	-ioengine=$test_ioengine \
	-name=$test_name \
	-rw=$test_name \
	-filename=$test_file_name \
	-size=$test_file_size \
	-direct=$test_direct \
	-bs=$test_blk_size \
	-numjobs=$test_nr_jobs \
	--terse-version=3 \
	--minimal \
	-iodepth=$test_io_depth \
	-time_based=$test_time_based \
	-runtime=$test_time

	#cat $logfile
	$root/parse_fio_terse.sh $logfile 2>/dev/null > $parsefile
}
