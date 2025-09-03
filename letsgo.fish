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

# (debug pause helper removed)

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

function is_installed_pacman -a pkg
    pacman -Qi -- $pkg >/dev/null 2>/dev/null
end

function ensure_yay_packages
    # Usage: ensure_yay_packages pkg1 pkg2 ...
    if type -q yay
        yay -S --needed --noconfirm -- $argv
        return $status
    else
        return 1
    end
end

function copy_update_only -a src dst
    if not test -d "$dst"
        mkdir -p -- "$dst"; or return 1
    end
    # Update only: copy when source is newer than destination
    cp -R -u -- "$src/." "$dst/"
end

# Replace a block of text between exact marker lines with provided content
function replace_block -a file start end content
    set -l tmpout (mktemp)
    set -l tmpc (mktemp)
    if test -z "$tmpout"; or test -z "$tmpc"
        return 1
    end
    if not test -f "$file"
        mkdir -p (dirname "$file"); and touch "$file"
    end
    # Materialize content with escapes/newlines
    printf "%b" "$content" > "$tmpc"; or return 1
    # If both markers are present, replace inline at original position; else append at end
    if grep -F -q -- "$start" "$file"; and grep -F -q -- "$end" "$file"
        awk -v s="$start" -v e="$end" -v cf="$tmpc" 'BEGIN{skip=0;}
            $0==s {
                # print replacement content
                while ((getline l < cf) > 0) print l; close(cf);
                skip=1; next
            }
            skip==1 && $0==e { skip=0; next }
            skip==0 { print $0 }' "$file" > "$tmpout"; or return 1
        mv "$tmpout" "$file"
    else
        cat "$file" > "$tmpout"; and cat "$tmpc" >> "$tmpout"; or return 1
        mv "$tmpout" "$file"
    end
end

# Ensure Homebrew (Linuxbrew) is installed and available in fish
function ensure_brew
    # Try to find brew even if not in PATH
    set -l brew_bin ""
    if type -q brew
        set -g SUMMARY_BREW "already present"
        return 0
    else if test -x $HOME/.linuxbrew/bin/brew
        set brew_bin "$HOME/.linuxbrew/bin/brew"
    else if test -x /home/linuxbrew/.linuxbrew/bin/brew
        set brew_bin "/home/linuxbrew/.linuxbrew/bin/brew"
    else if test -x /opt/homebrew/bin/brew
        set brew_bin "/opt/homebrew/bin/brew"
    end

    if test -n "$brew_bin"
        # Load into current session and persist
        eval ($brew_bin shellenv); or begin
            # Fallback: force PATH for this session
            set -gx PATH (dirname $brew_bin) (realpath (dirname $brew_bin)/../sbin) $PATH
        end
        set -l fish_cfg "$HOME/.config/fish/config.fish"
        if not test -f "$fish_cfg"; mkdir -p (dirname "$fish_cfg"); touch "$fish_cfg"; end
        set -l brew_shellenv_line "eval ($brew_bin shellenv)"
        if not grep -q "$brew_shellenv_line" "$fish_cfg" 2>/dev/null
            echo "$brew_shellenv_line" >> "$fish_cfg"
        end
        set -g SUMMARY_BREW "available (PATH updated)"
        return 0
    end

    # Not found locally; install
    info "Installing Homebrew (Linuxbrew)"
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
    curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash; or begin
        err "Homebrew installation failed"
        return 1
    end
    # Detect again after install
    set brew_bin ""
    if test -x $HOME/.linuxbrew/bin/brew
        set brew_bin "$HOME/.linuxbrew/bin/brew"
    else if test -x /home/linuxbrew/.linuxbrew/bin/brew
        set brew_bin "/home/linuxbrew/.linuxbrew/bin/brew"
    else if test -x /opt/homebrew/bin/brew
        set brew_bin "/opt/homebrew/bin/brew"
    end
    if test -n "$brew_bin"
        eval ($brew_bin shellenv); or set -gx PATH (dirname $brew_bin) (realpath (dirname $brew_bin)/../sbin) $PATH
        set -l fish_cfg "$HOME/.config/fish/config.fish"
        if not test -f "$fish_cfg"; mkdir -p (dirname "$fish_cfg"); touch "$fish_cfg"; end
        set -l brew_shellenv_line "eval ($brew_bin shellenv)"
        if not grep -q "$brew_shellenv_line" "$fish_cfg" 2>/dev/null
            echo "$brew_shellenv_line" >> "$fish_cfg"
        end
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
    set -l oldpwd $PWD
    cd "$builddir/yay-bin"; or begin
        err "Failed to cd to $builddir/yay-bin"
        return 1
    end
    info "Building and installing yay"
    makepkg -si --noconfirm; or begin
        cd $oldpwd >/dev/null
        err "Failed to build/install yay"
        return 1
    end
    cd $oldpwd >/dev/null
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
set -l summary_hyprland_pkg "skipped"
set -l summary_autologin "skipped"
set -l summary_hypr_autostart "skipped"
set -l did_theme_rebuild 0
set -l summary_file_manager_pkg "skipped"
set -l summary_file_manager_default "unchanged"
set -l summary_snapper_pkg "skipped"
set -l summary_snapper_config "skipped"
set -l summary_snapper_hooks "skipped"
set -l summary_snapshots_mount "unchanged"
set -l summary_snapshots_boot "skipped"
set -l summary_snapshots_limit "unchanged"
set -l summary_snapper_initramfs "unchanged"
set -l summary_snapper_initramfs_verify "skipped"

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

    info "Copying wallpapers (update only) from $wallpapers_src to $target_wp"
    copy_update_only "$wallpapers_src" "$target_wp"; or begin
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

    info "Copying Caelestia config (update only) from $caelestia_src to $target_c"
    copy_update_only "$caelestia_src" "$target_c"; or begin
        err "Copy failed (caelestia)"
        exit 1
    end
    log "Caelestia config is in place at $target_c (updated)"
    set summary_caelestia "updated in $target_c"
    set did_anything 1
