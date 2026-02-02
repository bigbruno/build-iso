#!/usr/bin/env bash
#-*- coding: utf-8 -*-
#
#  build-iso.sh - ISO Builder Tool for BigCommunity/BigLinux
#
#  Auxiliary tool for buildiso, adding automation, validations, and custom options
#  to the standard ISO build flow.
#

# Terminal configuration
export TERM=${TERM:-xterm-256color}

# Color definitions (since we removed dependency on external terminal_utils.sh)
blueDark="\e[1;38;5;33m"
mediumBlue="\e[1;38;5;32m" 
lightBlue="\e[1;38;5;39m"
cyan="\e[1;38;5;45m"
white="\e[1;97m"
reset="\e[0m"
red="\e[1;31m"
yellow="\e[1;33m"
green="\e[1;32m"

# Terminal utility functions
die() {
  local msg="$1"
  msg="$(sed 's/<[^>]*>//g' <<< "$msg")"
  echo -e "BP=>${red}error: ${white}${msg}${reset}"
  exit 1
}

msg() {
  local msg="$1"
  msg="$(sed 's/<[^>]*>//g' <<< "$msg")"
  echo -e "BP=>${blueDark}[${lightBlue}RUNNING${blueDark}]${reset} ${cyan}→${reset} ${white}${msg}${reset}"
}

msg_ok() {
  local msg="$1"
  msg="$(sed 's/<[^>]*>//g' <<< "$msg")"
  echo -e "BP=>${blueDark}[${green}SUCCESS${blueDark}]${reset} ${cyan}→${reset} ${white}${msg}${reset}"
}

msg_info() {
  local msg="$1"
  msg="$(sed 's/<[^>]*>//g' <<< "$msg")"
  echo -e "BP=>${blueDark}[${cyan}INFO${blueDark}]${reset} ${cyan}→${reset} ${white}${msg}${reset}"
}

msg_warning() {
  local msg="$1"
  msg="$(sed 's/<[^>]*>//g' <<< "$msg")"
  echo -e "BP=>${blueDark}[${yellow}WARNING${blueDark}]${reset} ${cyan}→${reset} ${white}${msg}${reset}"
}

replicate() {
  local char=${1:-'#'}
  local nsize=${2:-$(tput cols)}
  local line
  printf -v line "%*s" "$nsize" && echo -e "${blueDark}${line// /$char}${reset}"
}

#===============================================================================
# Core functions for ISO build
#===============================================================================

# Check and clean directories
prepare_directories() {
  msg "Preparing directories"
  
  # Create work directories if they don't exist
  mkdir -p "$WORK_PATH" &>/dev/null
  
  # Clean cache directories if they exist
  local path_dirs=(
    '/usr/share/manjaro-tools'
    '/usr/lib/manjaro-tools'
    '/var/lib/manjaro-tools/buildiso'
    '/var/cache/manjaro-tools/iso'
  )
  
  for cpath in "${path_dirs[@]}"; do
    if [[ -d "$cpath" ]]; then
      msg_info "Cleaning directory: $cpath"
      sudo rm -rf "$cpath"/* || true
    fi
  done
}

# Clone ISO profiles repository
clone_iso_profiles() {
  msg "Cloning ISO profiles repository"
  
  # Remove old directory if it exists
  if [[ -d "$WORK_PATH_ISO_PROFILES" ]]; then
    msg_info "Removing old ISO profiles directory"
    rm -rf "$WORK_PATH_ISO_PROFILES" || true
  fi
  
  # Clone repository
  msg_info "Cloning from: $ISO_PROFILES_REPO"
  if ! git clone --depth 1 "$ISO_PROFILES_REPO" "$WORK_PATH_ISO_PROFILES" &>/dev/null; then
    die "Failed to clone repository $ISO_PROFILES_REPO"
  fi
  
  # Mark as safe directory for git
  git config --global --add safe.directory "$WORK_PATH_ISO_PROFILES" || true
  
  # Verify directories
  if [[ ! -d "$PROFILE_PATH_EDITION" ]]; then
    die "Profile directory not found: $PROFILE_PATH_EDITION"
  fi
}

# Set up repository configuration
configure_repositories() {
  msg "Configuring repositories"
  
  # Configure pacman configuration files
  if [[ "$DISTRONAME" != "manjaro" ]]; then
    add_repositories_to_pacman "$PATH_MANJARO_TOOLS/pacman-default.conf"
    add_repositories_to_pacman "$PATH_MANJARO_TOOLS/pacman-multilib.conf"
  fi
  
  # Configure compression settings
  BRANCH_VAR="${DISTRONAME^^}_BRANCH"
  BRANCH="${!BRANCH_VAR}"
  
  if [[ "$BRANCH" == "stable" ]]; then
    msg_info "Configuring compression level for stable branch"
    sudo sed -i 's/-Xcompression-level [0-9]\+/-Xcompression-level 7/g' /usr/lib/manjaro-tools/util-iso.sh
  else
    msg_info "Configuring compression level for testing/unstable branch"
    sudo sed -i 's/-Xcompression-level [0-9]\+/-Xcompression-level 7/g' /usr/lib/manjaro-tools/util-iso.sh
  fi
  
  msg_info "Setting block size to 1024K"
  sudo sed -i 's/256K/1024K/g' /usr/lib/manjaro-tools/util-iso.sh

  # Enable parallel downloads for faster build
  msg_info "Enabling parallel downloads (10 simultaneous)"
  sudo sed -i '/ParallelDownloads/s/#//' "$PATH_MANJARO_TOOLS/pacman-default.conf"
  sudo sed -i '/ParallelDownloads/s/ParallelDownloads =.*/ParallelDownloads = 10/' "$PATH_MANJARO_TOOLS/pacman-default.conf"
  sudo sed -i '/ParallelDownloads/s/#//' "$PATH_MANJARO_TOOLS/pacman-multilib.conf"
  sudo sed -i '/ParallelDownloads/s/ParallelDownloads =.*/ParallelDownloads = 10/' "$PATH_MANJARO_TOOLS/pacman-multilib.conf"
}

