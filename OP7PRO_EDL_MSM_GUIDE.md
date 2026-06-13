# OnePlus 7 Pro EDL Unbrick — Complete Guide

## Device: OnePlus 7 Pro GM1917 / 18821 (guacamole)

---

## The Problem

Hard-bricked OnePlus 7 Pro (OOS 11.0.5.1) stuck in EDL mode (Qualcomm
9008). Goal: flash firmware via EDL on Linux without the Windows-only
MSM Download Tool.

The `edl` tool by bkerler supports OnePlus auth (OPP — OnePlus Protection)
but writes silently failed at 0% with the OOS 11 firehose programmer.

---

## Discovery Timeline

### Phase 1: OOS 11 dead end

- Connected device, uploaded `prog_firehose_ddr.elf` from OOS 11.0.5.1
- `demacia` command succeeded
- `setprojmodel` returned **"opcmd is not enabled"**
- Writes showed `Done |----------| 0.0% Write` — false positive success

**Root cause found in OOS 11 programmer binary:**
```
$ strings prog_firehose_ddr.elf | grep -i opcmd
opcmd is not enabled
```
Only two OnePlus strings exist in the whole ELF — the error message and
a debug log. **No enable command exists.** OPP was compiled out.

### Phase 2: Auth investigation

- Found `o0xmuhe/play_with_oneplus7pro` patch for edl v3.52.1
- Discovered prodkey for 18821: `b2fad511325185e5`
- Verified OOS 11 settings.xml uses a different prodkey: `7016147d58e8c038`
- Tried skipping `setprojmodel` and removing auth tokens — same 0% false
  progress (cmd_program() had a bug: returned True on any response,
  including NAK)

**Key insight:** different firmware versions use different prodkeys.
The OOS 11 prodkey (verified against settings.xml hash) is
`7016147d58e8c038`, but the OOS 9 prodkey is `b2fad511325185e5`.

### Phase 3: OOS 9 programmer

- Downloaded OOS 9.5.3 MSM package (`guacamole_21_O.07_190512_unlocked.zip`)
- Decrypted the OPS file with `bkerler/oppo_decrypt`:
  ```bash
  python3 opscrypto.py decrypt guacamole_21_O.07_190512.ops
  ```
- Extracted all partition images and **the OOS 9 programmer**

**OOS 9 programmer analysis:**
```
$ strings prog_firehose_ddr.elf | grep -c "opcmd is not enabled"
0     # <-- NO opcmd restriction!

$ strings prog_firehose_ddr.elf | grep "VIP is enabled"
VIP is enabled, receiving the signed table of size %d
```
OOS 9 programmer uses **VIP** (Verified Image Programming) instead of
OPP. setprojmodel works with VIP.

### Phase 4: Fixes applied

**a) cmd_program() NAK bug** (`firehose.py`):
Original code always returned True. Fixed to check:
- XML response success (ACK/NAK)
- Write completion response

**b) Re-enabled setprojmodel** (`oneplus.py`):
Was disabled with `# Skipped - opcmd not enabled`. Re-enabled for
programmers that support it.

**c) Correct auth for OOS 9** (`oneplus.py`):
- prodkey (18821): `b2fad511325185e5`
- random_postfix: `8MwDdWXZO7sj0PF3`
- Version: `guacamole_21_H.04_190416`

**d) Re-enabled auth tokens** in `addpatch()` and `addprogram()`

### Phase 5: Flash OOS 9

Used auto_flash_oos9.sh to flash all partitions:
- LUN 0: param, persist, op2, dynamic_nvbk, static_nvbk, config,
         metadata, system_a, odm_a
- LUN 1: xbl_a, xbl_config_a
- LUN 4: aop_a, tz_a, hyp_a, modem_a, bluetooth_a, abl_a, dsp_a,
         keymaster_a, boot_a, cmnlib_a, cmnlib64_a, devcfg_a, qupfw_a,
         vbmeta_a, dtbo_a, uefisecapp_a, imagefv_a, vendor_a, logo_a

Result: device booted OOS 9.5.3 successfully.

---

## Auth System Explained

All OnePlus firehose auth uses **ModelVerifyVersion=1** for OP7 Pro.