else
    warn "No Caelestia source found; skipping"
end

if test $did_anything -eq 0
    warn "No file sources found; continuing to package setup."
end

# Plymouth install and theme setup (Cybex)
if is_installed_pacman plymouth
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
        if sudo mkdir -p -- "/usr/share/plymouth/themes"
            # Copy with update-only and capture whether any files were actually copied
            set -l cp_out (sudo cp -R -u -v -- "$plymouth_theme_src/." "$plymouth_theme_dst/")
            set -l cp_out_str (string join ' ' $cp_out)
            set -l theme_updated 0
            if test -n "$cp_out_str"
                set summary_plymouth_theme "installed"
                set theme_updated 1
            else
                set summary_plymouth_theme "already present"
            end

            if type -q plymouth-set-default-theme
                # Read current default theme from plymouthd.conf if available
                set -l current_theme ""
                if test -r /etc/plymouth/plymouthd.conf
                    set -l current_theme_raw (sudo awk -F= '/^[[:space:]]*Theme[[:space:]]*=/{print $2; exit}' /etc/plymouth/plymouthd.conf)
                    set current_theme (string trim -- $current_theme_raw)
                    set current_theme (string replace -a '"' '' -- $current_theme)
                    set current_theme (string replace -a "'" '' -- $current_theme)
                end

                set -l need_set 0
                if test "$current_theme" != "cybex"
                    set need_set 1
                end
                if test $theme_updated -eq 1
                    # Ensure rebuild happens to pick up new theme assets
                    set need_set 1
                end

                if test $need_set -eq 1
                    info "Setting default Plymouth theme to 'cybex' and rebuilding initramfs"
                    if sudo plymouth-set-default-theme -R cybex
                        set summary_plymouth_theme "installed and set as default"
                        set did_theme_rebuild 1
                        set summary_initramfs "rebuilt"
                    else
                        warn "Failed to set default theme via plymouth-set-default-theme"
                    end
                else
                    info "Default Plymouth theme already 'cybex'; skipping rebuild"
                    # Keep summary as 'already present' if nothing changed
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
if not type -q sudo
    warn "sudo not available; skipping mkinitcpio hook update"
else if not test -r $mkconf
    warn "Cannot read $mkconf to verify plymouth hook"
