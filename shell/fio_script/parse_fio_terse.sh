#!/bin/bash

function parse_bw_iops_lat_mean()
{
	local file=$1

	#  7 read_bandwidth
	# 48 write_bandwidth
	local bw=`awk -F ";" '{printf("%ld\n", $7 + $48)}' $file`

	#  8 read_iops
	# 49 write_iops
	local iops=`awk -F ";" '{printf("%ld\n", $8 + $49)}' $file`

	# 40 read_lat_mean
	local read_lat_mean=`awk -F ";" '{print $40}' $file`
	# 81 write_lat_mean
	local write_lat_mean=`awk -F ";" '{print $81}' $file`

	local test_case=`echo $file | sed 's#./##' | sed 's/.log//' | sed 's/_0[0-9]_/_/'`
	#printf "%-40s %10d %10d %10.2f %10.2f\n" $file $bw $iops $read_lat_mean $write_lat_mean
	printf "%-40s %-10d %-10d %-12.2f %-12.2f\n" $test_case $bw $iops $read_lat_mean $write_lat_mean
}

function parse_bw_iops_lat_mean_header()
{
	printf "%-40s %-10s %-10s %-12s %-12s\n" "test case" "bw" "iops" "rd_avg_lat" "wr_avg_lat"
}

function parse_bw_iops_lat_mean_p99()
{
	local file=$1

	#  7 read_bandwidth
	# 48 write_bandwidth
	local bw=`awk -F ";" '{printf("%ld\n", $7 + $48)}' $file`

	#  8 read_iops
	# 49 write_iops
	local iops=`awk -F ";" '{printf("%ld\n", $8 + $49)}' $file`

	# 40 read_lat_mean
	local read_lat_mean=`awk -F ";" '{print $40}' $file`
	# 81 write_lat_mean
	local write_lat_mean=`awk -F ";" '{print $81}' $file`

	# 30 read_lat_pct13: 99.000000%=0
	local read_lat_p99=`awk -F ";" '{print $30}' $file | awk -F = '{print $2}'`
	# 71 write_lat_pct13: 99.000000%=0
	local write_lat_p99=`awk -F ";" '{print $71}' $file | awk -F = '{print $2}'`

	local test_case=`basename $file | sed 's/.log//' | sed 's/_0[0-9]_/_/'`
	#printf "%-40s %10d %10d %10.2f %10.2f\n" $file $bw $iops $read_lat_mean $write_lat_mean
	printf "%-40s %-10d %-10d %-12.2f %-12.2f %-12.2f %-12.2f\n" $test_case $bw $iops $read_lat_mean $write_lat_mean $read_lat_p99 $write_lat_p99
}

function parse_bw_iops_lat_mean_p99_header()
{
	printf "%-40s %-10s %-10s %-12s %-12s %-12s %-12s\n" "test case" "bw" "iops" "rd_avg_lat" "wr_avg_lat" "rd_p99_lat" "wr_p99_lat"
}

function main()
{
	local fd=$1
	if [ ! -e $fd ]; then
		echo "Does not exist: $fd"
		exit
	fi

	parse_bw_iops_lat_mean_p99_header
	if [ -d $fd ]; then
		fs=`ls $fd`
		for f in $fs
		do
			parse_bw_iops_lat_mean_p99 $fd/$f
		done
	elif [ -f $fd ]; then
		parse_bw_iops_lat_mean_p99 $fd
	fi
}

main $@
