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

# Resolve repo root and sources robustly
set -l repo_root ""
set -l tmpdir ""

if set -q REPO_SRC; and test -d "$REPO_SRC"
    set repo_root "$REPO_SRC"
    info "Using REPO_SRC=$repo_root"
else if test -d "$PWD/wallpapers"; or test -d "$PWD/.config/caelestia"
    set repo_root "$PWD"
    info "Using repo root at: $repo_root"
else
    # Try script directory as a last resort
    set -l script_path (status -f)
    if test -n "$script_path"
        set -l script_dir (cd (dirname "$script_path"); pwd)
        if test -d "$script_dir/wallpapers"; or test -d "$script_dir/.config/caelestia"
            set repo_root "$script_dir"
            info "Using script-adjacent repo root at: $repo_root"
        end
    end
end

if test -z "$repo_root"
    info "No local repo content found; cloning from GitHub"
    if not type -q git
        info "'git' not found; attempting to install via sudo pacman"
        if type -q sudo; and type -q pacman
            sudo pacman -Sy --needed --noconfirm git; or begin
                err "Failed to install 'git' via pacman."
                exit 1
            end
        else
            err "Cannot auto-install 'git' (need sudo and pacman)."
            err "Install 'git' manually or provide REPO_SRC."
            exit 1
        end
    end

    set tmpdir (mktemp -d)
    if test -z "$tmpdir"
        err "Failed to create temporary directory"
        exit 1
    end
    set repo_root "$tmpdir/arch-myway"
    info "Cloning into $repo_root"
    git clone --depth 1 https://github.com/DigitalPals/arch-myway.git "$repo_root"; or begin
        err "Failed to clone repository"
        exit 1
    end
end

# Determine sources for each component
set -l wallpapers_src ""
set -l caelestia_src ""

if set -q WALLPAPER_SRC; and test -d "$WALLPAPER_SRC"
    set wallpapers_src "$WALLPAPER_SRC"
    info "Using WALLPAPER_SRC=$wallpapers_src"
else if test -n "$repo_root"; and test -d "$repo_root/wallpapers"
    set wallpapers_src "$repo_root/wallpapers"
    info "Wallpapers source: $wallpapers_src"
end

if set -q CAELESTIA_SRC; and test -d "$CAELESTIA_SRC"
    set caelestia_src "$CAELESTIA_SRC"
    info "Using CAELESTIA_SRC=$caelestia_src"
else if test -n "$repo_root"; and test -d "$repo_root/.config/caelestia"
    set caelestia_src "$repo_root/.config/caelestia"
    info "Caelestia source: $caelestia_src"
end

set -l did_anything 0

# Wallpapers copy
if test -n "$wallpapers_src"
    set -l target_wp "$HOME/Pictures/Wallpapers"
    if not test -d "$target_wp"
        info "Creating $target_wp"
        mkdir -p -- "$target_wp"; or begin
            err "Failed to create $target_wp"
            exit 1
        end
    else
        info "Target exists: $target_wp"
    end

    info "Copying wallpapers (no overwrite) from $wallpapers_src to $target_wp"
    cp -n -R -- "$wallpapers_src/." "$target_wp/"; or begin
        err "Copy failed (wallpapers)"
        exit 1
    end
    log "Wallpapers are in place at $target_wp"
    set did_anything 1
else
    warn "No wallpapers source found; skipping"
end

# Caelestia config copy
if test -n "$caelestia_src"
    set -l target_c "$HOME/.config/caelestia"
    if not test -d "$target_c"
        info "Creating $target_c"
        mkdir -p -- "$target_c"; or begin
            err "Failed to create $target_c"
            exit 1
        end
    else
        info "Target exists: $target_c"
    end

    info "Copying Caelestia config (overwrite) from $caelestia_src to $target_c"
    cp -R -f -- "$caelestia_src/." "$target_c/"; or begin
        err "Copy failed (caelestia)"
        exit 1
    end
    log "Caelestia config is in place at $target_c (overwritten)"
    set did_anything 1
else
    warn "No Caelestia source found; skipping"
end

if test $did_anything -eq 0
    err "Nothing to do: no sources found."
    exit 1
end

# Cleanup temp directory if used
if test -n "$tmpdir"; and test -d "$tmpdir"
    rm -rf -- "$tmpdir"
end
