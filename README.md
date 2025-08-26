Arch My Way (WIP)

Prerequisites
- Minimal Arch Linux install with LUKS encryption.
- Caelestia dots installed: https://github.com/caelestia-dots/caelestia

Install
- Clone and run from a local directory:
  - `git clone https://github.com/DigitalPals/arch-myway.git`
  - `cd arch-myway`
  - `fish ./letsgo.fish`

What it does
- Copies wallpapers into `~/Pictures/Wallpapers` (keeps existing files).
- Copies Caelestia config into `~/.config/caelestia` (overwrites existing files).
- Creates target directories if missing.
- Installs Plymouth and applies the Cybex theme, updates mkinitcpio hooks, rebuilds initramfs, and adds `quiet splash` to kernel params (GRUB/systemd-boot).
- Installs Homebrew (Linuxbrew), updates fish PATH, and attempts to install `codex` and `claude-code` via brew if available.
 - Enables TTY1 autologin for your user and auto-starts Hyprland on login (no display manager required).

Rules
- Do not run as root.

Troubleshooting
- Not in repo: If you see "Could not determine repository root", run from the cloned directory (`cd arch-myway`) and use `fish ./letsgo.fish`.
- Permission denied: Some steps (Plymouth install/theme, bootloader updates, mkinitcpio) require sudo. Make sure your user has sudo privileges.
- Pacman locked: If package installs fail with a database lock, close any other package managers and retry once the lock clears.
- yay install issues: Ensure you have network access; the script installs prerequisites (git, base-devel) automatically.
- Plymouth not showing: The summary prints readiness. If incomplete, follow the printed tips to add the mkinitcpio hook, rebuild initramfs, and ensure kernel params include `quiet splash`.
- GRUB/systemd-boot not updating: Ensure `grub-mkconfig` (for GRUB) exists and succeeds, or that your `/boot/loader/entries/*.conf` files are writable for systemd-boot.