### Token generation

```
h1 = prodkey + projid + random_postfix
ModelVerifyHashToken = SHA256(h1)

h2 = "c4b95538c57df231" + projid + cf + soc_sn + Version + ts
     + ModelVerifyHashToken + "5b0217457e49381b"
secret = SHA256(h2)

items = [projid, random_postfix, ModelVerifyHashToken, Version,
         cf, soc_sn, ts, secret]

token = AES_CBC(key=pk_prefix + pk, iv=fixed, data=items.join(","))
```

### What the programmer verifies

1. Decrypt token with the provided `pk`
2. Extract projid, postfix, hash
3. Compute `SHA256(store_prodkey + projid + postfix)` and compare with hash
4. Compute `SHA256("c4b95538c57df231" + projid + cf + sn + Version + ts
   + hash + "5b0217457e49381b")` and compare with secret

The **prodkey** is compiled into the programmer binary. If it doesn't
match, auth fails. OOS 9 and OOS 11 use different prodkeys for 18821.

---

## Universal device support (any Qualcomm device)

The tool auto-detects everything needed — no device database required.

### Auth version auto-detection

Instead of relying on a hardcoded device list, the tool checks the
programmer's `supported_functions` at runtime:

```
setprocstart present       → v3 auth (setprocstart + setswprojmodel)
setprojmodel/demacia       → v1 auth (demacia + setprojmodel)
neither                    → no auth needed (standard firehose)
```

This means it automatically adapts to any OnePlus/Oppo/Realme device
regardless of whether it's in the database.

### prodkey resolution

```
1. Check KNOWN_PRODKEYS dict for exact projid match
2. Try PRODKEY_FALLBACKS in order:
   - "0000000000000000"  (generic default)
   - "7016147d58e8c038"  (common OOS 11+ key)
   - "b2fad511325185e5"  (common OOS 9/10 key)
3. If all fail → auth_ok=False, writes proceed without auth tokens
```

### Graceful degradation chain

On any Qualcomm device, the tool does:

```
Upload programmer (Sahara)
  ↓
Read supported functions
  ├─ setprocstart?  → oneplus2 auth (v3 with device_timestamp)
  ├─ setprojmodel?  → oneplus1 auth (v1, multi-prodkey retry)
  └─ neither?       → no auth (standard firehose, works everywhere)
  ↓
If auth fails:
  auth_ok = False, writes proceed WITHOUT pk/token in XML
  ↓
If opcmd blocked:
  Detected, auth_ok = False, writes skip auth tokens
  ↓
cmd_program(): checks NAK properly (fixed)
  ├─ NAK → return False (no false 0% progress)
  └─ ACK → stream data, wait for final ACK
  ↓
Write success or failure properly reported
```

This handles:
- **OnePlus** (all versions) — auto-detects v1/v3 auth
- **Oppo, Realme** — uses same auth as OnePlus
- **Xiaomi** — separate xiaomi module (already in edl)
- **Google Pixel, Samsung, Motorola, etc.** — no auth, firehose works directly
- **opcmd-blocked programmers** — auto-detected, falls back gracefully
- **Unknown projids** — no crash, tries defaults, falls back gracefully

---

## How to check any programmer

```bash
# Check for opcmd restriction (bad)
strings prog_firehose_ddr.elf | grep "opcmd is not enabled"

# Check for VIP support (good)
strings prog_firehose_ddr.elf | grep "VIP is enabled"

# Check supported firehose functions
strings prog_firehose_ddr.elf | grep "setprojmodel\|demacia"
```

If `opcmd` is present → find an older firmware's programmer.
If `VIP` is present → auth should work.

---

## Tool setup

```bash
# edl tool
git clone https://github.com/bkerler/edl.git
cd edl
pip install -r requirements.txt

# oppo_decrypt (OPS extraction)
git clone https://github.com/bkerler/oppo_decrypt.git
cd oppo_decrypt
pip install -r requirements.txt
python3 opscrypto.py decrypt firmware.ops
# Output goes to ./extract/
```

---

## OnePlus 7 Pro OPS firmware sources

