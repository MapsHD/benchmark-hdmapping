#!/bin/bash

# Script to run benchmarks for all Livox datasets
# Automatically discovers all Livox sensor directories and processes them
# Livox sensors: AVIA, LivoxHAP, LivoxMID360Arm, LivoxMID360Stick
# All use the same avia config (same topics in rosbag)
#
# Usage: ./run_all_avia.sh BASE_PATH
#   BASE_PATH: Base directory to search for Livox datasets (required)

set -e

# Check if BASE_PATH argument is provided
if [ -z "$1" ]; then
    echo "Error: BASE_PATH argument is required"
    echo ""
    echo "Usage: $0 BASE_PATH"
    echo ""
    echo "Arguments:"
    echo "  BASE_PATH    Base directory to search for Livox datasets"
    echo ""
    echo "Example:"
    echo "  $0 /path/to/benchmark-data/lowcost-experiment"
    exit 1
fi

BASE_PATH="$1"

# Start total time tracking
SCRIPT_START_TIME=$(date +%s)

echo "======================================"
echo "Running benchmarks for all Livox datasets"
echo "======================================"
echo "Base path: $BASE_PATH"
echo ""

# Find all Livox sensor directories and merge into single list
LIVOX_DIRS=$(
    {
        find "$BASE_PATH" -type d -name "AVIA"
        find "$BASE_PATH" -type d -name "LivoxHAP"
        find "$BASE_PATH" -type d -name "LivoxMID360Arm"
        find "$BASE_PATH" -type d -name "LivoxMID360Stick"
    } | sort
)

if [ -z "$LIVOX_DIRS" ]; then
    echo "Error: No Livox sensor directories found in $BASE_PATH"
    exit 1
fi

# Count total directories
TOTAL=$(echo "$LIVOX_DIRS" | wc -l)
CURRENT=0

# Arrays to store results
declare -a EXPERIMENT_NAMES
declare -a PROCESSING_TIMES
declare -a PROCESSING_STATUS

echo "Found $TOTAL Livox dataset(s):"
echo "======================================"
for LIVOX_DIR in $LIVOX_DIRS; do
    SENSOR_NAME=$(basename "$LIVOX_DIR")
    EXPERIMENT_NAME=$(basename $(dirname "$LIVOX_DIR"))
    echo "  - $EXPERIMENT_NAME/$SENSOR_NAME: $LIVOX_DIR"
done
echo "======================================"
echo ""
read -p "Press Enter to continue"
echo ""

# Process each Livox directory
for LIVOX_DIR in $LIVOX_DIRS; do
    CURRENT=$((CURRENT + 1))
    
    # Extract the sensor name (e.g., "AVIA", "LivoxHAP", etc.)
    SENSOR_NAME=$(basename "$LIVOX_DIR")
    
    # Extract the experiment name (e.g., "Pipes", "Spruce-old", etc.)
    PARENT_NAME=$(basename $(dirname "$LIVOX_DIR"))
    
    # Combined identifier for display
    EXPERIMENT_NAME="${PARENT_NAME}/${SENSOR_NAME}"
    
    # Construct the input bag directory path
    INPUT_BAG_DIRECTORY="${LIVOX_DIR}/ros2bag/mandeye_bag/"
    
    echo "======================================"
    echo "[$CURRENT/$TOTAL] Processing: $EXPERIMENT_NAME"
    echo "======================================"
    echo "Livox Directory: $LIVOX_DIR"
    echo "Input Bag Directory: $INPUT_BAG_DIRECTORY"
    echo ""
    
    # Check if the bag directory exists
    if [ ! -d "$INPUT_BAG_DIRECTORY" ]; then
        echo "Warning: Bag directory does not exist: $INPUT_BAG_DIRECTORY"
        echo "Skipping $EXPERIMENT_NAME..."
        echo ""
        EXPERIMENT_NAMES+=("$EXPERIMENT_NAME")
        PROCESSING_TIMES+=("N/A")
        PROCESSING_STATUS+=("SKIPPED")
        continue
    fi
    
    # Run the benchmark and track time
    echo "Running benchmark for $EXPERIMENT_NAME..."
    START_TIME=$(date +%s)
    
    if ./methods/benchmark-GenZ-ICP-to-HDMapping/run_benchmark.sh avia "$INPUT_BAG_DIRECTORY"; then
        END_TIME=$(date +%s)
        ELAPSED=$((END_TIME - START_TIME))
        
        # Convert to human-readable format
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
        
        echo ""
        echo "✓ Completed: $EXPERIMENT_NAME (Time: $TIME_STR)"
        echo ""
    else
        END_TIME=$(date +%s)
        ELAPSED=$((END_TIME - START_TIME))
        EXPERIMENT_NAMES+=("$EXPERIMENT_NAME")
        PROCESSING_TIMES+=("${ELAPSED}s")
        PROCESSING_STATUS+=("FAILED")
        
        echo ""
        echo "✗ Failed: $EXPERIMENT_NAME"
        echo ""
    fi
done

echo "======================================"
echo "All Livox benchmarks completed!"
echo "Processed $CURRENT out of $TOTAL datasets"
echo "======================================"
echo ""
echo "SUMMARY - Processing Times:"
echo "======================================"

# Calculate statistics
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

for i in "${!EXPERIMENT_NAMES[@]}"; do
    STATUS="${PROCESSING_STATUS[$i]}"
    EXPERIMENT="${EXPERIMENT_NAMES[$i]}"
    TIME="${PROCESSING_TIMES[$i]}"
    
    # Status symbol
    if [ "$STATUS" = "SUCCESS" ]; then
        SYMBOL="✓"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    elif [ "$STATUS" = "FAILED" ]; then
        SYMBOL="✗"
        FAILED_COUNT=$((FAILED_COUNT + 1))
    else
        SYMBOL="⊘"
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    fi
    
    printf "  %s %-30s %10s  (%s)\n" "$SYMBOL" "$EXPERIMENT" "$TIME" "$STATUS"
done

echo "======================================"
echo "Statistics:"
echo "  Success: $SUCCESS_COUNT"
echo "  Failed:  $FAILED_COUNT"
echo "  Skipped: $SKIPPED_COUNT"
echo "  Total:   $TOTAL"
echo "======================================"
echo ""

# Calculate and display total time
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