else
    # Extract HOOKS inner content, ignoring leading whitespace and trailing comments
    set -l hooks_inner (sed -n -E 's/^[[:space:]]*HOOKS=\(([^)]*)\).*$/\1/p' $mkconf | head -n1)
    if test -n "$hooks_inner"
        set -l tokens $hooks_inner
        # Normalize tokens by stripping quotes for matching, but keep original tokens for output
        set -l tokens_clean
        for t in $tokens
            set -l q (string replace -a '"' '' -- $t)
            set q (string replace -a "'" '' -- $q)
            set tokens_clean $tokens_clean $q
        end
        if contains -- plymouth $tokens_clean
            set summary_plymouth_hook "already present"
        else
            set -l idx_udev 0
            for i in (seq 1 (count $tokens_clean))
                if test $tokens_clean[$i] = udev
                    set idx_udev $i
                    break
                end
            end
            set -l tokens_new
            if test $idx_udev -gt 0
                set tokens_new $tokens[1..$idx_udev] plymouth $tokens[(math $idx_udev + 1)..-1]
            else
                # Try after systemd (systemd-based images)
                set -l idx_systemd 0
                for i in (seq 1 (count $tokens_clean))
                    if test $tokens_clean[$i] = systemd
                        set idx_systemd $i
                        break
                    end
                end
                if test $idx_systemd -gt 0
                    set tokens_new $tokens[1..$idx_systemd] plymouth $tokens[(math $idx_systemd + 1)..-1]
                else
                    # Try after base
                    set -l idx_base 0
                    for i in (seq 1 (count $tokens_clean))
                        if test $tokens_clean[$i] = base
                            set idx_base $i
                            break
                        end
                    end
                    if test $idx_base -gt 0
                        set tokens_new $tokens[1..$idx_base] plymouth $tokens[(math $idx_base + 1)..-1]
                    else
                        # Append to end as safe fallback
                        set tokens_new $tokens plymouth
                    end
                end
            end
            set -l new_hooks_line "HOOKS=("(string join ' ' $tokens_new)")"
            set -l tmpconf (mktemp)
            if test -z "$tmpconf"
                err "Failed to create temporary file for mkinitcpio.conf"
            else
                awk -v new="$new_hooks_line" 'BEGIN{done=0} /^[[:space:]]*HOOKS=/{print new; done=1; next} {print} END{if(!done) exit 1}' $mkconf > $tmpconf
                if test $status -eq 0
                    if sudo install -m 644 $tmpconf $mkconf
                        set summary_plymouth_hook "added"
                    else
                        err "Failed to write $mkconf"
                    end
                else
                    warn "HOOKS= line not found or replace failed in $mkconf"
                end
            end
        end
    else
        warn "HOOKS= line not found in $mkconf"
    end
end

# Hyprland: install, enable TTY1 autologin, and autostart on login
if is_installed_pacman hyprland
    set summary_hyprland_pkg "already installed"
else
    info "Installing hyprland"
    if ensure_pacman_packages hyprland
        set summary_hyprland_pkg "installed"
    else
        err "Failed to install hyprland"
        set summary_hyprland_pkg "install failed"
    end
end

# Configure autologin on TTY1 via systemd getty override
set -l current_user (whoami)
if test -n "$current_user"
    set -l dropin_dir "/etc/systemd/system/getty@tty1.service.d"
    set -l override_path "$dropin_dir/override.conf"
    if type -q sudo
        set -l tmpf (mktemp)
        if test -z "$tmpf"
            err "Failed to create temporary file for getty override"
        else
            mkdir -p (dirname $tmpf) >/dev/null 2>&1
            printf "[Service]\nExecStart=\nExecStart=-/usr/bin/agetty --autologin %s --noclear %%I 38400 linux\n" "$current_user" > $tmpf
            if sudo mkdir -p -- "$dropin_dir"; and sudo install -m 644 "$tmpf" "$override_path"
                sudo systemctl daemon-reload >/dev/null 2>&1
                sudo systemctl enable getty@tty1.service >/dev/null 2>&1
                set summary_autologin "configured for $current_user"
            else
                err "Failed to write $override_path"
                set summary_autologin "failed"
            end
        end
    else
        warn "sudo not available; cannot configure autologin"
        set summary_autologin "skipped"
    end
end

# Add Hyprland autostart to fish login on TTY1
set -l fish_cfg "$HOME/.config/fish/config.fish"
set -l hypr_marker "arch-myway autostart"
set -l hypr_snip "# --- autostart Hyprland on tty1 ($hypr_marker) ---\nif status is-login\n    if test (tty) = \"/dev/tty1\"\n        if type -q Hyprland\n            exec Hyprland\n        end\n    end\nend\n# --- end $hypr_marker ---\n"
if not test -f "$fish_cfg"
    mkdir -p (dirname "$fish_cfg"); and touch "$fish_cfg"
