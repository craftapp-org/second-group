
#!/bin/bash
PROJECT_NAME=$1
CPU_LIMIT=$2  # e.g., "200000 100000"
MEMORY_LIMIT=$3  # e.g., "2147483648"

# Create cgroup
sudo mkdir -p /sys/fs/cgroup/$PROJECT_NAME
echo "$CPU_LIMIT" | sudo tee /sys/fs/cgroup/$PROJECT_NAME/cpu.max
echo "$MEMORY_LIMIT" | sudo tee /sys/fs/cgroup/$PROJECT_NAME/memory.max



# #!/bin/bash
# PROJECT_NAME=$1
# CPU_LIMIT=$2  # e.g., "200000 100000"
# MEMORY_LIMIT=$3  # e.g., "2147483648"

# # Create cgroup
# sudo mkdir -p /sys/fs/cgroup/$PROJECT_NAME
# echo "$CPU_LIMIT" | sudo tee /sys/fs/cgroup/$PROJECT_NAME/cpu.max
# echo "$MEMORY_LIMIT" | sudo tee /sys/fs/cgroup/$PROJECT_NAME/memory.max
# # Enable controllers
# echo "+cpu +memory" | sudo tee /sys/fs/cgroup/$PROJECT_NAME/cgroup.subtree_control

# # Assign containers ONLY from the specified compose project
# docker ps --filter "label=com.docker.compose.project=$PROJECT_NAME" -q | \
#   xargs docker inspect --format '{{.State.Pid}}' | \
#   while read pid; do
#     echo $pid | sudo tee /sys/fs/cgroup/$PROJECT_NAME/cgroup.procs
#   done