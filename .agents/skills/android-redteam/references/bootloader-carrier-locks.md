# Bootloader & Carrier Lock Reference

## Table of Contents
- Android Boot Chain
- Bootloader Lock Types
- Carrier Lock vs OEM Lock
- AT&T Specific Protections
- Flash Tools (Odin, Heimdall)
- Bootloader Bypass Approaches
- SIM Lock vs Bootloader Lock

## Android Boot Chain

```
BootROM (SoC) -> BL1 (Samsung) -> BL2/sboot -> ABOOT -> kernel -> init -> system
     |              |                |            |
     v              v                v            v
  Hardware      Samsung cert    Samsung cert   dm-verity
  immutable     chain           + carrier cert  hash tree
```

Each stage verifies the next. Breaking any link in the chain requires compromising the verifier (the stage ABOVE it), not the verified stage itself.

## Bootloader Lock Types

### OEM Lock (Software)
- Toggle in Developer Settings: "OEM unlocking"
- Controlled by `sys.oem_unlock_allowed` property
- On AOSP/Google devices: actually unlocks bootloader via `fastboot oem unlock`
- On Samsung: only ONE prerequisite; carrier lock may override
- On carrier-locked Samsung: **purely cosmetic** - toggling ON has no practical effect

### Carrier Lock (Firmware/Hardware)
- Enforced in bootloader firmware (sboot/BL2)
- Checks a carrier-specific signing key during flash
- Cannot be disabled via software toggle
- Requires: carrier unlock code, or exploit in bootloader itself
- AT&T, Verizon, and US carriers are the most aggressive with this

### Samsung KNOX Lock
- Knox warranty fuse (eFuse): physical, one-time, irreversible
- Tripped by: flashing unsigned firmware, booting custom recovery
- Effect: Samsung Pay disabled, some apps refuse to run
- Does NOT prevent boot of signed Samsung firmware

## Carrier Lock vs OEM Lock

| Property | OEM Lock | Carrier Lock |
|----------|----------|-------------|
| Location | Android settings | Bootloader firmware |
| Toggle | Developer Settings | None (carrier controls) |
| Bypass | `fastboot oem unlock` (if no carrier lock) | Carrier unlock code or exploit |
| Scope | Prevents custom firmware flash | Prevents ANY unsigned flash |
| Samsung specifics | Prerequisite only | Actual enforcement |

**Critical distinction on Samsung**: OEM unlock toggle + Download Mode + Odin is the standard flash path. But carrier lock adds a SECOND verification layer that rejects images not signed with the carrier's key.

## AT&T Specific Protections

AT&T Samsung devices have the most restrictive bootloader policy among US carriers:
- OEM unlock toggle exists but is cosmetic
- Odin flash of modified partitions (AP, BL, CP, CSC) is rejected
- Even stock firmware from other carriers (T-Mobile, unlocked) is rejected
- Only AT&T-signed firmware can be flashed
- No `fastboot` interface (Samsung uses Download Mode + Odin instead)
- Historical bypasses (SamFAIL, engineering bootloaders) are patched on 2017+ builds

### Download Mode
Enter via: `adb reboot download` or Power + Vol Down + Home
- Shows device info: model, carrier, Knox warranty bit, secure download status
- "CUSTOM BINARY DOWNLOAD: OFF" means no custom firmware has been flashed
- Odin connects here for firmware flashing

## Flash Tools

### Odin (Windows, Samsung proprietary)
- Official Samsung service tool (leaked, widely available)
- Partitions: BL (bootloader), AP (kernel+system), CP (modem), CSC (carrier config)
- Odin v3.14.4 is the recommended version for older devices
- Flash process: Download Mode -> Odin detects -> select firmware -> Start
- On carrier-locked devices: Odin reports FAIL immediately after attempting to write

### Heimdall (Open source, cross-platform)
- Open-source alternative to Odin
- Uses same Samsung download protocol (PIT-based)
- Same carrier lock restrictions apply
- Useful for: detecting partitions, reading PIT, pulling images

### Magisk Patching (For Unlocked Bootloaders Only)
1. Extract `boot.img` from firmware AP package
2. Push to device: `adb push boot.img /sdcard/`
3. Open Magisk Manager -> Install -> Select and Patch a File -> choose boot.img
4. Pull patched image: `adb pull /sdcard/Download/magisk_patched-*.img`
5. Flash via Odin in AP slot (requires unlocked bootloader)

## Bootloader Bypass Approaches

### Software Approaches (Historical)
| Method | Era | Status on 2017+ Samsung |
|--------|-----|------------------------|
| SamFAIL exploit | 2014 | Patched |
| Engineering bootloader flash | 2015 | Key revoked |
| JTAG/eMMC direct access | Current | Requires hardware |
| Qualcomm EDL mode | SoC-specific | Not available on Exynos |
| Samsung Download Mode exploit | 2013-2014 | Patched |

### Hardware Approaches
- **eMMC direct read/write**: Desolder or use test points to access eMMC directly
  - Bypass ALL software locks (bootloader, carrier, Knox)
  - Requires: eMMC reader, soldering skills, device-specific test point map
  - Risk: brick device if write goes wrong
- **JTAG**: Debug interface on PCB test points
  - Full memory access but very slow
  - Requires: JTAG adapter, device-specific pinout
- **ISP (In-System Programming)**: Similar to eMMC but uses SPI/I2C
  - Less common on modern Samsung devices

### Carrier Unlock (Legitimate)
- Request unlock code from AT&T (after contract fulfilled)
- Third-party unlock services (use IMEI to generate code)
- This unlocks SIM lock, NOT bootloader lock (separate mechanisms)

## SIM Lock vs Bootloader Lock

These are SEPARATE mechanisms:

| Property | SIM Lock | Bootloader Lock |
|----------|----------|----------------|
| Purpose | Restrict to carrier's SIM | Prevent custom firmware |
| Storage | Modem firmware (CP) | Bootloader firmware (BL) |
| Unlock | Carrier code / IMEI service | Carrier agreement / exploit |
| Effect of bypass | Use any carrier's SIM | Flash custom recovery/ROM |
| Independence | Can unlock SIM with locked BL | Can unlock BL with locked SIM |

Rooting via bootloader unlock does NOT require SIM unlock, and vice versa. They are independent security mechanisms.
