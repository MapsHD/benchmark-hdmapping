#!/bin/bash

# Script to run Faster-LIO (ROS1) benchmarks for ALL datasets
# Automatically discovers all sensor directories and processes them
#
# Usage: ./run_all_fasterlio.sh BASE_PATH
#   BASE_PATH: Base directory to search for datasets (required)

set -e

if [ -z "$1" ]; then
    echo "Error: BASE_PATH argument is required"
    echo ""
    echo "Usage: $0 BASE_PATH"
    exit 1
fi

BASE_PATH="$1"

# Start total time tracking
SCRIPT_START_TIME=$(date +%s)

echo "======================================"
echo "Running Faster-LIO (ROS1) benchmarks for all datasets"
echo "======================================"
echo "Base path: $BASE_PATH"
echo ""

# Function to get config name for a sensor
# NOTE: MandEye ROS1 bags use /livox/* topics for all sensors
get_config_for_sensor() {
    local sensor_name="$1"
    echo "avia"
}

# Find all sensor directories
SENSOR_DIRS=$(
    {
        find "$BASE_PATH" -type d -name "AVIA"
        find "$BASE_PATH" -type d -name "LivoxHAP"
        find "$BASE_PATH" -type d -name "LivoxMID360Arm"
        find "$BASE_PATH" -type d -name "LivoxMID360Stick"
        find "$BASE_PATH" -type d -name "HesaiBig"
        find "$BASE_PATH" -type d -name "HesaiSmall"
        find "$BASE_PATH" -type d -name "Ouster"
        find "$BASE_PATH" -type d -name "SICK"
    } | sort
)

if [ -z "$SENSOR_DIRS" ]; then
    echo "Error: No sensor directories found in $BASE_PATH"
    exit 1
fi

TOTAL=$(echo "$SENSOR_DIRS" | wc -l)
CURRENT=0

declare -a EXPERIMENT_NAMES
declare -a PROCESSING_TIMES
declare -a PROCESSING_STATUS
declare -a CONFIG_NAMES

echo "Found $TOTAL dataset(s):"
echo "======================================"
while IFS= read -r SENSOR_DIR; do
    SENSOR_NAME=$(basename "$SENSOR_DIR")
    EXPERIMENT_NAME=$(basename "$(dirname "$SENSOR_DIR")")
    CONFIG=$(get_config_for_sensor "$SENSOR_NAME")

    if [ -f "./methods/benchmark-Faster-LIO-to-HDMapping/configs/${CONFIG}.env" ]; then
        CONFIG_DISPLAY="$CONFIG"
    else
        CONFIG_DISPLAY="$CONFIG (missing)"
    fi

    echo "  - $EXPERIMENT_NAME/$SENSOR_NAME [$CONFIG_DISPLAY]: $SENSOR_DIR"
done <<< "$SENSOR_DIRS"
echo "======================================"
echo ""
read -p "Press Enter to continue"
echo ""

