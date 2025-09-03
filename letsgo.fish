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

set -l default_pkgs 1password-beta google-chrome obs-studio termius
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
