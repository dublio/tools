#!/bin/bash
#
# This script only test for the OS boot with grub.
#
# mr.sh: make kernel, install kernel, set default kernel and reboot system
#
# Dependency package: kernel build tools, grub2-tools, grubby 
#
# Usage: just copy this script to your kernel source tree, run it.
#
# Author: Weiping Zhang <zwp10758@gmail.com>
# Date: 2020-02-27
#
# Enjoy your time ^_^.
#

ROOT=`cd $(dirname $0) && pwd -P`
cd $ROOT

set -eo pipefail # exit, if failed to execute any one command seperated by pipe

LOG_FILE=$ROOT/build.log
rm -f $LOG_FILE
touch $LOG_FILE

function log()
{
	echo "`date '+%F %T'` $@" 2>&1 | tee -a $LOG_FILE
}

function set_def_kernel()
{
	log "update grub"
	grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1 | tee -a $LOG_FILE

	# generate kernel version from Makefile
	eval `grep -E "^VERSION|^PATCHLEVEL|^SUBLEVEL|^EXTRAVERSION" Makefile | sed 's/ = /=/'`
	KERNELVERSION=$VERSION
	if [ -n "$PATCHLEVEL" ]; then
		KERNELVERSION+=".$PATCHLEVEL"
	fi
	if [ -n "$SUBLEVEL" ]; then
		KERNELVERSION+=".$SUBLEVEL"
	fi
	KERNELVERSION+=$EXTRAVERSION

	# may append a +
	local lver=`sh $ROOT/scripts/setlocalversion $ROOT`
	KERNELVERSION+=$lver

	log "$KERNELVERSION - Generated based on Makefile"

	local ks=`grubby --info ALL | egrep "^index|^kernel" | awk '{if (0==NR%2) {print $0} else {printf("%s ", $0);}}'`

	echo "$ks"
	local nr index kernel
	nr=`echo "$ks"| grep -c $KERNELVERSION`
	if [ $nr -lt 1 ]; then
		log "Not found matched item"
		exit
	fi
	if [ $nr -gt 1 ]; then
		log "Found ($nr) matched items:"
		echo "$ks"| grep $KERNELVERSION
		exit
	fi
	eval `echo "$ks"| grep $KERNELVERSION`
	log "select $index $kernel"

	# set default kernel for grub
	grubby --set-default=$kernel 2>&1 | tee -a $LOG_FILE

	log "Update grub2 done, please reboot your system"
}

function build()
{
	echo "start make"
	make -j`nproc` 2>&1 | tee -a $LOG_FILE
	make modules_install -j`nproc` 2>&1 | tee -a $LOG_FILE
	make install -j`nproc` 2>&1 | tee -a $LOG_FILE
	log "make finish"
}

build
set_def_kernel
# if this script work stable, enable the following reboot
#reboot
