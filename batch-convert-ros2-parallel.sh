#!/bin/bash

# Script to batch convert all Mandeye data directories to ROS2 bags in parallel
# Usage: ./batch-convert-ros2-parallel.sh <root_directory> [options]
#
# This uses the Docker-based converter in:
#   tools/mandeye_to_bag/mandeye-to-bag.sh

set -e

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <root_directory> [--workers <number>] [--dry-run] [--lines <number>] [--type <pointcloud2/livox>]"
    echo ""
    echo "Arguments:"
    echo "  root_directory          - Root directory to search for Mandeye data"
    echo ""
    echo "Options:"
    echo "  --workers <number>      - Number of parallel workers (default: 16)"
    echo "  --dry-run               - Show what would be processed without running conversions"
    echo "  --lines <number>        - Number of lines (default 8, for mid360)"
    echo "  --type <type>           - Message type: pointcloud2 or livox (default pointcloud2)"
    echo ""
    echo "Example:"
    echo "  $0 ~/data/benchmark-joseph --workers 16"
    echo "  $0 ~/data/benchmark-joseph --workers 16 --dry-run"
    echo "  $0 ~/data/benchmark-joseph --workers 16 --lines 8 --type pointcloud2"
    exit 1
fi

ROOT_DIR="$1"
shift

# Get absolute path
ROOT_DIR=$(realpath "$ROOT_DIR")

# Parse options
DRY_RUN=false
WORKERS=16
EXTRA_ARGS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --workers)
            WORKERS="$2"
            shift 2
            ;;
        *)
            EXTRA_ARGS="$EXTRA_ARGS $1"
            shift
            ;;
    esac
done

# Check if root directory exists
if [ ! -d "$ROOT_DIR" ]; then
    echo "Error: Root directory '$ROOT_DIR' does not exist"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONVERTER_SCRIPT="$SCRIPT_DIR/tools/mandeye_to_bag/mandeye-to-bag.sh"

if [ ! -f "$CONVERTER_SCRIPT" ]; then
    echo "Error: ROS2 converter script not found: $CONVERTER_SCRIPT"
    echo "Did you initialize submodules? (tools/mandeye_to_bag is a submodule)"
    exit 1
fi

echo "============================================"
if [ "$DRY_RUN" = true ]; then
    echo "Parallel Mandeye to ROS2 Bag Conversion (DRY RUN)"
else
    echo "Parallel Mandeye to ROS2 Bag Conversion"
fi
echo "============================================"
echo "Root directory: $ROOT_DIR"
echo "Workers: $WORKERS"
if [ "$DRY_RUN" = true ]; then
    echo "Mode: DRY RUN (no conversions will be performed)"
fi
echo "Extra arguments: $EXTRA_ARGS"
echo ""

# Find all unique directories containing imu*.csv files
echo "Searching for directories with IMU CSV files..."
DIRS=$(find "$ROOT_DIR" -name 'imu*.csv' -printf '%h\n' | sort -u)

if [ -z "$DIRS" ]; then
    echo "No directories with imu*.csv files found!"
    exit 1
fi

# Count directories
DIR_COUNT=$(echo "$DIRS" | wc -l)
echo "Found $DIR_COUNT directories to process"
echo ""

if [ "$DRY_RUN" = true ]; then
    # Dry run - just list what would be done
    echo "============================================"
    echo "Dry Run - Would process the following:"
    echo "============================================"
    CURRENT=0
    while IFS= read -r INPUT_DIR; do
        CURRENT=$((CURRENT + 1))
        OUTPUT_DIR="$INPUT_DIR/ros2bag"
        OUTPUT_BAG="$OUTPUT_DIR"
        echo "[$CURRENT/$DIR_COUNT] $INPUT_DIR"
        echo "  -> $OUTPUT_BAG"
    done <<< "$DIRS"
    echo ""
    echo "Would run with $WORKERS parallel workers"
else
    # Function to process a single directory
    process_dir() {
        local INPUT_DIR="$1"
        local CONVERTER_SCRIPT="$2"
        local EXTRA_ARGS="$3"

        OUTPUT_DIR="$INPUT_DIR/ros2bag"
        OUTPUT_BAG="$OUTPUT_DIR"

        mkdir -p "$OUTPUT_DIR"

        # Run conversion
        if "$CONVERTER_SCRIPT" "$INPUT_DIR" "$OUTPUT_BAG" $EXTRA_ARGS 2>&1; then
            echo "✓ SUCCESS: $INPUT_DIR"
            return 0
        else
            echo "✗ FAILED: $INPUT_DIR"
            return 1
        fi
    }

    # Export function and variables for parallel execution
    export -f process_dir
    export CONVERTER_SCRIPT
    export EXTRA_ARGS

    # Check if GNU parallel is available
    if command -v parallel &> /dev/null; then
        echo "Using GNU parallel with $WORKERS workers..."
        echo "============================================"
        echo ""

        # Use GNU parallel for better progress tracking and control
        echo "$DIRS" | parallel --jobs "$WORKERS" --progress --joblog /tmp/batch-convert-ros2-$$.log \
            process_dir {} "$CONVERTER_SCRIPT" "$EXTRA_ARGS"

        PARALLEL_EXIT=$?

        echo ""
        echo "============================================"
        echo "Parallel Conversion Complete"
        echo "============================================"

        # Parse joblog for statistics
        if [ -f /tmp/batch-convert-ros2-$$.log ]; then
            SUCCESS=$(awk 'NR>1 && $7==0 {count++} END {print count+0}' /tmp/batch-convert-ros2-$$.log)
            FAILED=$(awk 'NR>1 && $7!=0 {count++} END {print count+0}' /tmp/batch-convert-ros2-$$.log)
            echo "Total directories: $DIR_COUNT"
            echo "Successful: $SUCCESS"
            echo "Failed: $FAILED"
            rm -f /tmp/batch-convert-ros2-$$.log
        fi

        exit $PARALLEL_EXIT

    elif command -v xargs &> /dev/null; then
        echo "GNU parallel not found, using xargs with $WORKERS workers..."
        echo "Note: Install GNU parallel for better progress tracking (apt install parallel)"
        echo "============================================"
        echo ""

        # Fallback to xargs -P
        echo "$DIRS" | xargs -P "$WORKERS" -I {} bash -c 'process_dir "$@"' _ {} "$CONVERTER_SCRIPT" "$EXTRA_ARGS"

        echo ""
        echo "============================================"
        echo "Parallel Conversion Complete"
        echo "============================================"
        echo "Total directories: $DIR_COUNT"
        echo "(Use GNU parallel for detailed statistics)"

    else
        echo "Error: Neither GNU parallel nor xargs found!"
        echo "Please install GNU parallel: sudo apt install parallel"
        exit 1
    fi
fi

echo ""

