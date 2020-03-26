#!/bin/bash

root=$(cd `dirname $0` && pwd -P)
source $root/conf.sh
cd $root

# $1: jobs
# $2: io depth
if [ $# -gt 0 ]; then
	update_jobs_and_depth $@
fi

test_name=write
test_blk_size=256K

run_fio
