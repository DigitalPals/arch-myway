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
set -l summary_plymouth_pkg "skipped"
set -l summary_plymouth_theme "skipped"
set -l summary_plymouth_hook "unchanged"
set -l summary_initramfs "skipped"
set -l summary_kernel_params "unchanged"
set -l summary_bootloader_update "skipped"

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

# Plymouth install and theme setup (Cybex)
if pacman -Qi -- plymouth >/dev/null 2>/dev/null
    set summary_plymouth_pkg "already installed"
else
    info "Installing plymouth"
    if type -q sudo; and type -q pacman
        if sudo pacman -Sy --needed --noconfirm plymouth
            set summary_plymouth_pkg "installed"
        else
            err "Failed to install plymouth"
            set summary_plymouth_pkg "install failed"
        end
    else
        err "Cannot install plymouth automatically (need sudo and pacman)"
        set summary_plymouth_pkg "install skipped"
    end
end

# Source for cybex theme
set -l plymouth_theme_src ""
if set -q PLYMOUTH_THEME_SRC; and test -d "$PLYMOUTH_THEME_SRC"
    set plymouth_theme_src "$PLYMOUTH_THEME_SRC"
else if test -n "$repo_root"; and test -d "$repo_root/plymouth/themes/cybex"
    set plymouth_theme_src "$repo_root/plymouth/themes/cybex"
end

if test -n "$plymouth_theme_src"
    set -l plymouth_theme_dst "/usr/share/plymouth/themes/cybex"
    info "Installing Plymouth theme 'cybex' to $plymouth_theme_dst"
    if type -q sudo
        if sudo mkdir -p -- "/usr/share/plymouth/themes"; and sudo cp -R -f -- "$plymouth_theme_src" "$plymouth_theme_dst"
            set summary_plymouth_theme "installed"
            if type -q plymouth-set-default-theme
                info "Setting default Plymouth theme to 'cybex' and rebuilding initramfs"
                if sudo plymouth-set-default-theme -R cybex
                    set summary_plymouth_theme "installed and set as default"
                else
                    warn "Failed to set default theme via plymouth-set-default-theme"
                end
            else
                warn "plymouth-set-default-theme not found; theme copied only"
            end
        else
            err "Failed to copy Plymouth theme to $plymouth_theme_dst"
            set summary_plymouth_theme "copy failed"
        end
    else
        err "sudo not available; cannot install Plymouth theme"
        set summary_plymouth_theme "install skipped"
    end
else
    warn "No Plymouth theme source found; skipping theme install"
end

# Ensure mkinitcpio has the plymouth hook and rebuild initramfs
set -l mkconf "/etc/mkinitcpio.conf"
if test -r $mkconf
    set -l hooks_line (sudo awk '/^HOOKS=/{print; exit}' $mkconf)
    if test -n "$hooks_line"
        set -l hooks_inner (string replace -r '^HOOKS=\((.*)\)\s*$' '$1' -- $hooks_line)
        set -l tokens $hooks_inner
        if contains -- plymouth $tokens
            set summary_plymouth_hook "already present"
        else
            set -l idx_udev 0
            for i in (seq 1 (count $tokens))
                if test $tokens[$i] = udev
                    set idx_udev $i
                    break
                end
            end
            set -l tokens_new
            if test $idx_udev -gt 0
                set tokens_new $tokens[1..$idx_udev] plymouth $tokens[(math $idx_udev + 1)..-1]
            else
                set -l idx_base 0
                for i in (seq 1 (count $tokens))
                    if test $tokens[$i] = base
                        set idx_base $i
                        break
                    end
                end
                if test $idx_base -gt 0
                    set tokens_new $tokens[1..$idx_base] plymouth $tokens[(math $idx_base + 1)..-1]
                else
                    set tokens_new plymouth $tokens
                end
            end
            set -l new_hooks_line "HOOKS=("(string join ' ' $tokens_new)")"
            set -l tmpconf (mktemp)
            if test -z "$tmpconf"
                err "Failed to create temporary file for mkinitcpio.conf"
            else
                sudo awk -v new="$new_hooks_line" 'BEGIN{done=0} /^HOOKS=/{print new; done=1; next} {print} END{if(!done) exit 1}' $mkconf | sudo tee $tmpconf >/dev/null; and sudo mv "$tmpconf" "$mkconf"; and begin
                    set summary_plymouth_hook "added"
                end; or begin
                    err "Failed to update HOOKS in $mkconf"
                end
            end
        end
    else
        warn "HOOKS= line not found in $mkconf"
    end
else
    warn "Cannot read $mkconf to verify plymouth hook"
end