| Firmware | Version | File | Source |
|----------|---------|------|--------|
| OOS 9.5.3 Global | guacamole_21_O.07_190512 | guacamole_21_O.07_190512_unlocked.zip | androidfilehost.com |
| OOS 9.5.4 EU | guacamole_21_E.08_190515 | guacamole_21_E.08_190515_unlocked.rar | androidfilehost.com |
| HydrogenOS | guacamole_21_H.04_190416 | guacamole_21_H.04_190416_unlocked.zip | androidfilehost.com |

---

## Required edl patches (upgraded for generic devices)

### 1. `oneplus.py` — Universal OnePlus auth module

```python
# → prodkey database with fallbacks
KNOWN_PRODKEYS = {
    "18825": "b2fad511325185e5",
    "18801": "b2fad511325185e5",
    "18821": "b2fad511325185e5",
    "18857": "7016147d58e8c038",
    ...
}
PRODKEY_FALLBACKS = ["0000000000000000", "7016147d58e8c038",
                     "b2fad511325185e5"]

class oneplus:
    def __init__(self, ...):
        self.auth_ok = True                     # track auth success

    # → Auto-detect auth version from programmer's supported functions
    def detect_auth_version(self):
        if "setprocstart" in self.supported_functions:
            return 3                            # v3 (setprocstart)
        if "setprojmodel" in self.supported_functions:
            return 1                            # v1 (demacia+setproj)
        return 0                                # no auth needed

    def convert_projid(self, fh, projid, serial):
        prodkey = self.getprodkey(projid) or "0000000000000000"
        pk = self.generate_pk()

        if projid in deviceconfig:
            ...                                 # use known config
        # → Unknown projid: detect version from programmer
        version = self.detect_auth_version()
        if version >= 3:
            return oneplus2(fh, cm, serial, pk, prodkey, ...)
        elif version == 1:
            return oneplus1(fh, projid, serial, pk, prodkey, self.cf)
        return None                             # no auth

    def run(self):
        if self.ops is not None:
            if "demacia" in self.supported_functions:
                if not self.ops.run("demacia"):
                    self.auth_ok = False        # non-fatal
            if "setprojmodel" in self.supported_functions:
                if not self.ops.run(""):
                    self.auth_ok = False
            if "setprocstart" in self.supported_functions:
                if not self.ops.run(""):
                    self.auth_ok = False
        return self.auth_ok

    # → Only send auth tokens if auth succeeded
    def addprogram(self):
        if self.auth_ok and self.ops and \
           ("setprojmodel" in self.supported_functions or
            "setswprojmodel" in self.supported_functions):
            pk, token = self.ops.generatetoken(True)
            return f'pk="{pk}" token="{token}" '
        return ""

class oneplus1:
    def run(self, flag):
        if flag == "demacia":
            ...                                 # demacia auth
            return True
        # → Try multiple prodkeys before giving up
        candidates = [self.prodkey] + \
                     [k for k in PRODKEY_FALLBACKS if k != self.prodkey]
        for prodkey in candidates:
            self.prodkey = prodkey
            pk, token = self.generatetoken(False)
            res = self.fh.cmd_send(
                f"setprojmodel token=\"{token}\" pk=\"{pk}\"")
            if b"value=\"ACK\"" in res:
                return True
            if b"opcmd is not enabled" in res:
                return False                    # programmer blocked
        return False

class oneplus2:
    def run(self, flag):
        res = self.fh.cmd_send("setprocstart")
        # → parse device_timestamp from response
        ...
        pk, token = self.generatetoken(False)
        res = self.fh.cmd_send(
            f"setswprojmodel token=\"{token}\" pk=\"{pk}\"")
        if "model_check=\"0\"" in res and "auth_token_verify=\"0\"" in res:
            return True
        return False
```

### 2. `firehose.py` — cmd_program() NAK fix

```python
def cmd_program(self, ...):
    ...
    rsp = self.xmlsend(data, self.skipresponse)
    if not rsp.resp:                          # ← was missing
        self.error(...)
        return False
    # ... stream data ...
    wd = self.wait_for_data()
    rsp = self.xml.getresponse(wd)
    if rsp.get("value") != "ACK":             # ← was inverted
        self.error(...)
        return False
    return True
```

