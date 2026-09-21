#!/system/bin/sh
# ============================================
# ZRAM Turbo - Core Setup Script
# Optimized for OPPO A15 / MT6765 / 2-3GB RAM
# ============================================

LOG=/data/local/tmp/zram_tune.log
log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG
}

log_msg "=== ZRAM Turbo v2.0 starting ==="

# ============================================
# DETECT TOTAL RAM (in KB)
# ============================================
TOTAL_RAM_KB=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
if [ -z "$TOTAL_RAM_KB" ]; then
    log_msg "ERROR: Cannot read MemTotal"
    exit 1
fi

TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
log_msg "Total RAM: ${TOTAL_RAM_MB}MB (${TOTAL_RAM_KB}KB)"

# ============================================
# CALCULATE ZRAM SIZE
# ============================================
# Fixed 2GB zram for maximum swap headroom
# With lz4/lz4hc compression this expands to
# ~4-6GB effective virtual memory

ZRAM_SIZE_MB=2048

ZRAM_SIZE_BYTES=$((ZRAM_SIZE_MB * 1024 * 1024))
log_msg "ZRAM size: ${ZRAM_SIZE_MB}MB (${ZRAM_SIZE_BYTES} bytes)"

# ============================================
# DETERMINE BEST COMPRESSION ALGORITHM
# ============================================
# Priority: lz4hc > lz4 > zstd > lzo
COMP_ALGO=""

if [ -f /sys/block/zram0/comp_algorithm ]; then
    ALGO_LIST=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null)

    if echo "$ALGO_LIST" | grep -q "lz4hc"; then
        COMP_ALGO="lz4hc"
    elif echo "$ALGO_LIST" | grep -q "lz4"; then
        COMP_ALGO="lz4"
    elif echo "$ALGO_LIST" | grep -q "zstd"; then
        COMP_ALGO="zstd"
    elif echo "$ALGO_LIST" | grep -q "lzo"; then
        COMP_ALGO="lzo"
    fi
fi

if [ -z "$COMP_ALGO" ]; then
    COMP_ALGO="lz4"
    log_msg "WARN: Could not detect algo list, defaulting to lz4"
fi

log_msg "Compression algorithm: $COMP_ALGO"

# ============================================
# CHECK IF ZRAM ALREADY EXISTS
# ============================================
if [ -d /sys/block/zram0 ]; then
    CURRENT_DISKSIZE=$(cat /sys/block/zram0/disksize 2>/dev/null)
    CURRENT_ALGO=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null)
    log_msg "zram0 already exists: disksize=$CURRENT_DISKSIZE algo=$CURRENT_ALGO"

    # If already configured correctly, skip setup
    if [ "$CURRENT_DISKSIZE" = "$ZRAM_SIZE_BYTES" ] && [ "$CURRENT_ALGO" = "$COMP_ALGO" ]; then
        log_msg "ZRAM already configured correctly, skipping"
        exit 0
    fi

    # Reset zram
    swapoff /dev/block/zram0 2>/dev/null
    echo 1 > /sys/block/zram0/reset 2>/dev/null
    sleep 1
fi

# ============================================
# CONFIGURE ZRAM
# ============================================

# Set algorithm first (before disksize)
echo $COMP_ALGO > /sys/block/zram0/comp_algorithm 2>/dev/null
log_msg "Set comp_algorithm to $COMP_ALGO"

# Set disk size
echo $ZRAM_SIZE_BYTES > /sys/block/zram0/disksize 2>/dev/null
ACTUAL_DISKSIZE=$(cat /sys/block/zram0/disksize 2>/dev/null)
log_msg "Set disksize: requested=$ZRAM_SIZE_BYTES actual=$ACTUAL_DISKSIZE"

if [ "$ACTUAL_DISKSIZE" != "$ZRAM_SIZE_BYTES" ]; then
    log_msg "WARN: disksize mismatch, trying alternative method"
    echo 0 > /sys/block/zram0/reset 2>/dev/null
    sleep 1
    echo $COMP_ALGO > /sys/block/zram0/comp_algorithm 2>/dev/null
    echo $ZRAM_SIZE_BYTES > /sys/block/zram0/disksize 2>/dev/null
    ACTUAL_DISKSIZE=$(cat /sys/block/zram0/disksize 2>/dev/null)
    log_msg "Retry result: disksize=$ACTUAL_DISKSIZE"
fi

# ============================================
# SETUP SWAP
# ============================================

# Format as swap
mkswap /dev/block/zram0 2>/dev/null
if [ $? -ne 0 ]; then
    log_msg "ERROR: mkswap failed"
    exit 1
fi
log_msg "mkswap completed"

# Activate swap with high priority (100)
# -p 100 = high priority so zram is used first
# swapon flags: -d = discard, -p = priority
swapon /dev/block/zram0 -p 100 2>/dev/null
if [ $? -ne 0 ]; then
    log_msg "ERROR: swapon failed"
    exit 1
fi
log_msg "Swap activated with priority 100"

# ============================================
# VERIFY SWAP IS ACTIVE
# ============================================
SWAP_INFO=$(cat /proc/swaps 2>/dev/null | grep zram0)
log_msg "Swap status: $SWAP_INFO"

# ============================================
# TUNE VM SETTINGS
# ============================================

# swappiness - high value = use zram aggressively
# 100 = default for zram, 160 = more aggressive
echo 160 > /proc/sys/vm/swappiness 2>/dev/null
log_msg "swappiness set to 160"

# page-cluster = 0 (no readahead, optimal for zram)
echo 0 > /proc/sys/vm/page-cluster 2>/dev/null
log_msg "page-cluster set to 0"

# dirty ratios
echo 15 > /proc/sys/vm/dirty_ratio 2>/dev/null
echo 5 > /proc/sys/vm/dirty_background_ratio 2>/dev/null
log_msg "dirty ratios set"

# vfs_cache_pressure - keep dentries/inodes in memory longer
echo 50 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
log_msg "vfs_cache_pressure set to 50"

# ============================================
# ZRAM QUEUE OPTIMIZATION
# ============================================
if [ -d /sys/block/zram0/queue ]; then
    echo 256 > /sys/block/zram0/queue/nr_requests 2>/dev/null
    echo 2 > /sys/block/zram0/queue/nomerges 2>/dev/null
    echo 0 > /sys/block/zram0/queue/add_random 2>/dev/null
    echo 1 > /sys/block/zram0/queue/rq_affinity 2>/dev/null

    # Try to set best scheduler
    for sched in none bfq mq-deadline; do
        echo $sched > /sys/block/zram0/queue/scheduler 2>/dev/null
        if [ $? -eq 0 ]; then
            log_msg "Scheduler set to: $sched"
            break
        fi
    done
fi

# ============================================
# FINAL STATUS
# ============================================
log_msg "=== ZRAM Turbo setup complete ==="
log_msg "Size: ${ZRAM_SIZE_MB}MB | Algo: $COMP_ALGO | Swappiness: 160"
log_msg "Swap status: $(cat /proc/swaps 2>/dev/null)"

exit 0