# Add repository configurations to pacman.conf files
add_repositories_to_pacman() {
  local config_file="$1"
  
  msg_info "Adding repositories to: $config_file"
  
  # Configure BigCommunity repositories first (higher priority)
  if [[ "$DISTRONAME" == "bigcommunity" ]]; then
    case "$BIGCOMMUNITY_BRANCH" in
      stable)
        add_biglinux_update_stable | sudo tee -a "$config_file" >/dev/null
        add_community_stable | sudo tee -a "$config_file" >/dev/null
        add_community_extra | sudo tee -a "$config_file" >/dev/null
        ;;
      testing)
        add_biglinux_update_stable | sudo tee -a "$config_file" >/dev/null
        add_community_testing | sudo tee -a "$config_file" >/dev/null
        add_community_stable | sudo tee -a "$config_file" >/dev/null
        add_community_extra | sudo tee -a "$config_file" >/dev/null
        ;;
    esac
  fi
  
  # Configure BigLinux repositories after (lower priority)
  case "$BIGLINUX_BRANCH" in
    stable)
      add_biglinux_stable | sudo tee -a "$config_file" >/dev/null
      ;;
    testing)
      add_biglinux_testing | sudo tee -a "$config_file" >/dev/null
      add_biglinux_stable | sudo tee -a "$config_file" >/dev/null
      ;;
  esac
  
  # Add Manjaro mirrors last
  add_manjaro_mirrors "$config_file"
}

# Add Manjaro mirror list
add_manjaro_mirrors() {
  local config_file="$1"
  local servers=(
    'manjaro.c3sl.ufpr.br'
    'mirror.ufam.edu.br/manjaro'
    'linorg.usp.br/manjaro'
    'mirror.fcix.net/manjaro'
    'mirrors.sonic.net/manjaro'
  )
  
  for server in "${servers[@]}"; do
    msg_info "Adding mirror: $server"
    echo "Server = https://$server/$MANJARO_BRANCH/\$repo/\$arch" | sudo tee -a "$config_file" >/dev/null
  done
  echo "" | sudo tee -a "$config_file" >/dev/null
}

# Repository definition functions
add_biglinux_update_stable() {
  cat <<EOF
[biglinux-update-stable]
SigLevel = PackageRequired
Server = https://repo.biglinux.com.br/update-stable/\$arch

EOF
}

add_biglinux_stable() {
  cat <<EOF
[biglinux-stable]
SigLevel = PackageRequired
Server = https://repo.biglinux.com.br/stable/\$arch

EOF
}

add_biglinux_testing() {
  cat <<EOF
[biglinux-testing]
SigLevel = PackageRequired
Server = https://repo.biglinux.com.br/testing/\$arch

EOF
}

add_community_stable() {
  cat <<EOF
[community-stable]
SigLevel = PackageRequired
Server = https://repo.communitybig.org/stable/\$arch

EOF
}

add_community_testing() {
  cat <<EOF
[community-testing]
SigLevel = PackageRequired
Server = https://repo.communitybig.org/testing/\$arch

EOF
}

add_community_extra() {
  cat <<EOF
[community-extra]
SigLevel = PackageRequired
Server = https://repo.communitybig.org/extra/\$arch

EOF
}

