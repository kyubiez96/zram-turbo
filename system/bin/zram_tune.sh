#!/system/bin/sh
# ============================================
# ZRAM Turbo v2.1 - Core Setup Script
# Fixed: Use Magisk busybox for swapon/mkswap
# ============================================

LOG=/data/local/tmp/zram_tune.log

# Use Magisk's busybox (has swapon, mkswap, awk)
export PATH=/data/adb/magisk:/system/bin:/system/xbin:$PATH

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG
}

log_msg "=== ZRAM Turbo v2.1 starting ==="

# ============================================
# DETECT TOTAL RAM (in KB)
# ============================================
TOTAL_RAM_KB=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
if [ -z "$TOTAL_RAM_KB" ]; then
    # Fallback: use grep + cut if awk fails
    TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo 2>/dev/null | tr -s ' ' | cut -d' ' -f2)
fi

if [ -z "$TOTAL_RAM_KB" ]; then
    log_msg "ERROR: Cannot read MemTotal"
    exit 1
fi

TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
log_msg "Total RAM: ${TOTAL_RAM_MB}MB (${TOTAL_RAM_KB}KB)"

# ============================================
# ZRAM SIZE: Fixed 2GB
# ============================================
ZRAM_SIZE_MB=2048
ZRAM_SIZE_BYTES=$((ZRAM_SIZE_MB * 1024 * 1024))
log_msg "ZRAM size: ${ZRAM_SIZE_MB}MB (${ZRAM_SIZE_BYTES} bytes)"

# ============================================
# DETERMINE BEST COMPRESSION ALGORITHM
# ============================================
COMP_ALGO="lz4"

if [ -f /sys/block/zram0/comp_algorithm ]; then
    ALGO_LIST=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null)

    if echo "$ALGO_LIST" | grep -q "lz4hc"; then
        COMP_ALGO="lz4hc"
    elif echo "$ALGO_LIST" | grep -q "zstd"; then
        COMP_ALGO="zstd"
    elif echo "$ALGO_LIST" | grep -q "lzo"; then
        COMP_ALGO="lzo"
    fi
fi

log_msg "Compression algorithm: $COMP_ALGO"

# ============================================
# CHECK IF ZRAM ALREADY CONFIGURED
# ============================================
if [ -d /sys/block/zram0 ]; then
    CURRENT_DISKSIZE=$(cat /sys/block/zram0/disksize 2>/dev/null)
    CURRENT_SWAP=$(grep zram0 /proc/swaps 2>/dev/null)

    if [ "$CURRENT_DISKSIZE" = "$ZRAM_SIZE_BYTES" ] && [ -n "$CURRENT_SWAP" ]; then
        log_msg "ZRAM already active (${CURRENT_DISKSIZE} bytes), skipping"
        exit 0
    fi

    log_msg "zram0 exists: disksize=$CURRENT_DISKSIZE swap=$CURRENT_SWAP"
    # Reset zram
    swapoff /dev/block/zram0 2>/dev/null
    echo 1 > /sys/block/zram0/reset 2>/dev/null
    sleep 1
fi

# ============================================
# CONFIGURE ZRAM
# ============================================
echo $COMP_ALGO > /sys/block/zram0/comp_algorithm 2>/dev/null
log_msg "Set comp_algorithm to $COMP_ALGO"

echo $ZRAM_SIZE_BYTES > /sys/block/zram0/disksize 2>/dev/null
ACTUAL_DISKSIZE=$(cat /sys/block/zram0/disksize 2>/dev/null)
log_msg "Set disksize: requested=$ZRAM_SIZE_BYTES actual=$ACTUAL_DISKSIZE"

if [ "$ACTUAL_DISKSIZE" != "$ZRAM_SIZE_BYTES" ]; then
    log_msg "WARN: disksize mismatch, retrying..."
    echo 0 > /sys/block/zram0/reset 2>/dev/null
    sleep 1
    echo $COMP_ALGO > /sys/block/zram0/comp_algorithm 2>/dev/null
    echo $ZRAM_SIZE_BYTES > /sys/block/zram0/disksize 2>/dev/null
    ACTUAL_DISKSIZE=$(cat /sys/block/zram0/disksize 2>/dev/null)
    log_msg "Retry: disksize=$ACTUAL_DISKSIZE"
fi

# ============================================
# SETUP SWAP
# Use /system/bin/mkswap and /system/bin/swapon
# (BusyBox swapon doesn't support -p priority flag)
# ============================================

log_msg "Formatting zram0 as swap..."
/system/bin/mkswap /dev/block/zram0 2>>$LOG
MKSWAP_EXIT=$?
log_msg "mkswap exit: $MKSWAP_EXIT"

if [ $MKSWAP_EXIT -ne 0 ]; then
    log_msg "ERROR: mkswap failed"
    exit 1
fi

# swapon with priority 100 — use system binary, not busybox
/system/bin/swapon /dev/block/zram0 -p 100 2>>$LOG
SWAPON_EXIT=$?
log_msg "swapon exit: $SWAPON_EXIT"

# Fallback: if /system/bin/swapon doesn't exist, find any that supports -p
if [ $SWAPON_EXIT -ne 0 ]; then
    log_msg "Fallback: searching for swapon with -p support..."
    for BIN in /system/xbin/swapon /vendor/bin/swapon swapon; do
        $BIN /dev/block/zram0 -p 100 2>>$LOG
        if [ $? -eq 0 ]; then
            log_msg "swapon succeeded via: $BIN"
            SWAPON_EXIT=0
            break
        fi
    done
fi

if [ $SWAPON_EXIT -ne 0 ]; then
    log_msg "ERROR: swapon failed on all paths"
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
echo 160 > /proc/sys/vm/swappiness 2>/dev/null
log_msg "swappiness set to 160"

echo 0 > /proc/sys/vm/page-cluster 2>/dev/null
log_msg "page-cluster set to 0"

echo 15 > /proc/sys/vm/dirty_ratio 2>/dev/null
echo 5 > /proc/sys/vm/dirty_background_ratio 2>/dev/null
log_msg "dirty ratios set"

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
log_msg "=== ZRAM Turbo v2.1 setup complete ==="
log_msg "Size: ${ZRAM_SIZE_MB}MB | Algo: $COMP_ALGO | Swappiness: 160"
log_msg "Swap: $(cat /proc/swaps 2>/dev/null)"

exit 0
