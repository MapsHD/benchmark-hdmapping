#!/bin/bash

# Script to run I2EKF-LO (ROS1) benchmarks for ALL datasets
# Usage: ./run_all_i2ekflo.sh BASE_PATH

set -e

if [ -z "$1" ]; then
    echo "Error: BASE_PATH argument is required"
    echo "Usage: $0 BASE_PATH"
    exit 1
fi

BASE_PATH="$1"
SCRIPT_START_TIME=$(date +%s)

echo "======================================"
echo "Running I2EKF-LO (ROS1) benchmarks for all datasets"
echo "======================================"
echo "Base path: $BASE_PATH"
echo ""

get_config_for_sensor() { echo "avia"; }

SENSOR_DIRS=$(find "$BASE_PATH" -type d \( -name "AVIA" -o -name "LivoxHAP" -o -name "LivoxMID360Arm" -o -name "LivoxMID360Stick" -o -name "HesaiBig" -o -name "HesaiSmall" -o -name "Ouster" -o -name "SICK" \) | sort)

if [ -z "$SENSOR_DIRS" ]; then
    echo "Error: No sensor directories found in $BASE_PATH"
    exit 1
fi

TOTAL=$(echo "$SENSOR_DIRS" | wc -l)
CURRENT=0
declare -a EXPERIMENT_NAMES PROCESSING_TIMES PROCESSING_STATUS CONFIG_NAMES

echo "Found $TOTAL dataset(s). Press Enter to continue..."
read

while IFS= read -r SENSOR_DIR; do
    CURRENT=$((CURRENT + 1))
    SENSOR_NAME=$(basename "$SENSOR_DIR")
    PARENT_NAME=$(basename "$(dirname "$SENSOR_DIR")")
    EXPERIMENT_NAME="${PARENT_NAME}/${SENSOR_NAME}"
    CONFIG=$(get_config_for_sensor "$SENSOR_NAME")
    INPUT_BAG_FILE="${SENSOR_DIR}/ros1bag/mandeye.bag"

    echo "[$CURRENT/$TOTAL] Processing: $EXPERIMENT_NAME"

    if [ ! -f "$INPUT_BAG_FILE" ]; then
        echo "Skipping (no bag): $EXPERIMENT_NAME"
        EXPERIMENT_NAMES+=("$EXPERIMENT_NAME"); PROCESSING_TIMES+=("N/A"); PROCESSING_STATUS+=("SKIPPED"); CONFIG_NAMES+=("$CONFIG")
        continue
    fi

    START_TIME=$(date +%s)
    if ./methods/benchmark-I2EKF-LO-to-HDMapping/run_benchmark.sh "$CONFIG" "$INPUT_BAG_FILE"; then
        END_TIME=$(date +%s); ELAPSED=$((END_TIME - START_TIME))
        EXPERIMENT_NAMES+=("$EXPERIMENT_NAME"); PROCESSING_TIMES+=("${ELAPSED}s"); PROCESSING_STATUS+=("SUCCESS"); CONFIG_NAMES+=("$CONFIG")
        echo "Completed: $EXPERIMENT_NAME (${ELAPSED}s)"
    else
        END_TIME=$(date +%s); ELAPSED=$((END_TIME - START_TIME))
        EXPERIMENT_NAMES+=("$EXPERIMENT_NAME"); PROCESSING_TIMES+=("${ELAPSED}s"); PROCESSING_STATUS+=("FAILED"); CONFIG_NAMES+=("$CONFIG")
        echo "Failed: $EXPERIMENT_NAME"
    fi
done <<< "$SENSOR_DIRS"

echo "======================================"
echo "All I2EKF-LO benchmarks completed! Processed $CURRENT/$TOTAL"
echo "======================================"
for i in "${!EXPERIMENT_NAMES[@]}"; do
    printf "  %-35s %10s  (%s)\n" "${EXPERIMENT_NAMES[$i]}" "${PROCESSING_TIMES[$i]}" "${PROCESSING_STATUS[$i]}"
done
SCRIPT_END_TIME=$(date +%s)
echo "Total time: $((SCRIPT_END_TIME - SCRIPT_START_TIME))s"

