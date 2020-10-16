#!/bin/bash
ROOT="$($(cd $(dirname $0)) && pwd -P)"
cd $ROOT

# compile binary
gcc cgroup_v1_release_agent.c -o cgroup_v1_release_agent

# mount pointer
temp_dir="$ROOT/mnt"
mkdir -p $temp_dir
mount -t cgroup -o none,name=release_agent_test none "$temp_dir"

echo "$ROOT/cgroup_v1_release_agent" > "$temp_dir/release_agent"
echo 1 > "$temp_dir/notify_on_release"

test_dir="$temp_dir/test_dir"

mkdir -p "$test_dir"

pid="$(sh -c 'echo $PPID')"

echo "$pid" > "$test_dir/tasks"
echo "$pid" > "$temp_dir/tasks"

rmdir "$test_dir"
umount "$temp_dir"
rmdir "$temp_dir"

rm -f cgroup_v1_release_agent

echo "Test done, please check dmesg"
dmesg | tail