### 3. `init.py` — Non-fatal auth failure

```python
class modules:
    def writeprepare(self):
        if self.ops is not None:
            try:
                return self.ops.run()
            except Exception as e:
                self.error(f"Auth failed (non-fatal): {e}")
                return False      # ← don't abort writes
        return True
```

---

## Full flash script

```bash
#!/bin/bash
EXTRACT="/path/to/extract"
LOADER="$EXTRACT/prog_firehose_ddr.elf"
EDL="python3 edl.py"
BASE="$EDL --loader=$LOADER --devicemodel=18821"

flash() {
    local part=$1 file=$2 lun=${3:-0}
    echo ">>> LUN$lun: $part"
    $BASE w "$part" "$EXTRACT/$file" --lun=$lun --memory=ufs || exit 1
}

# LUN 0
flash param param.bin 0
flash persist persist.img 0
flash op2 op2.img 0
flash oem_dycnvbk dynamic_nvbk.bin 0
flash oem_stanvbk static_nvbk.bin 0
flash config config.bin 0

# system_a and odm_a are sparse — may be large
flash system_a system.img 0
flash odm_a odm.img 0

# LUN 1 — XBL
flash xbl_config_a xbl_config.elf 1
flash xbl_a xbl.elf 1

# LUN 4 — firmware
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
flash LOGO_a logo.bin 4
flash vendor_a vendor.img 4

# Set active slot and reboot
$BASE setactiveslot a
$BASE reset --resetmode=normal
echo "Done. Phone should boot OOS 9."
```

---

## Key lessons

1. **Programmer version matters** — later firmware (OOS 11+) compiled
   OPP out of the programmer. Always use the oldest available firmware's
   `prog_firehose_ddr.elf`.

2. **Different auth per firmware** — each firmware version may use a
   different prodkey. Verify against settings.xml if available.

3. **cmd_program() NAK bug** — edl's program function had a logic bug:
   `if rsp["value"] == "ACK": return False` (inverted). Writes returned
   progress bars and "Done" but actually failed silently.

4. **skipresponse** — when enabled, xmlsend returns `resp=True` without
   reading any response. Only used for crashdump recovery. Ensure it's
   False during normal writes.

5. **OPS decryption** — OnePlus OPS files use AES encryption via
   `opscrypto.py` from bkerler/oppo_decrypt. The decrypted ELF can be
   used directly with edl.

6. **setprojmodel is optional** — if the programmer doesn't support it
   (opcmd blocked), writes without auth tokens may still work if the
   programmer accepts unauthenticated program commands. OOS 11's
   programmer does not.

---

## Quick reference

```bash
# Extract OPS
python3 opscrypto.py decrypt firmware.ops
# → ./extract/prog_firehose_ddr.elf, ./extract/*.img, ./extract/settings.xml

# Check programmer
strings prog_firehose_ddr.elf | grep -E "opcmd|VIP is enabled|setprojmodel"

# Flash one partition
python3 edl.py --loader=prog_firehose_ddr.elf --devicemodel=18821 \
  w param param.bin --lun=0 --memory=ufs

# Enter EDL mode: Power off → hold Vol Up + Vol Down → plug USB
# Check: lsusb | grep 9008

# From bootloader: fastboot set_active a && fastboot reboot
```

---

## Files on this machine

```
/home/charan/edl/                          — edl tool (bkerler)
/home/charan/edl/edlclient/Library/Modules/oneplus.py  — patched auth
/home/charan/edl/edlclient/Library/firehose.py          — patched cmd_program
/home/charan/auto_flash_oos9.sh            — flash script (OOS 9)
/home/charan/edl/oos9/prog_firehose_ddr.elf  — working OOS 9 programmer
/home/charan/Downloads/OnePlus_7_Pro_Global_OxygenOS_9.5.3/  — OOS 9 OPS + extract
/home/charan/Downloads/OnePlus_7_Pro_Global_OxygenOS_11.0.5.1/  — OOS 11 OTA zip
/tmp/oppo_decrypt/                         — OPS decryption tool
```
