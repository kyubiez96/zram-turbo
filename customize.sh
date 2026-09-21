#!/system/bin/sh
# ZRAM Turbo - customize.sh (Magisk Manager)

# Print banner
ui_print "============================================"
ui_print "     ZRAM Turbo v2.0 - Optimized Swap       "
ui_print "     by RYU                                  "
ui_print "============================================"
ui_print ""

# Get total RAM
TOTAL_RAM_KB=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
ZRAM_SIZE_MB=2048

ui_print "- Detected RAM: ${TOTAL_RAM_MB}MB"
ui_print "- ZRAM size: ${ZRAM_SIZE_MB}MB (fixed 2GB)"
ui_print "- Algorithm: lz4 (auto-detected at boot)"
ui_print "- Swappiness: 160"
ui_print ""

# Detect best compression
COMP="lz4"
if [ -f /sys/block/zram0/comp_algorithm ]; then
    ALGOS=$(cat /sys/block/zram0/comp_algorithm 2>/dev/null)
    if echo "$ALGOS" | grep -q "lz4hc"; then
        COMP="lz4hc"
    elif echo "$ALGOS" | grep -q "zstd"; then
        COMP="zstd"
    fi
fi
ui_print "- Best compression: $COMP"
ui_print ""

# Set permissions
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm $MODPATH/system/bin/zram_tune.sh 0 0 0755
set_perm $MODPATH/post-fs-data.sh 0 0 0755
set_perm $MODPATH/service.sh 0 0 0755

ui_print "- Installation complete!"
ui_print "- Reboot to activate zram"
ui_print ""