end
# Replace any existing block between markers to avoid stale/broken content
set -l hypr_start "# --- autostart Hyprland on tty1 ($hypr_marker) ---"
set -l hypr_end   "# --- end $hypr_marker ---"
if not replace_block "$fish_cfg" "$hypr_start" "$hypr_end" "$hypr_snip"
    err "Failed to update $fish_cfg"
else
    set summary_hypr_autostart "configured"
end

# Also add autostart for bash login shells on TTY1 (in case fish isn't default)
set -l bash_profile "$HOME/.bash_profile"
set -l bash_marker "arch-myway-hypr"
set -l bash_snip "# --- $bash_marker ---\nif [ -z \"\\$DISPLAY\" ] && [ \"$(tty)\" = \"/dev/tty1\" ]; then\n  if command -v Hyprland >/dev/null 2>&1; then\n    exec Hyprland\n  fi\nfi\n# --- end $bash_marker ---\n"
if not test -f "$bash_profile"
    touch "$bash_profile"
end
set -l bash_start "# --- $bash_marker ---"
set -l bash_end   "# --- end $bash_marker ---"
replace_block "$bash_profile" "$bash_start" "$bash_end" "$bash_snip" >/dev/null 2>&1

# Pause after autologin + Hyprland
## (pause removed)

# File manager: ensure Nautilus and set as default
if is_installed_pacman nautilus
    set summary_file_manager_pkg "already installed"
else
    info "Installing Nautilus (file manager)"
    if ensure_pacman_packages nautilus
        set summary_file_manager_pkg "installed"
    else
        err "Failed to install Nautilus"
        set summary_file_manager_pkg "install failed"
    end
end

# Ensure xdg-mime is available to set defaults
if not type -q xdg-mime
    info "Installing xdg-utils to manage default applications"
    ensure_pacman_packages xdg-utils >/dev/null 2>&1
end

if type -q xdg-mime
    set -l current_fm (xdg-mime query default inode/directory 2>/dev/null)
    set -l target_fm "org.gnome.Nautilus.desktop"
    if test "$current_fm" != "$target_fm"
        info "Setting default file manager to Nautilus (inode/directory)"
        if xdg-mime default $target_fm inode/directory
            set summary_file_manager_default "set to Nautilus"
        else
            warn "Failed to set default file manager via xdg-mime"
            set summary_file_manager_default "set failed"
        end
    else
        set summary_file_manager_default "already Nautilus"
    end
else
    warn "xdg-mime not available; cannot set default file manager"
    set summary_file_manager_default "skipped"
end

# Rebuild initramfs if plymouth hook was added and theme didn't already rebuild
if test "$summary_plymouth_hook" = added; and test $did_theme_rebuild -eq 0
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

## (pause removed)

# Ensure kernel parameters include 'quiet splash' (GRUB and/or systemd-boot)
# GRUB
if test -r /etc/default/grub
    set -l grub_line (awk -F= '/^GRUB_CMDLINE_LINUX_DEFAULT=/ {print $0; found=1} END{if(!found) exit 2}' /etc/default/grub)
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
            awk -v nl="$new_line" 'BEGIN{done=0} /^[[:space:]]*GRUB_CMDLINE_LINUX_DEFAULT=/{print nl; done=1; next} {print} END{if(!done) print nl}' /etc/default/grub > $tmpf; and begin
                if sudo install -m 644 $tmpf /etc/default/grub
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
                else
                    err "Failed to update /etc/default/grub"
                end
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
                    awk -v nl="$new_opts" 'BEGIN{done=0} /^options /{print nl; done=1; next} {print} END{if(!done) print nl}' $f > $tmpf; and begin
                        if sudo install -m 644 $tmpf $f
                            set updated_any 1
                        else
                            err "Failed to install updated entry for $f"
                        end
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

## (pause removed)

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

set -l default_pkgs 1password-beta google-chrome obs-studio termius uwsm
set -l pkgs_installed
set -l pkgs_present
set -l pkgs_failed
for p in $default_pkgs
    if is_installed_pacman $p
        log "$p is already installed"
        set pkgs_present $pkgs_present $p
    else
        info "Installing $p via yay"
        if ensure_yay_packages $p
            set pkgs_installed $pkgs_installed $p
        else
            err "Failed to install $p"
            set pkgs_failed $pkgs_failed $p
        end
    end
end

## (pause removed)

# Snapper + snapshots on upgrades + boot integration
info "Configuring snapper for root snapshots on pacman/yay upgrades"

