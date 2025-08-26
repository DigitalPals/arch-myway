#!/usr/bin/env fish

# Run from a local clone of this repo to apply setup tasks
# Usage:
#   git clone https://github.com/DigitalPals/arch-myway.git
#   cd arch-myway
#   fish ./letsgo.fish

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

# Helpers
function ensure_pacman_packages
    # Usage: ensure_pacman_packages pkg1 pkg2 ...
    if type -q sudo; and type -q pacman
        sudo pacman -Sy --needed --noconfirm $argv
        return $status
    else
        return 1
    end
end

function copy_merge_no_overwrite -a src dst
    if not test -d "$dst"
        mkdir -p -- "$dst"; or return 1
    end
    cp -n -R -- "$src/." "$dst/"
end

function copy_overwrite -a src dst
    if not test -d "$dst"
        mkdir -p -- "$dst"; or return 1
    end
    cp -R -f -- "$src/." "$dst/"
end

# Ensure Homebrew (Linuxbrew) is installed and available in fish
function ensure_brew
    if type -q brew
        set -g SUMMARY_BREW "already present"
        return 0
    end
    info "Installing Homebrew (Linuxbrew)"
    # Ensure curl for installer
    if not type -q curl
        info "Installing curl via pacman"
        ensure_pacman_packages curl; or begin
            err "Failed to install curl needed for Homebrew installer"
            return 1
        end
    end
    if not type -q bash
        err "bash not found; please install bash and re-run"
        return 1
    end
    # Run official installer (pipe into bash; fish doesn't support $() )
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash; or begin
        err "Homebrew installation failed"
        return 1
    end
    # Locate brew binary and load into current session
    set -l brew_bin ""
    if test -x $HOME/.linuxbrew/bin/brew
        set brew_bin "$HOME/.linuxbrew/bin/brew"
    else if test -x /home/linuxbrew/.linuxbrew/bin/brew
        set brew_bin "/home/linuxbrew/.linuxbrew/bin/brew"
    else if test -x /opt/homebrew/bin/brew
        set brew_bin "/opt/homebrew/bin/brew"
    end
    if test -n "$brew_bin"
        eval ($brew_bin shellenv)
        # Persist into fish config
        set -l fish_cfg "$HOME/.config/fish/config.fish"
        if not test -f "$fish_cfg"; mkdir -p (dirname "$fish_cfg"); touch "$fish_cfg"; end
        set -l brew_shellenv_line "eval ($brew_bin shellenv)"
        if not grep -q "$brew_shellenv_line" "$fish_cfg" 2>/dev/null
            echo "$brew_shellenv_line" >> "$fish_cfg"
        end
    end
    if type -q brew
        set -g SUMMARY_BREW "installed"
        return 0
    else
        err "brew not found after installation"
        return 1
    end
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
    # Assumes git and base-devel were ensured earlier
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

# Resolve repo root (local only)
set -l repo_root ""
set -l summary_repo_source ""

if test -d "$PWD/wallpapers"; or test -d "$PWD/.config/caelestia"; or test -d "$PWD/plymouth"
    set repo_root "$PWD"
    set summary_repo_source "local repository (PWD)"
else
    set -l script_path (status -f)
    if test -n "$script_path"
        set -l script_dir (cd (dirname "$script_path"); pwd)
        if test -d "$script_dir"
            set repo_root "$script_dir"
            set summary_repo_source "local repository (script dir)"
        end
    end
end
if test -z "$repo_root"
    err "Could not determine repository root. Please run from within the cloned repo."
    exit 1
end

# Determine sources for each component from local repo only
set -l wallpapers_src ""
set -l caelestia_src ""

if test -n "$repo_root"; and test -d "$repo_root/wallpapers"
    set wallpapers_src "$repo_root/wallpapers"
    info "Wallpapers source: $wallpapers_src"
end

if test -n "$repo_root"; and test -d "$repo_root/.config/caelestia"
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
    copy_merge_no_overwrite "$wallpapers_src" "$target_wp"; or begin
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
    copy_overwrite "$caelestia_src" "$target_c"; or begin
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
    if ensure_pacman_packages plymouth
        set summary_plymouth_pkg "installed"
    else
        err "Failed to install plymouth"
        set summary_plymouth_pkg "install failed"
    end
end

# Source for cybex theme (local repo only)
set -l plymouth_theme_src ""
if test -n "$repo_root"; and test -d "$repo_root/plymouth/themes/cybex"
    set plymouth_theme_src "$repo_root/plymouth/themes/cybex"
end

