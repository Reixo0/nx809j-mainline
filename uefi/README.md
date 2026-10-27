# Mu-Silicium (UEFI) for the NX809J

The Mu-Silicium port itself lives in
[mu-silicium-nx809j](https://github.com/Reixo0/mu-silicium-nx809j), a git
submodule here (`git submodule update --init uefi/mu-silicium-nx809j`): the
device package, the driver extraction and patches, the ESP dispatcher
(`esp-dispatch/`) and the debugging probes. It boots Linux (Arch Linux ARM
via systemd-boot), started either from `boot_a` or, for dual boot with
Android, from the Canoe boot manager (below).

| File | What it is |
|---|---|
| `mu-silicium-nx809j/` | The port (submodule) |
| `build-mu.sh` | Builds it with this repository's inputs: `dump/partitions/uefi_a.img`, our kernel's DTB, `tools/avb/avbtool.py`, Mu-Silicium in `tools/dl` |
| `canoe/` | Dual boot with the Canoe boot manager: profile extraction, orange-screen patch, boot-root installer, `canoe-image` patch, large-font menu |

## Building

Host packages: clang, lld, nasm, mono. Then:

```bash
git submodule update --init uefi/mu-silicium-nx809j
git clone https://github.com/Project-Silicium/Mu-Silicium tools/dl/Mu-Silicium
git -C tools/dl/Mu-Silicium submodule update --init --recursive Common Mu_Basecore Silicium-ACPI Silicon
python3 -m venv tools/dl/mu-venv
tools/dl/mu-venv/bin/pip install -r tools/dl/Mu-Silicium/pip-requirements.txt
uefi/build-mu.sh
```

`uefi/mu-silicium-nx809j/out/Mu-nx809j.img` goes to `boot_a`; `fastboot boot`
never reaches the kernel on this phone. The ESP dispatcher:
`uefi/mu-silicium-nx809j/esp-dispatch/build.sh`, and its `MU.fd`:
`uefi/mu-silicium-nx809j/esp-dispatch/extract-mu-fd.py <image> MU.fd`.

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
* `nx809j-reboot-linux` (Arch) and, on Android,
  [android-reboot-to-linux](https://github.com/Reixo0/android-reboot-to-linux)
  (KernelSU module, or **Linux** in the power menu's restart options) write
  Canoe's boot-once record `canoe-once:linux` into the command field of
  `misc` and reboot, so Linux starts without any menu. Canoe clears the
  record first.
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
   `bin/canoe-bootmgr` and `efisp/tools`, the ESP dispatcher
   (`mu-silicium-nx809j/out/esp-dispatch/BOOTAA64.EFI`) as
   `nx809j/dispatch.efi` and `MU.fd`, then run
   `canoe/install-boot-root.sh --apply` as root on Android (SELinux
   permissive meanwhile).
5. Superfastboot: `fastboot stage BDS.efi`, `fastboot oem boot-efi`, hold
   volume up, "Enter Super Fastboot", then `fastboot flash efisp BDS.efi`
   (Android's kernel refuses the raw write; the old superfastboot hides
   `efisp`). Check with `fastboot fetch efisp`.

Back out: `fastboot flash efisp <old efisp image>` from Canoe's Super
Fastboot (or EDL); gbl-chainload ignores `efisp.fat`.

### Large boot-menu font

Canoe draws its menus and the Super Fastboot screens through the firmware
text console, whose 8x19 font is tiny on this 1216x2688 panel.
`canoe/canoe-big-console.patch` (against Canoe ae950bb, 7.0.11) adds
`SuperFbBigConsole.c`, a `gST->ConOut` replacement that draws the same EDK2
glyphs through GOP at 3x (50x47 grid) and shows the highlighted row white on
red. The first menu or fastboot screen installs it; it is removed around
every child `StartImage` (Android loader, dispatcher, `fastboot boot`), so
the silent default boot and the started images see the firmware console
as before. Menu text no longer reaches the firmware's serial log (the
`SFB: MARK` lines still do).

Build (host, no Docker; needs clang/lld, nasm and `tools/dl/mu-venv`):

```
git clone https://github.com/1vivy/gbl_root_canoe tools/dl/gbl_root_canoe
git -C tools/dl/gbl_root_canoe checkout ae950bb
uefi/canoe/build-bds.sh          # applies the patch -> out/canoe/BDS.efi
```

The script runs Canoe's `submodules/uefi` `build` recipe with the host
fixes it needs for clang 23 and Python 3.14 (see its header). Test from RAM
before flashing: hold volume up at boot, "Enter Super Fastboot", then
`fastboot boot out/canoe/BDS.efi`. Flash only once the menu is confirmed
readable: `fastboot flash efisp out/canoe/BDS.efi` from Super Fastboot,
check with `fastboot fetch efisp` (compare the leading `BDS.efi` bytes).
