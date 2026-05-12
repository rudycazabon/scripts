#!/bin/bash

# Check if an argument was provided
if [ -z "$1" ]; then
  echo "Usage: $0 <bash_script>"
  exit 1
fi

SCRIPT=$1

# Check if the file exists
if [ ! -f "$SCRIPT" ]; then
  echo "The file $SCRIPT does not exist."
  exit 1
fi

# Create a cgroup to limit resources
CGROUP_NAME="isolated"
CGROUP_PATH="/sys/fs/cgroup/$CGROUP_NAME"

# Create and configure the cgroup
mkdir -p $CGROUP_PATH
echo $$ > $CGROUP_PATH/tasks
echo 50 > $CGROUP_PATH/pids.max  # Limit to 50 processes

# Create a new PID and UTS namespace
unshare --pid --uts --mount --fork --mount-proc bash -c "
# Change the hostname
hostname isolated_env

# Mount a new tmpfs to isolate the temporary file system
mount -t tmpfs tmpfs /tmp

# Execute the provided script
bash $SCRIPT

# Clean up and exit
umount /tmp
"

# Wait for all processes in the cgroup to finish
while [ $(ls $CGROUP_PATH/tasks | wc -l) -gt 0 ]; do
  sleep 1
done

# Remove the cgroup after execution
rmdir $CGROUP_PATH

echo "Isolated environment finished and cleaned up, including cgroup."