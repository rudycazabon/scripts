#!/usr/bin/env bash

source "./logger.sh"

url="https://github.com/libsdl-org/SDL.git"

run_git() {
    git clone --recursive $1 
}


with ctx_logger -- \
with ctx_timer -- \
run_git $url