#!/bin/bash
# Example: flash OOS 9.5.3 on OnePlus 7 Pro (project 18821)
# Adjust --loader, --devicemodel, file paths for your device.
#
set -e

EXTRACT="./extract"              # Set this to your OPS extract directory
LOADER="$EXTRACT/prog_firehose_ddr.elf"
EDL="python3 edl.py"
BASE="$EDL --loader=$LOADER --devicemodel=18821"   # Change devicemodel for your device

echo "=== FLASH ==="

flash() {
    local part=$1 file=$2 lun=${3:-0}
    echo ">>> LUN$lun: $part  <-  $file"
    $BASE w "$part" "$EXTRACT/$file" --lun=$lun --memory=ufs || exit 1
    echo ""
}

# LUN 0
flash param param.bin 0
flash persist persist.img 0
flash op2 op2.img 0
flash oem_dycnvbk dynamic_nvbk.bin 0
flash oem_stanvbk static_nvbk.bin 0
flash config config.bin 0
flash system_a system.img 0
flash odm_a odm.img 0

# LUN 1
flash xbl_config_a xbl_config.elf 1
flash xbl_a xbl.elf 1

# LUN 4
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

# Shared
flash op1 op1.img 4

echo "=== DONE ==="
echo "Set active slot and reboot:"
echo "  $BASE setactiveslot a"
echo "  $BASE reset --resetmode=normal"
