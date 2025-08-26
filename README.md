Arch My Way (WIP)

One‑liner Usage (fish)
- Run this once after a fresh Arch install and make sure Caelestia is installed:
  - `curl -fsSL https://raw.githubusercontent.com/DigitalPals/arch-myway/main/letsgo.fish | fish -`

What it does (now)
- Copies wallpapers into `~/Pictures/Wallpapers` safely (no overwrite).
- Creates the target directory if missing.
- Works without cloning: downloads this repo’s wallpapers automatically.

Requirements
- `fish` and `curl` available on your system.

Rules
- Do not run as root. The script exits if run as root.
