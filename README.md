# ZRAM Turbo - Magisk Module

Aggressive zram swap module optimized for low-RAM Android devices. Creates a fixed 2GB compressed swap device using lz4 compression, giving your phone significantly more usable memory.

## What It Does

- Creates a **2GB zram block device** with lz4/lz4hc compression
- Effective virtual memory: ~4-6GB depending on data compressibility
- Tunes kernel VM parameters for zram-heavy workloads
- Sets up at boot via `post-fs-data.sh` (earliest possible)

## Features

| Feature | Value |
|---------|-------|
| ZRAM Size | 2GB (fixed) |
| Compression | lz4hc > lz4 > zstd > lzo (auto-detected) |
| Swappiness | 160 (aggressive zram usage) |
| Page Cluster | 0 (no readahead) |
| Swap Priority | 100 (used first) |
| VFS Cache Pressure | 50 |
| Dirty Ratios | 15% / 5% |
| Queue Tuning | Optimized nr_requests, nomerges |

## Requirements

- **Magisk 20.4+** (or KernelSU with Magisk module support)
- Android device with kernel zram support

## Installation

1. Download `ZRAM_Turbo_v2.0.zip` from [Releases](../../releases)
2. Open **Magisk Manager** → **Modules** → **Install from storage**
3. Select the zip file
4. **Reboot**

## Verify After Install

```bash
# Check swap is active
cat /proc/swaps

# Check zram size
cat /sys/block/zram0/disksize

# Check memory summary
free -h
```

## Uninstall

- Disable in Magisk Manager → Modules → ZRAM Turbo → toggle off → Reboot
- Or flash the zip again and select Uninstall

## How It Works

### Boot Sequence

1. **`post-fs-data.sh`** — Runs early in boot, calls `zram_tune.sh`
2. **`zram_tune.sh`** — Creates zram device, formats swap, enables it, tunes VM params
3. **`service.sh`** — Runs after boot completes, applies additional kernel tuning (LMK, dirty ratios, drop caches)

### Compression Algorithm Priority

The module auto-detects the best available algorithm:
1. **lz4hc** — Best balance of speed and compression (preferred)
2. **lz4** — Fastest compression/decompression
3. **zstd** — Best compression ratio (slightly slower)
4. **lzo** — Fallback

### VM Tuning

| Parameter | Value | Why |
|-----------|-------|-----|
| `vm.swappiness` | 160 | Use zram aggressively before killing apps |
| `vm.page-cluster` | 0 | No readahead, optimal for compressed swap |
| `vm.dirty_ratio` | 15 | Less writeback thrashing |
| `vm.dirty_background_ratio` | 5 | Start writeback sooner |
| `vm.vfs_cache_pressure` | 50 | Keep dentries/inodes in memory longer |

## Files

```
META-INF/
  com/google/android/
    update-binary        # Magisk installer
    updater-script       # Magisk marker
customize.sh            # Install-time output & permissions
post-fs-data.sh         # Early boot hook
service.sh              # Late boot optimizations
system/bin/zram_tune.sh # Core zram setup script
uninstall.sh            # Cleanup on module removal
module.prop             # Module metadata
```

## Logs

Boot logs are written to `/data/local/tmp/zram_tune.log`. Check this file if zram isn't working as expected.

## License

MIT