if test -n "$plymouth_theme_src"
    set -l plymouth_theme_dst "/usr/share/plymouth/themes/cybex"
    info "Installing Plymouth theme 'cybex' to $plymouth_theme_dst"
    if type -q sudo
        if sudo mkdir -p -- "/usr/share/plymouth/themes"; and sudo cp -R -f -- "$plymouth_theme_src/." "$plymouth_theme_dst/"
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
if type -q sudo; and type -q pacman
    info "Ensuring prerequisites (git, base-devel)"
    sudo pacman -Sy --needed --noconfirm git base-devel; or begin
        err "Failed to install prerequisites (git, base-devel)"
        exit 1
    end
else
    err "Cannot install prerequisites automatically (need sudo and pacman)"
    exit 1
end
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

# Install Homebrew and selected brew packages
info "Ensuring Homebrew (brew) is installed"
set -g SUMMARY_BREW "already present"
ensure_brew; or begin
    warn "Homebrew not available; skipping brew packages"
end

set -l brew_installed
set -l brew_present
set -l brew_failed
if type -q brew
    set -l brew_pkgs codex claude-code
    for b in $brew_pkgs
        if brew list --formula $b >/dev/null 2>&1; or brew list --cask $b >/dev/null 2>&1
            log "brew package $b already installed"
            set brew_present $brew_present $b
        else
            info "Installing $b via brew (best-effort)"
            if brew install $b >/dev/null 2>&1
                set brew_installed $brew_installed $b
            else
                set -l ok 0
                if test $b = claude-code
                    brew tap anthropic/claude >/dev/null 2>&1; and brew install claude >/dev/null 2>&1; and set ok 1
                    if test $ok -eq 1
                        set brew_installed $brew_installed claude
                    end
                end
                if test $ok -eq 0
                    warn "Failed to install $b via brew"
                    set brew_failed $brew_failed $b
                end
            end
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

# Derive overall Plymouth readiness status
set -l missing
switch $summary_plymouth_pkg
    case 'installed' 'already installed'
    case '*'
        set missing $missing pkg
end
switch $summary_plymouth_theme
    case 'installed*' 'installed and set as default'
    case '*'
        set missing $missing theme
end
switch $summary_plymouth_hook
    case 'already present' 'added'
    case '*'
        set missing $missing hook
end
switch $summary_kernel_params
    case 'updated*' 'already present*'
    case '*'
        set missing $missing kernel-params
end

if test (count $missing) -eq 0
    echo "- Plymouth readiness: ready"
else
    echo "- Plymouth readiness: incomplete (missing: "(string join ", " $missing)")"
    echo (set_color yellow)"Tips:"(set_color normal)
    # Derive a concrete path for the Cybex theme if available
    set -l theme_tip_path ""
    if test -n "$plymouth_theme_src"; and test -d "$plymouth_theme_src"
        set theme_tip_path "$plymouth_theme_src"
    else if test -n "$repo_root"; and test -d "$repo_root/plymouth/themes/cybex"
        set theme_tip_path "$repo_root/plymouth/themes/cybex"
    end
    if contains -- pkg $missing
        echo "  - Install plymouth: sudo pacman -Sy --needed plymouth"
    end
    if contains -- theme $missing
        echo "  - Install and set theme:"
        echo "      sudo mkdir -p /usr/share/plymouth/themes"
        if test -n "$theme_tip_path"
            echo "      sudo cp -R \"$theme_tip_path\" /usr/share/plymouth/themes/"
        else
            echo "      sudo cp -R <path-to-cybex-theme> /usr/share/plymouth/themes/"
        end
        echo "      sudo plymouth-set-default-theme -R cybex"
    end
    if contains -- hook $missing
        echo "  - Add 'plymouth' to HOOKS in /etc/mkinitcpio.conf then rebuild:"
        echo "      sudo mkinitcpio -P"
    end
    if contains -- kernel-params $missing
        echo "  - Ensure kernel params include 'quiet splash':"
        echo "      GRUB: edit /etc/default/grub then sudo grub-mkconfig -o /boot/grub/grub.cfg"
        echo "      systemd-boot: ensure each entry in /boot/loader/entries/*.conf has 'options ... quiet splash'"
    end
end

# Brew summary
if type -q brew
    set -l join_b_inst (string join ", " $brew_installed)
    set -l join_b_pres (string join ", " $brew_present)
    set -l join_b_fail (string join ", " $brew_failed)
    echo "- brew:        $SUMMARY_BREW"
    if test -n "$join_b_inst"
        echo "- Brew installed: $join_b_inst"
    end
    if test -n "$join_b_pres"
        echo "- Brew already present: $join_b_pres"
    end
    if test -n "$join_b_fail"
        echo "- Brew failed: $join_b_fail"
    end
end

# No temporary directories to cleanup (local-only mode)