# Rebuild initramfs if plymouth hook was added or plymouth theme was set
if test "$summary_plymouth_hook" = added
    if type -q sudo; and type -q mkinitcpio
        info "Rebuilding initramfs (mkinitcpio -P)"
        if sudo mkinitcpio -P
            set summary_initramfs "rebuilt"
        else
            err "mkinitcpio rebuild failed"
            set summary_initramfs "rebuild failed"
        end
    else
        warn "Cannot rebuild initramfs automatically (need sudo and mkinitcpio)"
        set summary_initramfs "skipped"
    end
end

# Ensure kernel parameters include 'quiet splash' (GRUB and/or systemd-boot)
# GRUB
if test -r /etc/default/grub
    set -l grub_line (sudo awk -F= '/^GRUB_CMDLINE_LINUX_DEFAULT=/ {print $0; found=1} END{if(!found) exit 2}' /etc/default/grub)
    set -l have_line $status
    set -l current_tokens
    if test $have_line -eq 0
        set -l current (string replace -r '^GRUB_CMDLINE_LINUX_DEFAULT="(.*)"\s*$' '$1' -- $grub_line)
        set current_tokens $current
    else
        set current_tokens
    end
    set -l need_update 0
    if not contains -- quiet $current_tokens
        set current_tokens $current_tokens quiet
        set need_update 1
    end
    if not contains -- splash $current_tokens
        set current_tokens $current_tokens splash
        set need_update 1
    end
    if test $need_update -eq 1
        set -l new_line 'GRUB_CMDLINE_LINUX_DEFAULT="'(string join ' ' $current_tokens)'"'
        set -l tmpf (mktemp)
        if test -z "$tmpf"
            err "Failed to create temporary file for grub config"
        else
            sudo awk -v nl="$new_line" 'BEGIN{done=0} /^GRUB_CMDLINE_LINUX_DEFAULT=/{print nl; done=1; next} {print} END{if(!done) print nl}' /etc/default/grub | sudo tee $tmpf >/dev/null; and sudo mv $tmpf /etc/default/grub; and begin
                set summary_kernel_params "updated (grub)"
                if type -q grub-mkconfig
                    info "Updating GRUB config"
                    if sudo grub-mkconfig -o /boot/grub/grub.cfg
                        set summary_bootloader_update "grub updated"
                    else
                        set summary_bootloader_update "grub update failed"
                        warn "grub-mkconfig failed"
                    end
                else
                    set summary_bootloader_update "grub tool missing"
                    warn "grub-mkconfig not found"
                end
            end; or begin
                err "Failed to update /etc/default/grub"
            end
        end
    else
        if test "$summary_kernel_params" = "unchanged"
            set summary_kernel_params "already present (grub)"
        end
    end
end

# systemd-boot
if test -d /boot/loader/entries
    set -l updated_any 0
    for f in /boot/loader/entries/*.conf
        if test -r $f
            set -l opts_line (sudo awk '/^options /{print; found=1; exit} END{if(!found) exit 2}' $f)
            set -l have_opts $status
            set -l tokens
            if test $have_opts -eq 0
                set -l current (string replace -r '^options\s+(.*)$' '$1' -- $opts_line)
                set tokens $current
            else
                set tokens
            end
            set -l changed 0
            if not contains -- quiet $tokens
                set tokens $tokens quiet
                set changed 1
            end
            if not contains -- splash $tokens
                set tokens $tokens splash
                set changed 1
            end
            if test $changed -eq 1
                set -l new_opts 'options '(string join ' ' $tokens)
                set -l tmpf (mktemp)
                if test -z "$tmpf"
                    err "Failed to create temporary file for systemd-boot entry"
                else
                    sudo awk -v nl="$new_opts" 'BEGIN{done=0} /^options /{print nl; done=1; next} {print} END{if(!done) print nl}' $f | sudo tee $tmpf >/dev/null; and sudo mv $tmpf $f; and begin
                        set updated_any 1
                    end; or begin
                        err "Failed to update $f"
                    end
                end
            end
        end
    end
    if test $updated_any -eq 1
        if test "$summary_kernel_params" = "unchanged"
            set summary_kernel_params "updated (systemd-boot)"
        else
            set summary_kernel_params "$summary_kernel_params + systemd-boot"
        end
    else
        if test "$summary_kernel_params" = "unchanged"
            set summary_kernel_params "already present (systemd-boot)"
        end
    end
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
echo "- Plymouth:    pkg=$summary_plymouth_pkg, theme=$summary_plymouth_theme, hook=$summary_plymouth_hook, initramfs=$summary_initramfs"
echo "- Kernel:      params=$summary_kernel_params, bootloader_update=$summary_bootloader_update"

# Cleanup temp directory if used
if test -n "$tmpdir"; and test -d "$tmpdir"
    rm -rf -- "$tmpdir"
end
