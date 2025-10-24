#!/usr/bin/env bash
#
# Script Name: template.sh
# Description: A template for new Bash scripts incorporating best practices.
# Author: Your Name
# Date: YYYY-MM-DD
# Version: 1.0.0
# License: MIT or other chosen license
#
# Usage: ./template.sh [OPTIONS] [ARGUMENTS]
#
# Options:
#   -h, --help      Display this help message and exit.
#   -v, --verbose   Enable verbose output.
#
# Changelog:
#   YYYY-MM-DD: Initial creation.

# --- Configuration & Error Handling ---

# Exit immediately if a command exits with a non-zero status.
set -o errexit
# Exit if any command in a pipeline fails.
set -o pipefail
# Treat unset variables as an error and exit immediately.
set -o nounset
# Enable verbose output for debugging (uncomment or conditionally enable).
# set -o xtrace

# --- Global Variables ---
readonly SCRIPT_NAME="$(basename "${0}")"
readonly SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd)"
readonly LOG_FILE="/tmp/${SCRIPT_NAME}.log" # Example log file

# --- Functions ---

# Function to display usage and help message.
usage() {
  echo "Usage: ${SCRIPT_NAME} [OPTIONS] [ARGUMENTS]"
  echo
  echo "A template for new Bash scripts incorporating best practices."
  echo
  echo "Options:"
  echo "  -h, --help      Display this help message and exit."
  echo "  -v, --verbose   Enable verbose output."
  echo
  exit 0
}

# Function for logging messages.
log() {
  local level="${1}"
  local message="${2}"
  echo "$(date '+%Y-%m-%d %H:%M:%S') [${level}] ${message}" | tee -a "${LOG_FILE}" >&2
}

# Function to handle errors and exit.
error_exit() {
  local message="${1}"
  log "ERROR" "${message}"
  exit 1
}

# Function to check if running as root.
is_root() {
  [[ "${EUID}" -eq 0 ]]
}

# --- Main Script Logic ---

# Parse command-line options.
while [[ "${#}" -gt 0 ]]; do
  case "${1}" in
    -h | --help)
      usage
      ;;
    -v | --verbose)
      # Enable verbose logging if desired
      ;;
    *)
      # Handle other arguments
      ;;
  esac
  shift
done

# Example: Check for root privileges if needed.
# if ! is_root; then
#   error_exit "This script requires root privileges."
# fi

# Your script's main functionality goes here.
log "INFO" "Script ${SCRIPT_NAME} started."
# ... (add your script's core logic)
log "INFO" "Script ${SCRIPT_NAME} finished successfully."
