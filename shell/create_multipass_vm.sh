#!/bin/bash
#
# This script used to create VM by multipass for Ubuntu.
#
# Author: Weiping Zhang <zwp10758@gmail.com>
# Date: 2022-09-24
#
# Enjoy your time ^_^.

get_input()
{
	#echo "$@ :"
	read -p "$@ :" r
	echo "$r"
}

ALL_UBUNTU=(18.04 20.04 22.04 22.10)
nr=${#ALL_UBUNTU[@]}
for((i=0;i<${nr};i++))
do
	echo "$i) ${ALL_UBUNTU[$i]}"
done
echo "select a release:"
read r
if [ $r -gt $((nr-1)) -o $r -lt 0 ]; then
	echo "bad index"
	exit
fi
UBUNTU_RELEASE=${ALL_UBUNTU[$r]}


#HOST_NAME=`get_input "ubuntu"`
HOST_NAME=`get_input "Input hostname"`
CPU_NR=`get_input "Input cpu count"`
MEM_GB=`get_input "Input mem(G)"`
DISK_GB=`get_input "Input disk(G)"`

echo -e "\n\nThe configration:"
echo "Ubuntu:     ${UBUNTU_RELEASE}"
echo "hostname:   ${HOST_NAME}"
echo "CPU count:  ${CPU_NR}"
echo "memory(G):  ${MEM_GB}"
echo "disk(G):    ${DISK_GB}"

read -p "Configuration is right and continue to create VM(yN) ?" r
if [ x"$r" == xy ]; then
	echo "Start create VM...."
#multipass launch -n t220401 -d 80G -m 16G -c 16 22.04
	echo "Finish create VM, please login it by the following command:"
	echo "multipass shell ${HOST_NAME}"
else
	echo "Bye"
fi
