# Before the full release

Things that must be done before the prebuilt images are published.

- [ ] **Publish the `[nx809j]` pacman repository.** Images point pacman at
  `https://github.com/Reixo0/nx809j-mainline/releases/download/arch-repo`
  (`scripts/make-arch-image.sh`), but that release has never been uploaded.
  Until it exists, `pacman -Syu` fails on every image ("nx809j.db failed to
  download"). Build the packages from clean sources first: the kernel from the
  public branch (`nx809j-public`, the same as `patches/`), not a tree with WIP
  or debug changes, and Denial, Phonewave and the apps from the forks' `main`
  (`scripts/build-denial.sh`, then `scripts/arch-pkgs.sh`). On the development
  phone `[nx809j]` is commented out in `/etc/pacman.conf` until then.
