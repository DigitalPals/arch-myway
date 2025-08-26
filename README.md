Arch My Way (WIP)

Prerequisites
- Minimal Arch Linux install with LUKS encryption.
- Caelestia dots installed: https://github.com/caelestia-dots/caelestia

Run (fish)
- One‑liner after a fresh Arch install:
  - `curl -fsSL https://raw.githubusercontent.com/DigitalPals/arch-myway/main/letsgo.fish | fish`

What it does
- Copies wallpapers into `~/Pictures/Wallpapers` (keeps existing files).
- Copies Caelestia config into `~/.config/caelestia` (overwrites existing files).
- Creates target directories if missing.
- Installs Plymouth and applies the Cybex theme.

Rules
- Do not run as root.
