#!/usr/bin/env bash

declare -A commands

# {
#     echo "Starting task..."
#         exec 3< hello.txt
#         while read -u 3 line; do
#             echo "item: $line"
#         done
#         exec 3>&-
# } || {
#     echo "Task failed! Entering error handling..."
#     exit 1
# }

Run() {
    local _cmd=${1:-}
    shift
    echo $_cmd
    echo $#
    ("$_cmd" "$@") &
    PID=$!
    wait $PID
    echo "Task Complete!"
}

task1() {
    local s=5
    echo -e "\e[32m"
    echo -e "task: ${FUNCNAME[0]} sleep: $s"
    for arg in "$@"; do
        echo "$arg"
    done
    echo -e "\e[0m"
    sleep $s
}

task2() {
    echo -e "task: ${FUNCNAME[0]}"
}

commands=(
    task2 a b c
)

for cmd in "${commands[@]}"; do
    Run $cmd
done