# Root FS must be btrfs
set -l root_fstype (findmnt -n -o FSTYPE / 2>/dev/null)
if test "$root_fstype" != btrfs
    warn "Root filesystem is not btrfs; skipping snapper setup"
else
    # Ensure required packages
    if ensure_pacman_packages snapper snap-pac btrfs-progs inotify-tools
        set summary_snapper_pkg "installed/ok"
    else
        if is_installed_pacman snapper; and is_installed_pacman snap-pac
            set summary_snapper_pkg "already installed"
        else
            err "Failed to install snapper dependencies"
        end
    end

    # Create root config if missing
    if not test -r /etc/snapper/configs/root
        info "Creating snapper root config"
        if type -q sudo; and sudo snapper -c root create-config /
            set summary_snapper_config "created"
        else
            err "Failed to create snapper root config"
        end
    else
        set summary_snapper_config "already exists"
    end

    # Ensure /.snapshots is mounted (snapper create-config creates the subvolume)
    if not findmnt -r /.snapshots >/dev/null 2>&1
        # Derive root filesystem UUID and subvolume to mount correct snapshots path
        set -l root_uuid (findmnt -n -o UUID / 2>/dev/null)
        # Determine current root subvol path (if any)
        set -l root_opts (findmnt -n -o OPTIONS / 2>/dev/null)
        set -l root_subvol ""
        for opt in (string split , -- $root_opts)
            if string match -q 'subvol=*' -- $opt
                set root_subvol (string split -m1 = -- $opt)[2]
            end
        end
        set -l snapshots_subvol ".snapshots"
        if test -n "$root_subvol"; and test "$root_subvol" != "/"; and test "$root_subvol" != "."
            set snapshots_subvol "$root_subvol/.snapshots"
        end
        if test -n "$root_uuid"
            set -l fstab_line "UUID=$root_uuid /.snapshots btrfs rw,relatime,ssd,space_cache=v2,subvol=$snapshots_subvol 0 0"
            if not grep -qsE '^[^#].*\s/\.snapshots\s' /etc/fstab 2>/dev/null
                set -l tmpf (mktemp)
                if test -n "$tmpf"
                    cat /etc/fstab > $tmpf 2>/dev/null
                    echo $fstab_line >> $tmpf
                    if sudo install -m 644 $tmpf /etc/fstab
                        mkdir -p /.snapshots 2>/dev/null
                        if sudo mount /.snapshots
                            set summary_snapshots_mount "mounted via fstab"
                        else
                            warn "fstab updated; mount of /.snapshots failed (check subvol name)"
                            set summary_snapshots_mount "fstab updated"
                        end
                    else
                        err "Failed to update /etc/fstab for /.snapshots"
                    end
                end
            else
                # fstab has an entry but not mounted yet; try mounting
                if sudo mount /.snapshots
                    set summary_snapshots_mount "mounted"
                else
                    warn "/.snapshots present in fstab but mount failed"
                end
            end
        else
            warn "Could not determine root UUID; skipping fstab entry for /.snapshots"
        end
    else
        set summary_snapshots_mount "already mounted"
    end

    # Ensure pacman hooks (snap-pac) are present
    if test -d /etc/pacman.d/hooks; and grep -Rsnq -- 'snap-pac' /etc/pacman.d/hooks >/dev/null 2>&1
        set summary_snapper_hooks "already present"
    else if test -d /usr/share/libalpm/hooks; and grep -Rsnq -- 'snap-pac' /usr/share/libalpm/hooks >/dev/null 2>&1
        set summary_snapper_hooks "present (system)"
    else
        # snap-pac package should have installed hooks; warn if not found
        warn "snap-pac hooks not detected; verify installation"
        set summary_snapper_hooks "unknown"
    end

    # Configure snapper retention: hard cap and no timeline snapshots
    if test -r /etc/snapper/configs/root
        set -l cf /etc/snapper/configs/root
        set -l tmpf (mktemp)
        if test -n "$tmpf"
            awk 'BEGIN{a=0;b=0;c=0;d=0;e=0}
                /^\s*TIMELINE_CREATE/ {print "TIMELINE_CREATE=\"no\""; a=1; next}
                /^\s*TIMELINE_CLEANUP/ {print "TIMELINE_CLEANUP=\"no\""; b=1; next}
                /^\s*NUMBER_CLEANUP/ {print "NUMBER_CLEANUP=\"yes\""; c=1; next}
                /^\s*NUMBER_LIMIT/ {print "NUMBER_LIMIT=5"; d=1; next}
                /^\s*NUMBER_MIN_AGE/ {print "NUMBER_MIN_AGE=0"; e=1; next}
                {print}
                END{
                    if(!a) print "TIMELINE_CREATE=\"no\"";
                    if(!b) print "TIMELINE_CLEANUP=\"no\"";
                    if(!c) print "NUMBER_CLEANUP=\"yes\"";
                    if(!d) print "NUMBER_LIMIT=5";
                    if(!e) print "NUMBER_MIN_AGE=0";
                }' $cf > $tmpf
            if sudo install -m 600 $tmpf $cf
                if test "$summary_snapshots_limit" = "unchanged"
                    set summary_snapshots_limit "snapper limit=5"
                else
                    set summary_snapshots_limit "$summary_snapshots_limit; snapper=5"
                end
            else
                warn "Failed to update snapper config retention settings"
            end
        end
    end

    # Enable cleanup timer and ensure timeline timer is disabled
    if type -q sudo; and type -q systemctl
        sudo systemctl enable --now snapper-cleanup.timer >/dev/null 2>&1
        sudo systemctl disable --now snapper-timeline.timer >/dev/null 2>&1
    end

    # Boot integration: GRUB (grub-btrfs) or systemd-boot (snapper-boot if available)
    set -l using_grub 0
    if test -r /etc/default/grub; or type -q grub-mkconfig
        set using_grub 1
    end

    if test $using_grub -eq 1
        # Install grub-btrfs from AUR and enable daemon to auto-regenerate menu
        if ensure_yay; and ensure_yay_packages grub-btrfs
            # Configure limit to 5 entries
            set -l gb_conf "/etc/default/grub-btrfs/config"
            # Ensure parent directory exists for config
            if type -q sudo
                sudo install -d -m 755 (dirname $gb_conf) >/dev/null 2>&1
            end
            if test -r $gb_conf
                set -l tmpf (mktemp)
                if test -n "$tmpf"
                    # Ensure limit and enable snapshot boot with overlayfs (RW behavior)
                    awk '
                        BEGIN{limit=0; boot=0; overlay=0; addrw=0}
                        /^#?\s*GRUB_BTRFS_LIMIT=/{print "GRUB_BTRFS_LIMIT=5"; limit=1; next}
                        /^#?\s*GRUB_BTRFS_SNAPSHOT_BOOTING=/{print "GRUB_BTRFS_SNAPSHOT_BOOTING=\"true\""; boot=1; next}
                        /^#?\s*GRUB_BTRFS_OVERLAYFS=/{print "GRUB_BTRFS_OVERLAYFS=\"true\""; overlay=1; next}
                        /^#?\s*GRUB_BTRFS_ADD_LINUX_ROOTFLAGS=/{print "GRUB_BTRFS_ADD_LINUX_ROOTFLAGS=\"rw\""; addrw=1; next}
                        {print}
                        END{
                            if(!limit) print "GRUB_BTRFS_LIMIT=5";
                            if(!boot) print "GRUB_BTRFS_SNAPSHOT_BOOTING=\"true\"";
                            if(!overlay) print "GRUB_BTRFS_OVERLAYFS=\"true\"";
                            if(!addrw) print "GRUB_BTRFS_ADD_LINUX_ROOTFLAGS=\"rw\"";
                        }' $gb_conf > $tmpf
                    sudo install -m 644 $tmpf $gb_conf >/dev/null 2>&1
                end
            else
                printf "GRUB_BTRFS_LIMIT=5\nGRUB_BTRFS_SNAPSHOT_BOOTING=\"true\"\nGRUB_BTRFS_OVERLAYFS=\"true\"\nGRUB_BTRFS_ADD_LINUX_ROOTFLAGS=\"rw\"\n" | sudo tee -a $gb_conf >/dev/null 2>&1
            end
            if test "$summary_snapshots_limit" = "unchanged"
                set summary_snapshots_limit "grub limit=5"
            else
                set summary_snapshots_limit "$summary_snapshots_limit; grub=5"
            end

            if type -q sudo; and type -q systemctl
                # Prefer path unit if present; else service
                if systemctl list-unit-files | grep -q '^grub-btrfsd\.path';
                    sudo systemctl enable --now grub-btrfsd.path >/dev/null 2>&1
                else if systemctl list-unit-files | grep -q '^grub-btrfsd\.service';
                    sudo systemctl enable --now grub-btrfsd.service >/dev/null 2>&1
                end
            end

            # Generate grub.cfg once to include current snapshots
            if type -q grub-mkconfig
                info "Updating GRUB config to include snapshot entries"
                if sudo grub-mkconfig -o /boot/grub/grub.cfg
                    set summary_snapshots_boot "grub entries ready"
                else
                    warn "grub-mkconfig failed for snapshots"
                end
            else
                warn "grub-mkconfig not found; snapshot entries will appear after next grub update"
            end
        else
            warn "Failed to install grub-btrfs via yay"
        end
    else if test -d /boot/loader/entries
        # systemd-boot: Create custom hook to generate boot entries for snapshots
        info "Configuring systemd-boot for snapshot booting"
        
        # Create a pacman hook to update systemd-boot entries after snapshots
        set -l hook_dir "/etc/pacman.d/hooks"
        set -l hook_file "$hook_dir/95-systemd-boot-snapshots.hook"
        
        if type -q sudo
            sudo mkdir -p $hook_dir 2>/dev/null
            
            # Create the hook file
            set -l hook_content "[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Updating systemd-boot entries for snapshots
