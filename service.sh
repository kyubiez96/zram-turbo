#!/system/bin/sh
# ZRAM Turbo - service.sh
# Late-boot memory optimizations

MODDIR=${0%/*}

# Wait for boot to complete
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
done
sleep 10

# ============================================
# LOW MEMORY KILLER TUNING (for older kernels)
# ============================================

# Set LMK minfree levels (aggressive but fair)
# These values are in pages (4KB each)
if [ -f /sys/module/lowmemorykiller/parameters/minfree ]; then
    echo "18432,23040,27648,32256,55296,80640" > /sys/module/lowmemorykiller/parameters/minfree 2>/dev/null
fi

# ============================================
# VIRTUAL MEMORY TUNING
# ============================================

# swappiness - high for zram usage (160 = very aggressive use of zram)
echo 160 > /proc/sys/vm/swappiness 2>/dev/null

# dirty ratio - how much脏页 before writeback
echo 15 > /proc/sys/vm/dirty_ratio 2>/dev/null
echo 5 > /proc/sys/vm/dirty_background_ratio 2>/dev/null

# vfs_cache_pressure - keep inode/dentry caches longer
echo 50 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null

# page cluster - 0 for zram (no readahead)
echo 0 > /proc/sys/vm/page-cluster 2>/dev/null

# ============================================
# ZRAM RE-TUNE (ensure settings stick)
# ============================================

if [ -d /sys/block/zram0 ]; then
    # Re-confirm swappiness
    echo 160 > /proc/sys/vm/swappiness 2>/dev/null

    # Set IO scheduler for zram
    for sched in bfq mq-deadline none; do
        if [ -f /sys/block/zram0/queue/scheduler ]; then
            echo $sched > /sys/block/zram0/queue/scheduler 2>/dev/null
        fi
    done

    # Optimize queue settings for zram
    echo 256 > /sys/block/zram0/queue/nr_requests 2>/dev/null
    echo 2 > /sys/block/zram0/queue/nomerges 2>/dev/null
    echo 0 > /sys/block/zram0/queue/add_random 2>/dev/null
    echo 1 > /sys/block/zram0/queue/rq_affinity 2>/dev/null
fi

# ============================================
# OTHER KERNEL TUNING
# ============================================

# Panic timeout - reboot on hang instead of freeze
echo 1 > /proc/sys/kernel/panic_on_oops 2>/dev/null
echo 10 > /proc/sys/kernel/panic 2>/dev/null

# Drop_caches to free up slab caches
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null

exit 0
