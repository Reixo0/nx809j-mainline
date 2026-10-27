# Mu-Silicium (UEFI) for the NX809J

Port of [Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium) based
on the OnePlus 15 (`infiniti`, same SoC) port. Status: boots Linux (Arch
Linux ARM via systemd-boot), started either from `boot_a` or, for dual boot
with Android, from the Canoe boot manager (below).

| File | What it is |
|---|---|
| `nx809jPkg/` | Device package (goes to `Platforms/ZTE/nx809jPkg`): memory map (OnePlus 15 map plus the Nubia RamConsole at 0xE2000000, where our kernel keeps pstore), configuration map (from `xbl_config`), 1216x2688 framebuffer, SMBIOS, driver lists |
| `nx809j.toml` | Build config: FD at 0xC6900000, boot image v4 with the `os_version` our ABL requires |
| `fv-extract.py` | Extracts the drivers from the phone's `uefi` partition (ELF with LZMA firmware volumes) |
| `patch-dxe.py` | The OnePlus 15 driver patches, located again in this phone's firmware build; each checks the bytes it replaces |
| `Binaries/nx809j/` | `.inf` files only; `make-binaries.sh` puts the phone's own drivers next to them |
| `build.sh` | Builds everything into `out/Mu-nx809j.img` (with the AVB footer ABL wants) |
| `esp-dispatch/` | `BOOTAA64.EFI` that starts Mu-Silicium from the Qualcomm UEFI (Canoe entry or "Boot to ESP") and, under Mu, systemd-boot; `extract-mu-fd.py` gets its `MU.fd` |
| `canoe/` | Dual boot with the Canoe boot manager: profile extraction, orange-screen patch, boot-root installer, `canoe-image` patch |
| `include/efi-mini.h` | Minimal freestanding EFI definitions for the small loaders here |
| `probe/` | Debugging aids: `AblProbe.c` (`ABL_PROBE=1` build shows ABL's hand-off) and `abldump/` (kernel module that dumps it from Linux) |
| `android-loader/` | Experiment: start Android's kernel from Mu-Silicium. Android's TrustZone services fail after Mu has run Qualcomm's TZ drivers, so it is not used |

The drivers are Qualcomm/Nubia binaries from the phone, so they are never in
git: `make-binaries.sh` builds them from `dump/partitions/uefi_a.img`.

## Building

Host packages: clang, lld, nasm, mono. Then:

```bash
git clone https://github.com/Project-Silicium/Mu-Silicium tools/dl/Mu-Silicium
cd tools/dl/Mu-Silicium
git submodule update --init --recursive Common Mu_Basecore Silicium-ACPI Silicon
cd ../../..
python3 -m venv tools/dl/mu-venv
tools/dl/mu-venv/bin/pip install -r tools/dl/Mu-Silicium/pip-requirements.txt
uefi/build.sh
```

The `Binaries` submodule (every device's blobs) is not needed.
`out/Mu-nx809j.img` goes to `boot_a`; `fastboot boot` never reaches the
kernel on this phone.

## Dual boot with Canoe

`boot_a` keeps Android's own boot image. Linux starts from the
[Canoe](https://github.com/1vivy/gbl_root_canoe) boot manager (7.0.11) in
`efisp`, which the phone's vulnerable ABL runs on every boot:

```
ABL -> efisp: Canoe BDS -> persist/efisp.fat
         android-a (default): boot_a.efi, the patched ABL, Mode 2 -> Android
         linux: nx809j/dispatch.efi -> MU.fd at 0xC6900000 -> Mu-Silicium
                -> ESP \EFI\BOOT\BOOTAA64.EFI (same dispatcher) -> systemd-boot
```

* A plain boot starts Android; volume up during boot opens Canoe's menu.
* `nx809j-reboot-linux` (Arch) and the KernelSU module in
  `device/android/reboot-linux` (Action button) write Canoe's boot-once
  record `canoe-once:linux` into the command field of `misc` and reboot, so
  Linux starts without any menu. Canoe clears the record first.
* The dispatcher no-ops Qualcomm's display power protocol before
  `ExitBootServices`; ABL's "Boot to ESP" path registers a callback that
  powers the panel off there, which left Linux with a broken display.

Mode 2 makes Android's KeyMint see a locked, stock-signed device. User data
is bound to that identity, so the Canoe loader must carry the same profile
as the loader it replaces. Steps used on 2026-10-27 (replacing
gbl-chainload 2.2.2):

1. `canoe/extract-gm2p.py dump/partitions/efisp.img boot.gm2p` (the
   2.2.2 profile: os_version 0, spl 0x801, stock Nubia key digests).
2. Build `tools/canoe-image` from Canoe with `canoe/canoe-image-gm2p.patch`
   (accepts that profile in place of `--vbmeta`; this phone's `vbmeta_a` is
   EvolutionX's) and run
   `canoe-image build --abl abl_a.img --vbmeta boot.gm2p --staged staged-orig`.
   `abl_a` is the current firmware ABL (2026-03-20); Canoe's patcher accepts it.
3. `canoe/skip-orange.py staged-orig/boot.efi staged/boot.efi`, copy the
   `.gm2p`/`.tzmap` beside it.
4. Bundle those with the one-shot package's `bin/canoe-provision`,
   `bin/canoe-bootmgr` and `efisp/tools`, `out/esp-dispatch/BOOTAA64.EFI`
   as `nx809j/dispatch.efi` and `MU.fd`, then run
   `canoe/install-boot-root.sh --apply` as root on Android (SELinux
   permissive meanwhile).
5. Superfastboot: `fastboot stage BDS.efi`, `fastboot oem boot-efi`, hold
   volume up, "Enter Super Fastboot", then `fastboot flash efisp BDS.efi`
   (Android's kernel refuses the raw write; the old superfastboot hides
   `efisp`). Check with `fastboot fetch efisp`.

Back out: `fastboot flash efisp <old efisp image>` from Canoe's Super
Fastboot (or EDL); gbl-chainload ignores `efisp.fat`.

Canoe's menus use the firmware text console, whose font is small on this
1216x2688 panel.