When = PostTransaction
Exec = /usr/local/bin/update-systemd-boot-snapshots.sh
"
            set -l tmpf (mktemp)
            if test -n "$tmpf"
                echo "$hook_content" > $tmpf
                if sudo install -m 644 $tmpf $hook_file
                    info "Created pacman hook for systemd-boot snapshot entries"
                else
                    warn "Failed to create pacman hook"
                end
            end
            
            # Create the script that generates boot entries for snapshots
            set -l script_content '#!/bin/bash
# Update systemd-boot entries for btrfs snapshots

BOOT_DIR="/boot/loader/entries"
SNAPSHOT_DIR="/.snapshots"
MAX_ENTRIES=5

# Check if running on btrfs with snapshots
if [ ! -d "$SNAPSHOT_DIR" ]; then
    exit 0
fi

# Remove old snapshot entries
rm -f ${BOOT_DIR}/*-snapshot-*.conf 2>/dev/null

# Get the current default entry as template
DEFAULT_ENTRY=$(grep -l "^title.*Arch Linux$" ${BOOT_DIR}/*.conf 2>/dev/null | head -1)
if [ -z "$DEFAULT_ENTRY" ]; then
    DEFAULT_ENTRY=$(ls ${BOOT_DIR}/*.conf 2>/dev/null | head -1)
fi

if [ -z "$DEFAULT_ENTRY" ] || [ ! -f "$DEFAULT_ENTRY" ]; then
    exit 0
fi

# Extract kernel and initrd info from default entry
LINUX=$(grep "^linux" "$DEFAULT_ENTRY" | head -1)
INITRD=$(grep "^initrd" "$DEFAULT_ENTRY")
OPTIONS=$(grep "^options" "$DEFAULT_ENTRY" | head -1 | sed "s/^options //")

# Get list of snapshots (newest first)
SNAPSHOTS=$(ls -1dr ${SNAPSHOT_DIR}/*/info.xml 2>/dev/null | head -${MAX_ENTRIES})

