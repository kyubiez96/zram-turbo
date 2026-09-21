#!/system/bin/sh
# ZRAM Turbo - post-fs-data.sh
# Sets up zram as early as possible in boot

MODDIR=${0%/*}

# Wait for kernel to be ready
sleep 1

# Run the main zram setup
sh $MODDIR/system/bin/zram_tune.sh

exit 0
