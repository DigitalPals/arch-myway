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

# Ensure yay (AUR helper) is available; install if missing
function ensure_yay
    if type -q yay
        set -g SUMMARY_YAY "already present"
        return 0
    end
    info "Installing 'yay' (AUR helper)"
    if not type -q git
        if type -q sudo; and type -q pacman
            sudo pacman -Sy --needed --noconfirm git; or begin
                err "Failed to install 'git' via pacman"
                return 1
            end
        else
            err "Cannot install 'git' automatically (need sudo and pacman)"
            return 1
        end
    end
    if type -q sudo; and type -q pacman
        sudo pacman -Sy --needed --noconfirm base-devel; or begin
            err "Failed to install 'base-devel' via pacman"
            return 1
        end
    else
        err "Cannot install 'base-devel' automatically (need sudo and pacman)"
        return 1
    end
    set -l builddir (mktemp -d)
    if test -z "$builddir"
        err "Failed to create temporary build directory"
        return 1
    end
    info "Cloning yay-bin AUR into $builddir"
    git clone https://aur.archlinux.org/yay-bin.git "$builddir/yay-bin"; or begin
        err "Failed to clone yay-bin from AUR"
        return 1
    end
    pushd "$builddir/yay-bin" >/dev/null
    info "Building and installing yay"
    makepkg -si --noconfirm; or begin
        popd >/dev/null
        err "Failed to build/install yay"
        return 1
    end
    popd >/dev/null
    rm -rf -- "$builddir"
    set -g SUMMARY_YAY "installed"
end

# Resolve repo root and sources robustly
set -l repo_root ""
set -l tmpdir ""
set -l summary_repo_source ""

if set -q REPO_SRC; and test -d "$REPO_SRC"
    set repo_root "$REPO_SRC"
    info "Using REPO_SRC=$repo_root"
    set summary_repo_source "local repository (REPO_SRC)"
else if test -d "$PWD/wallpapers"; or test -d "$PWD/.config/caelestia"
    set repo_root "$PWD"
    info "Using repo root at: $repo_root"
    set summary_repo_source "local repository (PWD)"
else
    # Try script directory as a last resort
    set -l script_path (status -f)
    if test -n "$script_path"
        set -l script_dir (cd (dirname "$script_path"); pwd)
        if test -d "$script_dir/wallpapers"; or test -d "$script_dir/.config/caelestia"
            set repo_root "$script_dir"
            info "Using script-adjacent repo root at: $repo_root"
            set summary_repo_source "local repository (script dir)"
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
    set summary_repo_source "cloned repository to temporary directory"
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
set -l summary_wallpapers "skipped"
set -l summary_caelestia "skipped"

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
    set summary_wallpapers "copied to $target_wp"
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
    set summary_caelestia "overwritten in $target_c"
    set did_anything 1
else
    warn "No Caelestia source found; skipping"
end

if test $did_anything -eq 0
    warn "No file sources found; continuing to package setup."
end

# Install default applications via yay (if missing)
info "Ensuring default applications are installed via yay"
set -g SUMMARY_YAY "already present"
ensure_yay; or begin
    err "'yay' is required to install default applications"
    exit 1
end

set -l default_pkgs 1password-beta google-chrome obs-studio termius
set -l pkgs_installed
set -l pkgs_present
set -l pkgs_failed
for p in $default_pkgs
    if pacman -Qi -- $p >/dev/null 2>/dev/null
        log "$p is already installed"
        set pkgs_present $pkgs_present $p
    else
        info "Installing $p via yay"
        if yay -S --needed --noconfirm -- $p
            set pkgs_installed $pkgs_installed $p
        else
            err "Failed to install $p"
            set pkgs_failed $pkgs_failed $p
        end
    end
end

# Print status summary
echo
echo (set_color bryellow)'=== Summary ==='(set_color normal)
if test -n "$summary_repo_source"
    echo "- Repo source: $summary_repo_source"
end
echo "- Wallpapers:  $summary_wallpapers"
echo "- Caelestia:   $summary_caelestia"
echo "- yay:         $SUMMARY_YAY"

set -l join_installed (string join ", " $pkgs_installed)
set -l join_present (string join ", " $pkgs_present)
set -l join_failed (string join ", " $pkgs_failed)
if test -n "$join_installed"
    echo "- Apps installed: $join_installed"
else
    echo "- Apps installed: (none)"
end
if test -n "$join_present"
    echo "- Apps already present: $join_present"
end
if test -n "$join_failed"
    echo "- Apps failed: $join_failed"
end

# Cleanup temp directory if used
if test -n "$tmpdir"; and test -d "$tmpdir"
    rm -rf -- "$tmpdir"
end