COUNT=0
for INFO_FILE in $SNAPSHOTS; do
    SNAPSHOT_NUM=$(basename $(dirname "$INFO_FILE"))
    SNAPSHOT_PATH="/.snapshots/${SNAPSHOT_NUM}/snapshot"
    
    # Skip if not a valid number
    if ! [[ "$SNAPSHOT_NUM" =~ ^[0-9]+$ ]]; then
        continue
    fi
    
    # Get snapshot description and date
    DESC=$(grep "<description>" "$INFO_FILE" 2>/dev/null | sed "s/.*<description>\(.*\)<\/description>.*/\1/" | head -1)
    DATE=$(grep "<date>" "$INFO_FILE" 2>/dev/null | sed "s/.*<date>\(.*\)<\/date>.*/\1/" | head -1 | cut -d"T" -f1)
    
    if [ -z "$DESC" ]; then
        DESC="Snapshot ${SNAPSHOT_NUM}"
    fi
    
    # Create new boot entry for this snapshot
    ENTRY_FILE="${BOOT_DIR}/arch-snapshot-${SNAPSHOT_NUM}.conf"
    
    cat > "$ENTRY_FILE" << EOF
title   Arch Linux (Snapshot ${SNAPSHOT_NUM} - ${DATE})
${LINUX}
${INITRD}
options ${OPTIONS} rootflags=subvol=${SNAPSHOT_PATH}
EOF
    
    COUNT=$((COUNT + 1))