# Setup Manjaro tools
setup_manjaro_tools() {
  msg "Setting up Manjaro tools"

  # Configure ISO profiles location
  msg_info "Configuring ISO profiles location"
  mkdir -p "$HOME_FOLDER/.config/manjaro-tools"
  echo "run_dir=$WORK_PATH_ISO_PROFILES" > "$HOME_FOLDER/.config/manjaro-tools/iso-profiles.conf"
  chmod 644 "$HOME_FOLDER/.config/manjaro-tools/iso-profiles.conf"
  msg_info "ISO profiles configuration: $(cat "$HOME_FOLDER/.config/manjaro-tools/iso-profiles.conf")"
  
  # Clean profiles to prevent duplication
  msg_info "Removing custom profiles directory"
  rm -rf "$WORK_PATH_ISO_PROFILES/custom-profiles"
  
  # Create and configure cache directories
  msg_info "Creating cache directories"
  sudo mkdir -p "$VAR_CACHE_MANJARO_TOOLS_ISO"
  sudo chmod 1777 "$VAR_CACHE_MANJARO_TOOLS_ISO"
  
  # Check buildiso availability
  if ! command -v buildiso &>/dev/null; then
    die "buildiso command not found. Please ensure manjaro-tools-iso is installed correctly."
  fi
  
  # Configure misobasedir and misolabel for each edition
  VOL_ID="${DISTRONAME^^}_LIVE_${EDITION^^}"
  msg_info "Configuring edition-specific paths: misobasedir=${DISTRONAME,,} and misolabel=${VOL_ID}"
  
  # Adjust configuration in kernels.cfg files
  msg_info "Adjusting kernel configuration files"
  find "$WORK_PATH_ISO_PROFILES" -name "kernels.cfg" -exec sudo sed -i "s/misobasedir=[^ ]*/misobasedir=${DISTRONAME,,}/g" {} + || true
  find "$WORK_PATH_ISO_PROFILES" -name "kernels.cfg" -exec sudo sed -i "s/misolabel=[^ ]*/misolabel=${VOL_ID}/g" {} + || true
  
  # Adjust configuration in grub-fix.sh files
   msg_info "Adjusting grub-fix.sh files"
   find "$WORK_PATH_ISO_PROFILES" -name "grub-fix.sh" -exec sudo sed -i "s|misobasedir=[^ ]* misolabel=[^ ]*|misobasedir=${DISTRONAME,,} misolabel=${VOL_ID}|g" {} + || true

  # Update theme paths
  msg_info "Adjusting theme paths"
  find "$WORK_PATH_ISO_PROFILES" -name "variable.cfg" -exec sudo sed -i \
    "s#grub_theme=/boot/grub/themes/[^/]*/theme.txt#grub_theme=/boot/grub/themes/${DISTRONAME_ISOPROFILES,,}-live/theme.txt#g" {} + || true
  
  find "$WORK_PATH_ISO_PROFILES" -name "grub.cfg" -exec sudo sed -i \
    "s#theme=(\$root)/boot/grub/themes/[^/]*/theme.txt#theme=(\$root)/boot/grub/themes/${DISTRONAME_ISOPROFILES,,}-live/theme.txt#g" {} + || true
  
  # Process any remove files in the profile
  process_remove_files
  
  # Run special commands if they exist
  if [[ -f "$PROFILE_PATH_EDITION/special-commands.sh" ]]; then
    msg_info "Executing special commands script"
    bash "$PROFILE_PATH_EDITION/special-commands.sh"
  fi
  
  # Configure distribution name
  msg_info "Configuring distribution name"
  sudo sed -i "s/dist_name=.*/dist_name=${DISTRONAME,,}/" /usr/lib/manjaro-tools/util.sh
  sudo sed -i "s/iso_name=.*/iso_name=${DISTRONAME,,}/" /usr/lib/manjaro-tools/util.sh
  sudo sed -i "s/dist_branding=.*/dist_branding=${DISTRONAME,,}/" /usr/lib/manjaro-tools/util.sh
  
  # Modify ISO filename format
  msg_info "Modifying ISO filename format"
  sudo sed -i "s/_\${profile}\${_edition}_\${dist_release//./}/-live/" /usr/lib/manjaro-tools/util-iso.sh
  
  # Configure profile
  msg_info "Setting profile path"
  sudo sed -i "s|profile=.*|profile=\"$EDITION\"|" /usr/lib/manjaro-tools/util-iso.sh
  sudo sed -i "s|profile_dir=.*|profile_dir=\"$PROFILE_PATH/$EDITION\"|" /usr/lib/manjaro-tools/util-iso.sh
  
  # Disable kernel version check
  msg_info "Disabling kernel version check"
  sudo sed -i '/\${iso_kernel}/s/^/#/' /usr/lib/manjaro-tools/util-iso.sh
  
  # Add cleanup functions
  msg_info "Adding system cleanup functions"
  add_cleanups
  
  # Configure root overlay
  msg_info "Configuring root overlay"
  sudo sed -i '/copy_overlay "\${profile_dir}\/root-overlay" "\${path}"/a [[ -e ${profile_dir}\/root-overlay ]] && copy_overlay "${profile_dir}\/root-overlay" "${path}"' /usr/lib/manjaro-tools/util-iso.sh
  
  # Enable plymouth and kms
  msg_info "Enabling plymouth and kms"
  sudo sed -i 's/keyboard keymap/keyboard keymap kms plymouth/g' /usr/share/manjaro-tools/mkinitcpio.conf
}

