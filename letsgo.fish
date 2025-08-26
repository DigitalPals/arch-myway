#!/usr/bin/env fish

# Safely copy wallpapers from the repo into ~/Pictures/Wallpapers
# Usage:
#   fish ./letsgo.fish
#   WALLPAPER_SRC=/some/path fish ./letsgo.fish  # optional override

function log
    echo (set_color green)'[OK] '(set_color normal)$argv
end

function info
    echo (set_color cyan)'[INFO] '(set_color normal)$argv
end

function warn
    echo (set_color yellow)'[WARN] '(set_color normal)$argv
end

function err
    echo (set_color red)'[ERR] '(set_color normal)$argv 1>&2
end

# Disallow running as root
if test (id -u) -eq 0
    err "Do not run this script as root. Run it as your normal user so files land in your home directory."
    exit 1
end

# Resolve source directory robustly
set -l src ""
set -l tmpdir ""

if set -q WALLPAPER_SRC; and test -d "$WALLPAPER_SRC"
    set src "$WALLPAPER_SRC"
    info "Using WALLPAPER_SRC=$src"
else if test -d "$PWD/wallpapers"
    set src "$PWD/wallpapers"
    info "Using repo wallpapers at: $src"
else
    # Try script directory as a last resort
    set -l script_path (status -f)
    if test -n "$script_path"
        set -l script_dir (cd (dirname "$script_path"); pwd)
        if test -d "$script_dir/wallpapers"
            set src "$script_dir/wallpapers"
            info "Using script-adjacent wallpapers at: $src"
        end
    end
end

if test -z "$src"; or not test -d "$src"
    info "No local wallpapers found; attempting to download from GitHub"
    if not type -q curl
        err "curl not found; cannot download wallpapers automatically."
        err "Install curl or run with WALLPAPER_SRC pointing at a local folder."
        exit 1
    end
    if not type -q tar
        info "'tar' not found; attempting to install via sudo pacman"
        if type -q sudo; and type -q pacman
            sudo pacman -Sy --needed --noconfirm tar; or begin
                err "Failed to install 'tar' via pacman."
                exit 1
            end
        else
            err "Cannot auto-install 'tar' (need sudo and pacman)."
            err "Install 'tar' manually or provide WALLPAPER_SRC."
            exit 1
        end
    end

    set tmpdir (mktemp -d)
    if test -z "$tmpdir"
        err "Failed to create temporary directory"
        exit 1
    end

    set -l tarball "$tmpdir/arch-myway.tar.gz"
    set -l url "https://codeload.github.com/DigitalPals/arch-myway/tar.gz/refs/heads/main"
    info "Downloading $url"
    curl -fsSL "$url" -o "$tarball"; or begin
        err "Failed to download wallpaper archive"
        exit 1
    end
    # Extract archive
    tar -xzf "$tarball" -C "$tmpdir"; or begin
        err "Failed to extract wallpaper archive"
        exit 1
    end

    if test -d "$tmpdir/arch-myway-main/wallpapers"
        set src "$tmpdir/arch-myway-main/wallpapers"
        info "Using downloaded wallpapers at: $src"
    else
        err "Downloaded archive does not contain wallpapers/"
        exit 1
    end
end

set -l target_dir "$HOME/Pictures/Wallpapers"

# Ensure target exists
if not test -d "$target_dir"
    info "Creating $target_dir"
    mkdir -p -- "$target_dir"; or begin
        err "Failed to create $target_dir"
        exit 1
    end
else
    info "Target exists: $target_dir"
end

# Copy contents without overwriting existing files
info "Copying wallpapers (no overwrite) from $src to $target_dir"
cp -n -R -- "$src/." "$target_dir/"; or begin
    err "Copy failed"
    exit 1
end

log "Wallpapers are in place at $target_dir"

# Cleanup temp directory if used
if test -n "$tmpdir"; and test -d "$tmpdir"
    rm -rf -- "$tmpdir"
end