done

echo "Created ${COUNT} snapshot boot entries"
'
            set -l script_file "/usr/local/bin/update-systemd-boot-snapshots.sh"
            set -l tmpf2 (mktemp)
            if test -n "$tmpf2"
                echo "$script_content" > $tmpf2
                if sudo install -m 755 $tmpf2 $script_file
                    info "Created systemd-boot snapshot update script"
                    # Run it once to create initial entries
                    if sudo $script_file
                        set summary_snapshots_boot "systemd-boot entries configured"
                    else
                        warn "Failed to generate initial snapshot entries"
                        set summary_snapshots_boot "systemd-boot script created"
                    end
                else
                    warn "Failed to install snapshot update script"
                    set summary_snapshots_boot "systemd-boot setup failed"
                end
            end
        else
            warn "sudo not available for systemd-boot setup"
            set summary_snapshots_boot "systemd-boot (manual)"
        end
    else
        set summary_snapshots_boot "no supported bootloader detected"
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
    # Avoid GitHub prompts; operate without API usage
    set -lx HOMEBREW_NO_AUTO_UPDATE 1
    set -lx HOMEBREW_NO_GITHUB_API 1
    set -lx HOMEBREW_NO_INSTALL_FROM_API 1
    set -lx GIT_TERMINAL_PROMPT 0

    # Codex (formula) — try install; if not found, record failure
    if brew list --formula codex >/dev/null 2>&1
        log "brew package codex already installed"
        set brew_present $brew_present codex
    else
        info "Installing codex via brew"
        if brew install codex
            set brew_installed $brew_installed codex
        else
            warn "Failed to install codex via brew"
            set brew_failed $brew_failed codex
        end
    end

    # Claude Code (cask) — install with --cask (works on your machine)
    if brew list --cask claude-code >/dev/null 2>&1
        log "brew cask claude-code already installed"
        set brew_present $brew_present claude-code
    else
        info "Installing claude-code via brew cask"
        if brew install --cask claude-code
            set brew_installed $brew_installed claude-code
        else
            warn "Failed to install claude-code via brew cask"
            set brew_failed $brew_failed claude-code
        end
    end
end

# Pause after brew setup
## (pause removed)

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
echo "- Hyprland:    pkg=$summary_hyprland_pkg, autologin=$summary_autologin, autostart=$summary_hypr_autostart"
echo "- FileMgr:     pkg=$summary_file_manager_pkg, default=$summary_file_manager_default"
echo "- Snapper:     pkg=$summary_snapper_pkg, config=$summary_snapper_config, hooks=$summary_snapper_hooks, mount=$summary_snapshots_mount, boot=$summary_snapshots_boot, limit=$summary_snapshots_limit, initramfs=$summary_snapper_initramfs, verify=$summary_snapper_initramfs_verify"

# Derive overall Plymouth readiness status
set -l missing
switch $summary_plymouth_pkg
    case 'installed' 'already installed'
    case '*'
        set missing $missing pkg
end
switch $summary_plymouth_theme
    case 'installed*' 'installed and set as default' 'already present'
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

# Verify snapper-boot hook presence in active initramfs (systemd-boot path)
set -l verify_hook ""
if test -r /usr/lib/initcpio/hooks/snapper-boot; and test -r /usr/lib/initcpio/install/snapper-boot
    set verify_hook "snapper-boot"
else if test -r /usr/lib/initcpio/hooks/snapper; and test -r /usr/lib/initcpio/install/snapper
    set verify_hook "snapper"
end
if type -q lsinitcpio; and test -n "$verify_hook"
    set -l images (ls /boot/initramfs*.img 2>/dev/null)
    if test (count $images) -gt 0
        set -l found 0
        for img in $images
            if lsinitcpio -a $img 2>/dev/null | grep -qs "/usr/lib/initcpio/hooks/$verify_hook"
                set summary_snapper_initramfs_verify "present in "(basename $img)
                set found 1
                break
            end
        end
        if test $found -eq 0
            set summary_snapper_initramfs_verify "not present"
        end
    else
        set summary_snapper_initramfs_verify "no images"
    end
end