while IFS= read -r SENSOR_DIR; do
    CURRENT=$((CURRENT + 1))

    SENSOR_NAME=$(basename "$SENSOR_DIR")
    PARENT_NAME=$(basename "$(dirname "$SENSOR_DIR")")
    EXPERIMENT_NAME="${PARENT_NAME}/${SENSOR_NAME}"
    CONFIG=$(get_config_for_sensor "$SENSOR_NAME")

    INPUT_BAG_FILE="${SENSOR_DIR}/ros1bag/mandeye.bag"

    echo "======================================"
    echo "[$CURRENT/$TOTAL] Processing: $EXPERIMENT_NAME"
    echo "======================================"
    echo "Sensor Directory: $SENSOR_DIR"
    echo "Input Bag File: $INPUT_BAG_FILE"
    echo "Config: $CONFIG"
    echo ""

    CONFIG_FILE="./methods/benchmark-Faster-LIO-to-HDMapping/configs/${CONFIG}.env"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Warning: Config file does not exist: $CONFIG_FILE"
        echo "Skipping $EXPERIMENT_NAME..."
        echo ""
        EXPERIMENT_NAMES+=("$EXPERIMENT_NAME")
        PROCESSING_TIMES+=("N/A")
        PROCESSING_STATUS+=("SKIPPED (config missing)")
        CONFIG_NAMES+=("$CONFIG")
        continue
    fi

    if [ ! -f "$INPUT_BAG_FILE" ]; then
        echo "Warning: Bag file does not exist: $INPUT_BAG_FILE"
        echo "Skipping $EXPERIMENT_NAME..."
        echo ""
        EXPERIMENT_NAMES+=("$EXPERIMENT_NAME")
        PROCESSING_TIMES+=("N/A")
        PROCESSING_STATUS+=("SKIPPED (no bag)")
        CONFIG_NAMES+=("$CONFIG")
        continue
    fi

    echo "Running Faster-LIO benchmark for $EXPERIMENT_NAME with config: $CONFIG..."
    START_TIME=$(date +%s)

    if ./methods/benchmark-Faster-LIO-to-HDMapping/run_benchmark.sh "$CONFIG" "$INPUT_BAG_FILE"; then
        END_TIME=$(date +%s)
        ELAPSED=$((END_TIME - START_TIME))

        HOURS=$((ELAPSED / 3600))
        MINUTES=$(((ELAPSED % 3600) / 60))
        SECONDS=$((ELAPSED % 60))

        if [ $HOURS -gt 0 ]; then
            TIME_STR="${HOURS}h ${MINUTES}m ${SECONDS}s"
        elif [ $MINUTES -gt 0 ]; then
            TIME_STR="${MINUTES}m ${SECONDS}s"
        else
            TIME_STR="${SECONDS}s"
        fi

        EXPERIMENT_NAMES+=("$EXPERIMENT_NAME")
        PROCESSING_TIMES+=("$TIME_STR")
        PROCESSING_STATUS+=("SUCCESS")
        CONFIG_NAMES+=("$CONFIG")

        echo ""
        echo "Completed: $EXPERIMENT_NAME (Time: $TIME_STR)"
        echo ""
    else
        END_TIME=$(date +%s)
        ELAPSED=$((END_TIME - START_TIME))

        EXPERIMENT_NAMES+=("$EXPERIMENT_NAME")
        PROCESSING_TIMES+=("${ELAPSED}s")
        PROCESSING_STATUS+=("FAILED")
        CONFIG_NAMES+=("$CONFIG")

        echo ""
        echo "Failed: $EXPERIMENT_NAME"
        echo ""
    fi
done <<< "$SENSOR_DIRS"

echo "======================================"
echo "All Faster-LIO benchmarks completed!"
echo "Processed $CURRENT out of $TOTAL datasets"
echo "======================================"
echo ""
echo "SUMMARY - Processing Times:"
echo "======================================"

SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

for i in "${!EXPERIMENT_NAMES[@]}"; do
    STATUS="${PROCESSING_STATUS[$i]}"
    EXPERIMENT="${EXPERIMENT_NAMES[$i]}"
    TIME="${PROCESSING_TIMES[$i]}"
    CONFIG="${CONFIG_NAMES[$i]}"

    if [ "$STATUS" = "SUCCESS" ]; then
        SYMBOL="[OK]"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    elif [ "$STATUS" = "FAILED" ]; then
        SYMBOL="[FAIL]"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    else
        SYMBOL="[SKIP]"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    fi

    printf "  %s %-35s %-12s %10s  (%s)\n" "$SYMBOL" "$EXPERIMENT" "[$CONFIG]" "$TIME" "$STATUS"
done

echo "======================================"
echo "Statistics:"
echo "  Success: $SUCCESS_COUNT"
echo "  Failed:  $FAILED_COUNT"
echo "  Skipped: $SKIPPED_COUNT"
echo "  Total:   $TOTAL"
echo "======================================"
echo ""

SCRIPT_END_TIME=$(date +%s)
TOTAL_ELAPSED=$((SCRIPT_END_TIME - SCRIPT_START_TIME))

TOTAL_HOURS=$((TOTAL_ELAPSED / 3600))
TOTAL_MINUTES=$(((TOTAL_ELAPSED % 3600) / 60))
TOTAL_SECONDS=$((TOTAL_ELAPSED % 60))

if [ $TOTAL_HOURS -gt 0 ]; then
    TOTAL_TIME_STR="${TOTAL_HOURS}h ${TOTAL_MINUTES}m ${TOTAL_SECONDS}s"
elif [ $TOTAL_MINUTES -gt 0 ]; then
    TOTAL_TIME_STR="${TOTAL_MINUTES}m ${TOTAL_SECONDS}s"
else
    TOTAL_TIME_STR="${TOTAL_SECONDS}s"
fi

echo "Total execution time: $TOTAL_TIME_STR"
echo "======================================"

