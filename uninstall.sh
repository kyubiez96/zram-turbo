#!/system/bin/sh
# ZRAM Turbo - Cleanup on uninstall

# Disable zram swap
swapoff /dev/block/zram0 2>/dev/null

# Reset zram
echo 1 > /sys/block/zram0/reset 2>/dev/null

# Reset vm settings to defaults
echo 60 > /proc/sys/vm/swappiness 2>/dev/null
echo 0 > /proc/sys/vm/page-cluster 2>/dev/null
echo 100 > /proc/sys/vm/dirty_ratio 2>/dev/null
echo 5 > /proc/sys/vm/dirty_background_ratio 2>/dev/null
echo 100 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null

# Remove log
rm -f /data/local/tmp/zram_tune.log 2>/dev/null

exit 0
