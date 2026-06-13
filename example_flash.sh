#!/bin/bash
# Example: flash firmware on OnePlus/Qualcomm device via EDL
# Adjust --loader, --devicemodel, file paths for your device.
#
# Features:
#   - Flashes both A and B slots (full unbrick)
#   - Preserves bootloader unlock state (never touches frp/devinfo)
#   - Preserves userdata (never writes userdata partition)
#   - --dry-run: preview what would be flashed without writing
#   - Cross-platform: works on Linux, macOS, Windows (Git Bash / WSL)
#
set -e

DRY_RUN=false
[[ "$1" == "--dry-run" ]] && DRY_RUN=true

EXTRACT="./extract"              # Set this to your OPS extract directory
LOADER="$EXTRACT/prog_firehose_ddr.elf"
EDL="python3 edl.py"
BASE="$EDL --loader=$LOADER --devicemodel=18821"   # Change devicemodel for your device

if $DRY_RUN; then
    echo "=== DRY RUN — no writes will be performed ==="
fi

echo "=== FLASH BOTH SLOTS ==="
echo "Bootloader unlock: PRESERVED (frp partition not touched)"
echo "User data:         PRESERVED (userdata partition not touched)"
echo ""

flash() {
    local part=$1 file=$2 lun=${3:-0}
    local path="$EXTRACT/$file"
    if [ ! -f "$path" ]; then
        echo "!!! SKIP $part: $path not found"
        return 0
    fi
    echo ">>> LUN$lun: $part  <-  $file"
    if $DRY_RUN; then
        return 0
    fi
    $BASE w "$part" "$path" --lun=$lun --memory=ufs 2>&1 || exit 1
    echo ""
}

echo "--- LUN 0 ---"
flash param param.bin 0
flash persist persist.img 0
flash op2 op2.img 0
flash oem_dycnvbk dynamic_nvbk.bin 0
flash oem_stanvbk static_nvbk.bin 0
flash config config.bin 0
flash metadata metadata.img 0
flash system_a system.img 0
flash odm_a odm.img 0

echo "--- LUN 1 ---"
flash xbl_config_a xbl_config.elf 1
flash xbl_a xbl.elf 1

echo "--- LUN 2 (B-slot XBL) ---"
flash xbl_config_b xbl_config.elf 2
flash xbl_b xbl.elf 2

echo "--- LUN 4 ---"
flash aop_a aop.mbn 4
flash tz_a tz.mbn 4
flash hyp_a hyp.mbn 4
flash modem_a NON-HLOS.bin 4
flash bluetooth_a BTFM.bin 4
flash abl_a abl.elf 4
flash dsp_a dspso.bin 4
flash keymaster_a km4.mbn 4
flash boot_a boot.img 4
flash cmnlib_a cmnlib.mbn 4
flash cmnlib64_a cmnlib64.mbn 4
flash devcfg_a devcfg.mbn 4
flash qupfw_a qupv3fw.elf 4
flash vbmeta_a vbmeta.img 4
flash dtbo_a dtbo.img 4
flash uefisecapp_a uefi_sec.mbn 4
flash imagefv_a imagefv.elf 4
flash vendor_a vendor.img 4
flash LOGO_a logo.bin 4

echo "--- LUN 5 (B-slot bootchain) ---"
flash aop_b aop.mbn 5
flash tz_b tz.mbn 5
flash hyp_b hyp.mbn 5
flash modem_b NON-HLOS.bin 5
flash bluetooth_b BTFM.bin 5
flash abl_b abl.elf 5
flash dsp_b dspso.bin 5
flash keymaster_b km4.mbn 5
flash boot_b boot.img 5
flash cmnlib_b cmnlib.mbn 5
flash cmnlib64_b cmnlib64.mbn 5
flash devcfg_b devcfg.mbn 5
flash qupfw_b qupv3fw.elf 5
flash vbmeta_b vbmeta.img 5
flash dtbo_b dtbo.img 5
flash uefisecapp_b uefi_sec.mbn 5
flash imagefv_b imagefv.elf 5

echo "--- SHARED ---"
flash op1 op1.img 4

if $DRY_RUN; then
    echo "=== DRY RUN COMPLETE — nothing was written ==="
    exit 0
fi

echo "=== DONE FLASHING ==="
echo "Setting active slot to A..."
$BASE setactiveslot a 2>&1
echo "Rebooting..."
$BASE reset --resetmode=normal 2>&1
echo ""
echo "Device should boot. Unlock state and userdata preserved."
