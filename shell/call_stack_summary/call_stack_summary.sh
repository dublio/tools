#!/bin/bash

#
# a simple and low efficient script to summary call stack within a kernel log file
# It's used to show how many different stack occur and the count for each call stack
# in this kernel log file
#

g_stack_nr=0

# format: f1 f2 f3 ...
g_stack_array=""

# output 1 on end, 0 on not
function is_call_end()
{
	local line="$1"
	local key="system_call_fastpath"

	echo "$line" | grep -c "$key"
}


# output:
# NR1 f1 f2 f3
# NR2 f1 f2 f3
# ...
# NRn f1 f2 f3
function deduplicate()
{
	local i

	for ((i = 0; i < $g_stack_nr; i++))
	do
		printf "%s\n" "${g_stack_array[$i]}"
	done | sort | uniq -c | sort -rnk 1
}

# output:
# NR1
# func1
# func2
# func3
function main()
{
	local klog="$1"
	local kcall="$klog.call"
	local kuniq="$klog.uniq"
	local include="\[*\]"
	local exclude="\] ?"
	local is_valid is_end
	local line func

	if [ $# -ne 1 ]; then
		echo "please give a valid kernel log file, like ./call_stack_summary.sh /var/log/message"
		exit
	fi

	if [ ! -e "$klog" ]; then
		echo "please make sure log file is exist: $klog"
		exit
	fi

	echo "`date '+%F %T'` start analyzing, please wait... or improve it"
	cat $klog | grep -v "$exclude" | grep "$include" > $kcall

	# generate g_stack_array
	while read line
	do

		# get real function
		func="$(echo "$line" | awk -F "]" '{print $2}' | awk '{printf $1}')"
		# append this function to call array, seperated by space
		g_stack_array[$g_stack_nr]="${g_stack_array[$g_stack_nr]} ${func}"

		# this call stack is end
		is_end=$(is_call_end "$line")
		if [[ "1" == "$is_end" ]]; then
			#echo ">>> count:$g_stack_nr, ${g_stack_array[$g_stack_nr]}"
			g_stack_nr=$(($g_stack_nr + 1))
		fi
	done < $kcall

	echo "`date '+%F %T'` start deduplicate"
	deduplicate | while read line
	do
		echo "$line" | awk '{print "count:"$1} {for (i=2;i<=NF;i++) print $i} {printf("\n");}'
	done > $kuniq
	echo "`date '+%F %T'` done, please visit $kuniq"
}

main $@
