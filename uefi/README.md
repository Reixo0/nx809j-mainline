# Mu-Silicium (UEFI) for the NX809J

Port of [Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium) based
on the OnePlus 15 (`infiniti`, same SoC) port. Status: builds, not yet tried
on the phone.

| File | What it is |
|---|---|
| `nx809jPkg/` | Device package (goes to `Platforms/ZTE/nx809jPkg`): memory map (OnePlus 15 map plus the Nubia RamConsole at 0xE2000000, where our kernel keeps pstore), configuration map (from `xbl_config`), 1216x2688 framebuffer, SMBIOS, driver lists |
| `nx809j.toml` | Build config: FD at 0xC6900000, boot image v4 with the `os_version` our ABL requires |
| `fv-extract.py` | Extracts the drivers from the phone's `uefi` partition (ELF with LZMA firmware volumes) |
| `patch-dxe.py` | The OnePlus 15 driver patches, located again in this phone's firmware build; each checks the bytes it replaces |
| `Binaries/nx809j/` | `.inf` files only; `make-binaries.sh` puts the phone's own drivers next to them |
| `build.sh` | Builds everything into `out/Mu-nx809j.img` (with the AVB footer ABL wants) |

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
