#!/bin/bash

# Script to run KISS-ICP benchmarks for ALL datasets
# Automatically discovers all sensor directories and processes them
# Sensors: AVIA, LivoxHAP, LivoxMID360Arm, LivoxMID360Stick, Hesai big, Hesai small, Ouster, SICK
#
# Usage: ./run_all_kiss.sh BASE_PATH
#   BASE_PATH: Base directory to search for datasets (required)

set -e

# Check if BASE_PATH argument is provided
if [ -z "$1" ]; then
    echo "Error: BASE_PATH argument is required"
    echo ""
    echo "Usage: $0 BASE_PATH"
    echo ""
    echo "Arguments:"
    echo "  BASE_PATH    Base directory to search for datasets"
    echo ""
    echo "Example:"
    echo "  $0 /path/to/benchmark-data/lowcost-experiment"
    exit 1
fi

BASE_PATH="$1"

# Start total time tracking
SCRIPT_START_TIME=$(date +%s)

echo "======================================"
echo "Running KISS-ICP benchmarks for all datasets"
echo "======================================"
echo "Base path: $BASE_PATH"
echo ""

# Function to get config name for a sensor
# Returns the config name or "NONE" if no config exists
# NOTE: All sensors in this benchmark use /livox/pointcloud topic (recorded via MandEye)
#       so they all use the "avia" config
get_config_for_sensor() {
    local sensor_name="$1"
    local sensor_lower=$(echo "$sensor_name" | tr '[:upper:]' '[:lower:]')
    
    echo "avia" # all sensors use the same config
}

# Find all sensor directories
# Directory names are case-sensitive as found in the dataset
SENSOR_DIRS=$(
    {
        # Livox sensors
        find "$BASE_PATH" -type d -name "AVIA"
        find "$BASE_PATH" -type d -name "LivoxHAP"
        find "$BASE_PATH" -type d -name "LivoxMID360Arm"
        find "$BASE_PATH" -type d -name "LivoxMID360Stick"
        # Hesai sensors
        find "$BASE_PATH" -type d -name "HesaiBig"
        find "$BASE_PATH" -type d -name "HesaiSmall"
        # Ouster sensor
        find "$BASE_PATH" -type d -name "Ouster"
        # SICK sensor
        find "$BASE_PATH" -type d -name "SICK"
    } | sort
)

if [ -z "$SENSOR_DIRS" ]; then
    echo "Error: No sensor directories found in $BASE_PATH"
    exit 1
fi

# Count total directories
TOTAL=$(echo "$SENSOR_DIRS" | wc -l)
CURRENT=0

# Arrays to store results
declare -a EXPERIMENT_NAMES
declare -a PROCESSING_TIMES
declare -a PROCESSING_STATUS
declare -a CONFIG_NAMES

echo "Found $TOTAL dataset(s):"
echo "======================================"
for SENSOR_DIR in $SENSOR_DIRS; do
    SENSOR_NAME=$(basename "$SENSOR_DIR")
    EXPERIMENT_NAME=$(basename $(dirname "$SENSOR_DIR"))
    CONFIG=$(get_config_for_sensor "$SENSOR_NAME")
    
    if [ "$CONFIG" = "NONE" ]; then
        CONFIG_DISPLAY="(unknown)"
    elif [ -f "./methods/benchmark-KISS-ICP-to-HDMapping/configs/${CONFIG}.env" ]; then
        CONFIG_DISPLAY="$CONFIG"
    else
        CONFIG_DISPLAY="$CONFIG (missing)"
    fi
    
    echo "  - $EXPERIMENT_NAME/$SENSOR_NAME [$CONFIG_DISPLAY]: $SENSOR_DIR"
done
echo "======================================"
echo ""
read -p "Press Enter to continue"
echo ""

# Process each sensor directory
for SENSOR_DIR in $SENSOR_DIRS; do
    CURRENT=$((CURRENT + 1))
    
    # Extract the sensor name
    SENSOR_NAME=$(basename "$SENSOR_DIR")
    
    # Extract the experiment name
    PARENT_NAME=$(basename $(dirname "$SENSOR_DIR"))
    
    # Combined identifier for display
    EXPERIMENT_NAME="${PARENT_NAME}/${SENSOR_NAME}"
    
    # Get config for this sensor
    CONFIG=$(get_config_for_sensor "$SENSOR_NAME")
    
    # Construct the input bag directory path (new layout: ros2bag is the bag dir)
    INPUT_BAG_DIRECTORY="${SENSOR_DIR}/ros2bag/"
    
    echo "======================================"
    echo "[$CURRENT/$TOTAL] Processing: $EXPERIMENT_NAME"
    echo "======================================"
    echo "Sensor Directory: $SENSOR_DIR"
    echo "Input Bag Directory: $INPUT_BAG_DIRECTORY"
    echo "Config: $CONFIG"
    echo ""
    
    # Check if config is known
    if [ "$CONFIG" = "NONE" ]; then
        echo "Warning: No config mapping for sensor: $SENSOR_NAME"
        echo "Skipping $EXPERIMENT_NAME..."
        echo ""
        EXPERIMENT_NAMES+=("$EXPERIMENT_NAME")
        PROCESSING_TIMES+=("N/A")
        PROCESSING_STATUS+=("SKIPPED (no config mapping)")
        CONFIG_NAMES+=("$CONFIG")
        continue
    fi
    
    # Check if config file exists
    CONFIG_FILE="./methods/benchmark-KISS-ICP-to-HDMapping/configs/${CONFIG}.env"
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
    
    # Check if the bag directory exists
    if [ ! -d "$INPUT_BAG_DIRECTORY" ]; then
        echo "Warning: Bag directory does not exist: $INPUT_BAG_DIRECTORY"
        echo "Skipping $EXPERIMENT_NAME..."
        echo ""
        EXPERIMENT_NAMES+=("$EXPERIMENT_NAME")
        PROCESSING_TIMES+=("N/A")
        PROCESSING_STATUS+=("SKIPPED (no bag)")
        CONFIG_NAMES+=("$CONFIG")
        continue
    fi
    
    # Run the benchmark and track time
    echo "Running KISS-ICP benchmark for $EXPERIMENT_NAME with config: $CONFIG..."
    START_TIME=$(date +%s)
    
    if ./methods/benchmark-KISS-ICP-to-HDMapping/run_benchmark.sh "$CONFIG" "$INPUT_BAG_DIRECTORY"; then
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
done

echo "======================================"
echo "All KISS-ICP benchmarks completed!"
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
    CONFIG="${CONFIG_NAMES[$i]}"
    
    # Status symbol
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
