# Before the full release

Things that must be done before the prebuilt images are published.

- [ ] **Publish the Fedora dnf repository (COPR).** Fedora images point dnf
  at the `nx809j` COPR project of `COPR_OWNER` (`scripts/make-fedora-image.sh`).
  Build it from clean sources: the kernel from the public branch
  (`nx809j-public`, the same as `patches/`), not a tree with WIP or debug
  changes, and Denial, Phonewave and the apps from the forks' `main`
  (`scripts/build-denial.sh` with a Fedora sysroot), then `scripts/fedora-pkgs.sh`, then
  `fedora/copr-build.sh` on a Fedora host with `copr-cli` and the owner's
  API token, and check every build succeeded before building images.
