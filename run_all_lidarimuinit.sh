#!/bin/bash

# Script to run LiDAR-IMU-Init (ROS1) benchmarks for ALL datasets
set -e

if [ -z "$1" ]; then echo "Usage: $0 BASE_PATH"; exit 1; fi

BASE_PATH="$1"
SCRIPT_START_TIME=$(date +%s)

echo "======================================"
echo "Running LiDAR-IMU-Init benchmarks"
echo "Base path: $BASE_PATH"
echo "======================================"

SENSOR_DIRS=$(find "$BASE_PATH" -type d \( -name "AVIA" -o -name "LivoxHAP" -o -name "LivoxMID360Arm" -o -name "LivoxMID360Stick" -o -name "HesaiBig" -o -name "HesaiSmall" -o -name "Ouster" -o -name "SICK" \) | sort)

if [ -z "$SENSOR_DIRS" ]; then echo "No sensor directories found"; exit 1; fi

TOTAL=$(echo "$SENSOR_DIRS" | wc -l)
CURRENT=0
declare -a RESULTS

echo "Found $TOTAL dataset(s). Press Enter to continue..."; read

while IFS= read -r SENSOR_DIR; do
    CURRENT=$((CURRENT + 1))
    EXPERIMENT_NAME="$(basename "$(dirname "$SENSOR_DIR")")/$(basename "$SENSOR_DIR")"
    INPUT_BAG_FILE="${SENSOR_DIR}/ros1bag/mandeye.bag"

    echo "[$CURRENT/$TOTAL] $EXPERIMENT_NAME"

    if [ ! -f "$INPUT_BAG_FILE" ]; then
        RESULTS+=("SKIP $EXPERIMENT_NAME"); continue
    fi

    START_TIME=$(date +%s)
    if ./methods/benchmark-LiDAR-IMU-Init-to-HDMapping/run_benchmark.sh avia "$INPUT_BAG_FILE"; then
        RESULTS+=("OK   $EXPERIMENT_NAME $(($(date +%s) - START_TIME))s")
    else
        RESULTS+=("FAIL $EXPERIMENT_NAME")
    fi
done <<< "$SENSOR_DIRS"

echo "======================================"
echo "Summary:"
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo "Total time: $(($(date +%s) - SCRIPT_START_TIME))s"

