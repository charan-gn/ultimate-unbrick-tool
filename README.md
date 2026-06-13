# Ultimate Unbrick Tool

Universal Qualcomm EDL unbrick/flash tool with auto-detecting OnePlus/Oppo auth,
cross-platform (Linux/macOS/Windows), bootloader-unlock-safe, userdata-preserving.

**Fork of [bkerler/edl](https://github.com/bkerler/edl) with critical bug fixes
and universal OnePlus auth support.**

## Quick start

```bash
# Extract OPS firmware
pip install -r requirements.txt
python3 opscrypto.py decrypt firmware.ops

# Flash everything (adjust --devicemodel for your device)
python3 edl.py --loader=extract/prog_firehose_ddr.elf --devicemodel=18821 \
  w param extract/param.bin --lun=0 --memory=ufs

# Or use the example script (edit paths first)
bash example_flash.sh          # real flash
bash example_flash.sh --dry-run  # preview only
```

## Features

| Feature | Detail |
|---------|--------|
| **Universal auth** | Auto-detects OnePlus v1/v3 auth from the programmer at runtime. No device database needed. Falls back gracefully to unauth writes. |
| **Bootloader unlock preserved** | Never touches `frp`, `devinfo`, or `sec` partitions. If your device was unlocked, it stays unlocked. |
| **Userdata preserved** | `userdata` partition is never written. Apps, files, settings survive the flash. |
| **Dual-slot safe** | Flash both A and B slots to ensure the device boots regardless of active slot. |
| **Cross-platform** | Python 3 + pyusb works on Linux, macOS, and Windows (via WSL or Git Bash + Zadig). |
| **--dry-run** | Preview every write without touching the device. |
| **Graceful degradation** | If auth fails (wrong prodkey, opcmd blocked, unknown device), writes proceed without auth tokens. Many programmers accept unauth writes. |

## Supported devices

**Any Qualcomm device in EDL mode** with a firehose programmer.

Auth is auto-detected — no config needed:
- **OnePlus** (all versions, OP5 through OP11) — v1/v3 auth
- **Oppo, Realme** — same auth as OnePlus
- **Google Pixel, Samsung, Motorola, Xiaomi, etc.** — no auth, standard firehose

Provide your own `prog_firehose_ddr.elf` and partition images. See `GUIDE.md`
for how to extract them from an OPS/MSM firmware package.

> **Always use the oldest available firehose programmer.** Newer firmware
> (OOS 11+) often compiles OnePlus auth out of the programmer. The OOS 9
> programmer works on OP7 Pro even to flash OOS 11 firmware.

## Differences from upstream edl

| Area | Upstream | This fork |
|------|----------|-----------|
| OnePlus auth | Hardcoded device database, errors on unknown projids | Auto-detected from programmer at runtime, multi-prodkey fallback, graceful degradation |
| `cmd_program()` | Returns True on any response (including NAK) | Correctly checks ACK/NAK |
| `cmd_program_buffer()` | Returns True on NAK | Fixed to return False |
| `wait_for_data()` | Infinite hang on no response | 30-second timeout |
| `cdc.write()` return | Ignored | Checked — returns False on write failure |
| `qfil` auth | `writeprepare()` never called | Added before programming |
| `writeprepare()` | Called per-partition in loop | Called once before batch |
| `skipresponse` crash leak | Never reset after crashdump recovery | Restored to original value |
| CLI | No `--devicemodel` docs | Still undocumented — contributions welcome |

## Project structure

```
├── edl.py                      # Main entry point
├── example_flash.sh            # A/B dual-slot flash script
├── GUIDE.md                    # Full reverse-engineering guide
├── edlclient/Library/
│   ├── firehose.py             # Firehose protocol + bug fixes
│   ├── Modules/
│   │   └── oneplus.py          # Universal OnePlus auth module
│   └── ...
└── ...
```

## License

GPLv3 — same as upstream. See `LICENSE`.