# Process remove files to remove packages from package files
# Also copies remove files to root-overlay for post-install removal
process_remove_files() {
  local remove_dir="$PROFILE_PATH_EDITION/root-overlay/tmp/packages-remove"
  
  # Create directory for remove files in root-overlay
  mkdir -p "$remove_dir"
  
  for remove_file in Root-remove Live-remove Mhwd-remove Desktop-remove; do
    if [[ -f "$PROFILE_PATH_EDITION/$remove_file" ]]; then
      # Copy remove file to root-overlay for post-install removal
      msg_info "Copying $remove_file to root-overlay for post-install removal"
      cp "$PROFILE_PATH_EDITION/$remove_file" "$remove_dir/"
      
      # Also remove from package list (prevents installation when possible)
      target_file="$PROFILE_PATH_EDITION/Packages-${remove_file%-remove}"
      if [[ -f "$target_file" ]]; then
        msg_info "Processing removals from $remove_file"
        while IFS= read -r package; do
          # Skip empty lines and comments
          [[ -z "$package" || "$package" =~ ^[[:space:]]*# ]] && continue
          # Remove package prefix like ">multilib " if present
          package_clean=$(echo "$package" | sed 's/^>[^ ]* //')
          sed -i "/^${package_clean}$/d" "$target_file"
          sed -i "/^>.*${package_clean}$/d" "$target_file"
        done < "$PROFILE_PATH_EDITION/$remove_file"
      fi
    fi
  done
}

# Add cleanup functions to ISO build
add_cleanups() {
  local cleanup_script="/usr/lib/manjaro-tools/util-iso-image.sh"
  
  # Verify target file exists and create backup
  if [[ ! -f "$cleanup_script" ]]; then
    msg_warning "Target script not found: $cleanup_script"
    return 1
  fi
  
  # Create backup
  sudo cp "$cleanup_script" "${cleanup_script}.backup"
  
  # Use specific pattern that only exists in the target file
  if ! sudo grep -q "^configure_live_image()" "$cleanup_script"; then
    msg_warning "Expected pattern not found in $cleanup_script"
    return 1
  fi
  
  # Add cleanup function call at the beginning of configure_live_image
  # This ensures cleanup runs before the live image is finalized
  # Insert after "configure_live_image(){" line
  sudo sed -i '/^configure_live_image(){$/a\    mkiso_build_iso_cleanups "$1"' "$cleanup_script"
  
  # Verify the modification was applied correctly
  if sudo grep -q "mkiso_build_iso_cleanups" "$cleanup_script"; then
    msg_info "Cleanup function successfully added to $cleanup_script"
  else
    msg_warning "Failed to add cleanup function to $cleanup_script"
    # Restore backup on failure
    sudo mv "${cleanup_script}.backup" "$cleanup_script"
    return 1
  fi
  
  # Add cleanup function
  sudo tee -a "$cleanup_script" >/dev/null <<-'EOF_CLEANUPS'

mkiso_build_iso_cleanups() {
  # Big cleanups
  local cpath="$1"

  # ===========================================
  # Post-install package removal
  # ===========================================
  local remove_dir="$cpath/tmp/packages-remove"
  if [[ -d "$remove_dir" ]]; then
    echo "[CLEANUP] Processing post-install package removals..."
    for remove_file in "$remove_dir"/*-remove; do
      if [[ -f "$remove_file" ]]; then
        echo "[CLEANUP] Processing: $(basename "$remove_file")"
        while IFS= read -r package; do
          # Skip empty lines and comments
          [[ -z "$package" || "$package" =~ ^[[:space:]]*# ]] && continue
          # Remove package prefix like ">multilib " if present
          package_clean=$(echo "$package" | sed 's/^>[^ ]* //')
          # Check if package is installed
          if chroot "$cpath" pacman -Qi "$package_clean" &>/dev/null; then
            echo "[CLEANUP] Removing package: $package_clean"
            chroot "$cpath" pacman -Rdd --noconfirm "$package_clean" 2>/dev/null || true
          else
            echo "[CLEANUP] Package not installed, skipping: $package_clean"
          fi
        done < "$remove_file"
      fi
    done
    # Clean up the remove directory
    rm -rf "$remove_dir"
  fi

  # ===========================================
  # Remove documentation
  # ===========================================
  rm -rf "$cpath/usr/share/doc"/* 2> /dev/null

  # Remove man pages
  rm -rf "$cpath/usr/share/man"/* 2> /dev/null

  # Clean LibreOffice configs
  local libreoffice_path="$cpath/usr/lib/libreoffice/share/config"
  if [[ -d "$libreoffice_path" ]]; then
    rm -f "$libreoffice_path"/images_{karasa_jaga,elementary,sukapura}* 2> /dev/null
    rm -f "$libreoffice_path"/images_{colibre,sifr_dark,sifr,breeze_dark,breeze}_svg.zip 2> /dev/null
  fi

  # Clean wallpapers
  local wallpapers_path="$cpath/usr/share/wallpapers"
  if [[ -d "$wallpapers_path" ]]; then
    rm -rf "$wallpapers_path"/{Altai,BytheWater,Cascade,ColdRipple,DarkestHour,EveningGlow,Flow,FlyingKonqui,IceCold,Kokkini,Next,Opal,Patak,SafeLanding,summer_1am,Autumn,Canopee,Cluster,ColorfulCups,Elarun,FallenLeaf,Fluent,Grey,Kite,MilkyWay,OneStandsOut,PastelHills,Path,Shell,Volna}
  fi
}
EOF_CLEANUPS
}

# Patch manjaro-tools to respect the community-release package
patch_manjaro_tools() {
  msg "Patching manjaro-tools to respect community-release package"
  
  local script="/usr/lib/manjaro-tools/util-iso-image.sh"
  
  # Replace the lsb-release configuration function
  sudo sed -i '/msg2 "Configuring lsb-release"/,+2c\
        msg2 "Configuring lsb-release: respecting community-release package"\
        # If community-release is installed, preserve its values\
        if grep -q "community-release" "$1/var/lib/pacman/local/"*"/files" 2>/dev/null; then\
            msg2 "community-release package detected, preserving its values"\
        else\
            sed -i -e "s/^.*DISTRIB_RELEASE.*/DISTRIB_RELEASE=\\"${dist_release}\\"/" "$1/etc/lsb-release"\
            sed -i -e "s/^.*DISTRIB_CODENAME.*/DISTRIB_CODENAME=\\"${dist_codename}\\"/" "$1/etc/lsb-release"\
        fi' "$script"
  
  # Verify the patch was applied
  if grep -q "respecting community-release package" "$script"; then
    msg_ok "Successfully patched manjaro-tools to respect community-release"
  else
    msg_warning "Failed to patch manjaro-tools. ISO build may override lsb-release values"
  fi
}

# Configure kernel for ISO
configure_kernel() {
  msg "Configuring kernel: $KERNEL"
  
  # Get appropriate kernel version
  case "$KERNEL" in
    oldlts)
      KERNEL=$(curl -s https://www.kernel.org/feeds/kdist.xml | 
          grep ": longterm" | 
          sed -n 's/.*<title>\(.*\): longterm<\/title>.*/\1/p' | 
          rev | cut -d "." -f2,3 | rev | 
          sed 's/\.//g' | sed -n '2p')
      ;;
    lts)
      KERNEL=$(curl -s https://www.kernel.org/feeds/kdist.xml | 
              grep ": longterm" | 
              sed -n 's/.*<title>\(.*\): longterm<\/title>.*/\1/p' | 
              rev | cut -d "." -f2,3 | rev | 
              sed 's/\.//g' | head -n1)
      ;;
    latest)
      KERNEL=$(curl -s https://raw.githubusercontent.com/biglinux/linux-latest/stable/PKGBUILD | 
              awk -F= '/kernelver=/{print $2}')
      ;;
    xanmod*)
      KERNEL="-$KERNEL"
      ;;
  esac
  
  # Clean previous kernel packages from all profile files
  msg_info "Removing previous kernel references"
  for pkg_file in "$PROFILE_PATH_EDITION"/Packages-*; do
    sed -i '/^linux[0-9]/d' "$pkg_file"
    sed -i '/^linux-latest/d' "$pkg_file"
  done
  
  # Configure kernel name
  if [[ "$KERNEL" == "-xanmod"* ]]; then
    KERNEL_NAME="${KERNEL#-}"
    msg_info "Adding linux-firmware to Packages-Root"
    echo "linux-firmware" >> "$PROFILE_PATH_EDITION/Packages-Root"
  elif [[ "$KERNEL" == "latest" ]]; then
    KERNEL_NAME="latest"
  else
    KERNEL_NAME="$KERNEL"
  fi
  
  # Format kernel version with dot
  if [[ "$KERNEL_NAME" =~ ^[0-9]+$ ]]; then
    if [[ ${#KERNEL_NAME} -eq 3 ]]; then
      KERNEL_VERSION_DOT="${KERNEL_NAME:0:1}.${KERNEL_NAME:1:2}"
    elif [[ ${#KERNEL_NAME} -eq 2 ]]; then
      KERNEL_VERSION_DOT="${KERNEL_NAME:0:1}.${KERNEL_NAME:1:1}"
    else
      KERNEL_VERSION_DOT="$KERNEL_NAME"
    fi
  else
    KERNEL_VERSION_DOT="$KERNEL_NAME"
  fi
  
  msg_info "Kernel version dot format: $KERNEL_VERSION_DOT"
  
  # Modify boot extras function for this kernel
  sudo sed -i "/prepare_boot_extras()/,/^}/c\\
  prepare_boot_extras(){\\
      mkdir -p \"\$2\"\\
      cp \$1/boot/amd-ucode.img \$2/amd_ucode.img\\
      cp \$1/boot/intel-ucode.img \$2/intel_ucode.img\\
      cp \$1/usr/share/licenses/amd-ucode/LIC* \$2/amd_ucode.LICENSE\\
      cp \$1/usr/share/licenses/intel-ucode/LIC* \$2/intel_ucode.LICENSE\\
      cp \$1/boot/memtest86+/memtest.bin \$2/memtest\\
      local kernel_file=\$(ls \$1/boot/vmlinuz-${KERNEL_VERSION_DOT}-* 2>/dev/null || ls \$1/boot/vmlinuz-*-${KERNEL_VERSION_DOT}* 2>/dev/null)\\
      if [ -n \"\$kernel_file\" ]; then\\
          cp \"\$kernel_file\" \$2/vmlinuz-x86_64\\
          echo \"Kernel copied: \$kernel_file -> \$2/vmlinuz-x86_64\"\\
      else\\
          echo \"Error: Kernel file not found for KERNEL_VERSION_DOT=${KERNEL_VERSION_DOT}\"\\
          ls -l \$1/boot/\\
      fi\\
  }" /usr/lib/manjaro-tools/util-iso-boot.sh
  
  # Replace kernel placeholders in package files
  for pkg_file in "$PROFILE_PATH_EDITION"/Packages-*; do
    msg_info "Updating kernel references in $pkg_file"
    sed -i "s/^KERNEL\b/linux${KERNEL_NAME}/g" "$pkg_file"
    sed -i "s/^KERNEL-headers\b/linux${KERNEL_NAME}-headers/g" "$pkg_file"
    sed -i "s/^KERNEL-\(.*\)/linux${KERNEL_NAME}-\1/g" "$pkg_file"
  done
}

# Set build info for the ISO
set_build_info() {
  local release_file="$PROFILE_PATH_EDITION/root-overlay/etc/big-release"
  local release_dir=$(dirname "$release_file")
  
  # Create directory if it doesn't exist
  mkdir -p "$release_dir"
  
  # Write build info
  {
    echo "BUILD_RELEASE=$RELEASE_TAG"
    echo "BUILD_BRANCH=$BIGLINUX_BRANCH"
    echo "UNIX_TIMESTAMP=$(($(date +%s) / 86400))"
  } >> "$release_file"
  
  msg_info "Build info written to $release_file"
}

# Configure ISO name and label
configure_iso_name() {
  msg_info "Configuring ISO name and label"
  
  # Set volume ID
  msg_info "Setting volume ID: ${VOL_ID}"
  sed -i "s/label=.*/label=${VOL_ID}/" "$PROFILE_PATH_EDITION"/profile.conf
  sudo sed -i "s/iso_label=.*/iso_label=${VOL_ID}/" "/usr/lib/manjaro-tools/util-iso.sh"
  
  # Set ISO basename based on distro and branch
  if [[ "$DISTRONAME" == 'bigcommunity' ]]; then
    case "$MANJARO_BRANCH/$BIGCOMMUNITY_BRANCH" in
      stable/stable) ISO_BASENAME="${DISTRONAME}_STABLE_${EDITION}_${RELEASE_TAG%%_*}_k${KERNEL}.iso" ;;
      stable/testing | testing/*) ISO_BASENAME="${DISTRONAME}_BETA_${EDITION}_${RELEASE_TAG%%_*}_k${KERNEL}.iso" ;;
      unstable/*) ISO_BASENAME="${DISTRONAME}_DEVELOPMENT_${EDITION}_${RELEASE_TAG%%_*}_k${KERNEL}.iso" ;;
    esac
  elif [[ "$DISTRONAME" == 'biglinux' ]]; then
    case "$MANJARO_BRANCH/$BIGLINUX_BRANCH" in
      stable/stable) ISO_BASENAME="${DISTRONAME}_STABLE_${EDITION}_${RELEASE_TAG%%_*}_k${KERNEL}.iso" ;;
      stable/testing | testing/*) ISO_BASENAME="${DISTRONAME}_BETA_${EDITION}_${RELEASE_TAG%%_*}_k${KERNEL}.iso" ;;
      unstable/*) ISO_BASENAME="${DISTRONAME}_DEVELOPMENT_${EDITION}_${RELEASE_TAG%%_*}_k${KERNEL}.iso" ;;
    esac
  else
    # Default for other distros
    case "$MANJARO_BRANCH/$BIGLINUX_BRANCH" in
      stable/stable) ISO_BASENAME="${DISTRONAME}_STABLE_${EDITION}_${RELEASE_TAG%%_*}_k${KERNEL}.iso" ;;
      stable/testing | testing/*) ISO_BASENAME="${DISTRONAME}_BETA_${EDITION}_${RELEASE_TAG%%_*}_k${KERNEL}.iso" ;;
      unstable/*) ISO_BASENAME="${DISTRONAME}_DEVELOPMENT_${EDITION}_${RELEASE_TAG%%_*}_k${KERNEL}.iso" ;;
    esac
  fi
  
  msg_info "ISO basename set to: $ISO_BASENAME"
}

# Verify ISO profiles configuration
verify_iso_profiles_conf() {
  local config_file="$HOME_FOLDER/.config/manjaro-tools/iso-profiles.conf"
  
  if [[ -f "$config_file" ]]; then
    msg_info "ISO profiles config file exists: $config_file"
    
    local run_dir_value=$(grep "^run_dir=" "$config_file" | cut -d'=' -f2)
    
    if [[ -n "$run_dir_value" ]]; then
      if [[ "$run_dir_value" == "/"* ]]; then
        msg_info "Run directory path is valid: $run_dir_value"
      else
        die "Run directory path seems invalid in $config_file"
      fi
    else
      die "Run directory not specified in $config_file"
    fi
  else
    die "ISO profiles config file not found: $config_file"
  fi
}

# Build ISO image
build_iso() {
  msg "Starting ISO build process"
  
  # Display build configuration
  replicate "#" 
  msg_info "BUILD COMMAND: buildiso -f -p $EDITION -b $MANJARO_BRANCH -k ${KERNEL_NAME}"
  msg_info "DISTRONAME: $DISTRONAME"
  msg_info "EDITION: $EDITION" 
  msg_info "KERNEL: ${KERNEL_NAME}"
  msg_info "ISO_BASENAME: $ISO_BASENAME"
  replicate "#"
  
  # Verify configuration
  verify_iso_profiles_conf
  
  # Execute buildiso
  msg_info "Executing buildiso command"
  LC_ALL=C sudo -u "$USERNAME" bash -c "buildiso -q -v"
  
  if $DEBUG; then
    LC_ALL=C sudo -u "$USERNAME" bash -c "buildiso -d zstd -f -p $EDITION -b $MANJARO_BRANCH -k linux${KERNEL_NAME};exit \$?"
  else
    LC_ALL=C sudo -u "$USERNAME" bash -c "buildiso -d zstd -f -p $EDITION -b $MANJARO_BRANCH -k linux${KERNEL_NAME} > /dev/null 2>&1; exit \$?"
  fi
  BUILD_EXIT_CODE=$?
  
  # Check build result
  if [[ $BUILD_EXIT_CODE -ne 0 ]]; then
    die "buildiso command failed with exit code $BUILD_EXIT_CODE"
  fi
  
  msg_ok "ISO build completed successfully with exit code $BUILD_EXIT_CODE"
}

# Move built ISO to designated path
cleanup_and_move_files() {
  msg "Processing built ISO files"
  
  # Find the most recently created ISO file
  OUTPUT_ISO_PATH_NAME=$(find "$VAR_CACHE_MANJARO_TOOLS_ISO" -type f -name "*.iso" -exec stat -c '%Y %n' {} + | sort -nr | awk 'NR==1 {print $2}')
  FILE_PKG=$(find "$VAR_CACHE_MANJARO_TOOLS_ISO" -type f -name "*-pkgs.txt" -exec stat -c '%Y %n' {} + | sort -nr | awk 'NR==1 {print $2}')
  
  # Update environment variables
  {
    echo "ISO_BASENAME=$ISO_BASENAME"
    echo "OUTPUT_ISO_PATH_NAME=$OUTPUT_ISO_PATH_NAME"
    echo "FILE_PKG=$FILE_PKG"
  } >> "$GITHUB_ENV"
  
  echo "iso_path=$WORK_PATH/$ISO_BASENAME" >> "$GITHUB_OUTPUT"
  
  # Move files to work path
  msg_info "Moving ISO and PKG files to $WORK_PATH"
  sudo mv -f "$OUTPUT_ISO_PATH_NAME" "$WORK_PATH/$ISO_BASENAME" || msg_warning "Failed to move ISO file: $OUTPUT_ISO_PATH_NAME"
  sudo mv -f "$FILE_PKG" "$WORK_PATH/${ISO_BASENAME}.pkgs" || msg_warning "Failed to move PKG file: $FILE_PKG"
  
  # Display file information
  replicate '#'
  msg_info "OUTPUT_ISO_PATH_NAME: $OUTPUT_ISO_PATH_NAME"
  msg_info "FILE_PKG            : $FILE_PKG"
  msg_info "ISO_BASENAME        : $ISO_BASENAME"
  msg_info "NEW PATH ISO FILE   : $WORK_PATH/$ISO_BASENAME"
  msg_info "NEW PATH ISO PKGS   : $WORK_PATH/${ISO_BASENAME}.pkgs"
  replicate '#'
}

install_required_packages() {
  msg "Installing required packages"
  
  # Clean working directories
  if type cleaning_working_directories &>/dev/null; then
    cleaning_working_directories
  fi
  
  # Install required packages that aren't in the Docker image
  msg_info "Installing specialized build tools"
  sudo pacman -Sy --quiet --needed --noconfirm \
    archiso \
    calamares \
    calamares-tools \
    cdrkit \
    manjaro-tools-base-git \
    manjaro-tools-iso-git \
    manjaro-tools-pkg-git \
    manjaro-tools-yaml-git \
    mkinitcpio \
    mktorrent \
    ncurses \
    shfmt \
    squashfs-tools
  
  if [[ $? -eq 0 ]]; then
    msg_ok "All packages installed successfully."
  else
    die "Failed to install required packages."
  fi
}

# Main build function
make_iso() {
  local start_datetime
  local end_datetime
  declare -g VOL_ID="${DISTRONAME^^}_LIVE_${EDITION^^}"
  
  # Record start time
  start_time=$(date +%s)
  start_datetime=$(date)
  
  msg_info "Starting ISO build process as user: $USERNAME"
  
  # Prepare environment
  prepare_directories
  install_required_packages
  clone_iso_profiles
  configure_repositories
  
  # Configure build
  setup_manjaro_tools
  patch_manjaro_tools
  configure_kernel
  
  # Add repositories to ISO
  msg_info "Adding repositories to ISO profile"
  add_repositories_to_iso "$WORK_PATH_ISO_PROFILES/shared/pacman.conf" "$BIGCOMMUNITY_BRANCH" "$BIGLINUX_BRANCH"
  
  # Set build info and ISO name
  set_build_info
  configure_iso_name
  
  # Build ISO
  build_iso
  
  # Process completed ISO
  cleanup_and_move_files
  
  # Record completion time
  end_datetime=$(date)
  msg_ok "ISO ${ISO_BASENAME} build completed successfully"
  msg_info "Start time : $start_datetime"
  msg_info "Finish time: $end_datetime"
  msg_info "Time elapsed: $(calc_elapsed_time)"
  
  exit 0
}

# Add repositories to ISO configuration
add_repositories_to_iso() {
  local config_file="$1"
  local bigcommunity_branch="$2"
  local biglinux_branch="$3"
  local config_dir
  
  config_dir=$(dirname "$config_file")
  
  # Ensure directory exists
  mkdir -p "$config_dir"
  
  # Add appropriate repositories based on distro and branch
  if [[ "$DISTRONAME" == "bigcommunity" ]]; then
    if [[ "$bigcommunity_branch" == "testing" ]]; then
      add_community_testing | sudo tee -a "$config_file" >/dev/null
      add_community_stable | sudo tee -a "$config_file" >/dev/null
      add_community_extra | sudo tee -a "$config_file" >/dev/null
    else
      add_community_stable | sudo tee -a "$config_file" >/dev/null
      add_community_extra | sudo tee -a "$config_file" >/dev/null
    fi
  fi
  
  if [[ "$biglinux_branch" == "testing" ]]; then
    add_biglinux_testing | sudo tee -a "$config_file" >/dev/null
    add_biglinux_stable | sudo tee -a "$config_file" >/dev/null
  else
    add_biglinux_stable | sudo tee -a "$config_file" >/dev/null
  fi
}

# Calculate elapsed time
calc_elapsed_time() {
  local end_time
  local duration
  local hours
  local minutes
  local seconds
  
  end_time=$(date +%s)
  duration=$((end_time - start_time))
  hours=$((duration / 3600))
  minutes=$(((duration % 3600) / 60))
  seconds=$((duration % 60))
  
  # Format values to have two digits
  hours=$(printf "%02d" $hours)
  minutes=$(printf "%02d" $minutes)
  seconds=$(printf "%02d" $seconds)
  
  echo "$hours:$minutes:$seconds"
}

#===============================================================================
# Script entry point
#===============================================================================

# Run ISO build automatically
make_iso