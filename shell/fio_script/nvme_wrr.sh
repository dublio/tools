#!/bin/bash

function config_weight_wrr()
{
	#local h=64
	#local m=32
	#local l=8
	local h=$1
	local m=$2
	local l=$3
	local ab=0

	for ((i=0;i<$g_disk_nr;i++))
	do
		local l_disk=${g_all_disk[$i]}
		if [[ "$l_disk" == nvme* ]]; then
			local val=`printf "0x%x\n" $(($ab<<0|$l<<8|$m<<16|$h<<24))`
			nvme set-feature /dev/$l_disk -f 1 -v $val
			log "nvme set-feature /dev/$l_disk -f 1 -v $val"
		fi
	done
}
