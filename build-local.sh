#!/usr/bin/env bash
#
# build-local.sh - Build BigCommunity/BigLinux ISO locally
#
# This script automates the entire local ISO build process, including:
# - Automatic dependency installation
# - Custom output directory selection
# - Interactive menu for configuration
#

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================

CONFIG_DIR="${HOME}/.config/build-iso"
CONFIG_FILE="${CONFIG_DIR}/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
DEFAULT_OUTPUT_DIR="${HOME}/ISO"
DEFAULT_DISTRO="bigcommunity"
DEFAULT_EDITION="gnome"
DEFAULT_MANJARO_BRANCH="stable"
DEFAULT_BIGLINUX_BRANCH="stable"
DEFAULT_BIGCOMMUNITY_BRANCH="stable"
DEFAULT_KERNEL="lts"

# =============================================================================
# TERMINAL COLORS
# =============================================================================

export TERM=${TERM:-xterm-256color}
blueDark="\e[1;38;5;33m"
lightBlue="\e[1;38;5;39m"
cyan="\e[1;38;5;45m"
white="\e[1;97m"
reset="\e[0m"
red="\e[1;31m"
green="\e[1;32m"
yellow="\e[1;33m"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

die() {
  echo -e "${red}ERRO: ${white}$1${reset}" >&2
  exit 1
}

msg() {
  echo -e "${blueDark}[${lightBlue}RUNNING${blueDark}]${reset} ${cyan}→${reset} ${white}$1${reset}"
}

msg_ok() {
  echo -e "${blueDark}[${green}SUCCESS${blueDark}]${reset} ${cyan}→${reset} ${white}$1${reset}"
}

msg_info() {
  echo -e "${blueDark}[${cyan}INFO${blueDark}]${reset} ${cyan}→${reset} ${white}$1${reset}"
}

msg_warning() {
  echo -e "${blueDark}[${yellow}WARNING${blueDark}]${reset} ${cyan}→${reset} ${white}$1${reset}"
}

# =============================================================================
# CONFIGURATION MANAGEMENT
# =============================================================================

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
  fi
  
  # Set defaults if not configured
  OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
  DISTRO="${DISTRO:-$DEFAULT_DISTRO}"
  EDITION="${EDITION:-$DEFAULT_EDITION}"
  MANJARO_BRANCH="${MANJARO_BRANCH:-$DEFAULT_MANJARO_BRANCH}"
  BIGLINUX_BRANCH="${BIGLINUX_BRANCH:-$DEFAULT_BIGLINUX_BRANCH}"
  BIGCOMMUNITY_BRANCH="${BIGCOMMUNITY_BRANCH:-$DEFAULT_BIGCOMMUNITY_BRANCH}"
  KERNEL="${KERNEL:-$DEFAULT_KERNEL}"
}

save_config() {
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_FILE" << EOF
# BigCommunity ISO Builder Configuration
OUTPUT_DIR="$OUTPUT_DIR"
DISTRO="$DISTRO"
EDITION="$EDITION"
MANJARO_BRANCH="$MANJARO_BRANCH"
BIGLINUX_BRANCH="$BIGLINUX_BRANCH"
BIGCOMMUNITY_BRANCH="$BIGCOMMUNITY_BRANCH"
KERNEL="$KERNEL"
EOF
  msg_ok "Configuração salva em $CONFIG_FILE"
}

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================

check_dependencies() {
  local missing=()
  
  # Check for required packages
  local packages=(
    "manjaro-tools-iso-git"
    "git"
    "base-devel"
  )
  
  for pkg in "${packages[@]}"; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
      missing+=("$pkg")
    fi
  done
  
  echo "${missing[@]}"
}

setup_environment() {
  clear
  echo -e "${cyan}════════════════════════════════════════${reset}"
  echo -e "${white}     Configurando Ambiente de Build     ${reset}"
  echo -e "${cyan}════════════════════════════════════════${reset}"
  echo
  
  # Check if running as root
  if [[ $EUID -eq 0 ]]; then
    die "Não execute este script como root. Use sudo quando necessário."
  fi
  
  msg "Verificando dependências..."
  
  local missing
  missing=$(check_dependencies)
  
  if [[ -n "$missing" ]]; then
    msg_warning "Pacotes faltando: $missing"
    echo
    read -rp "Deseja instalar automaticamente? [S/n] " response
    response=${response:-S}
    
    if [[ "${response,,}" =~ ^(s|sim|y|yes)$ ]]; then
      msg "Instalando pacotes..."
      
      # Add biglinux repository if needed
      if ! grep -q "\[biglinux-stable\]" /etc/pacman.conf; then
        msg_info "Adicionando repositório BigLinux..."
        echo -e "\n[biglinux-stable]\nSigLevel = PackageRequired\nServer = https://repo.biglinux.com.br/stable/\$arch" | sudo tee -a /etc/pacman.conf > /dev/null
      fi
      
      # Setup keys
      msg "Configurando chaves GPG..."
      if [[ ! -d /tmp/biglinux-key ]]; then
        git clone --depth 1 https://github.com/biglinux/biglinux-key.git /tmp/biglinux-key
      fi
      sudo install -dm755 /etc/pacman.d/gnupg/
      sudo install -m0644 /tmp/biglinux-key/usr/share/pacman/keyrings/* /etc/pacman.d/gnupg/
      sudo pacman-key --init
      sudo pacman-key --populate
      
      # Install missing packages
      sudo pacman -Sy --noconfirm $missing
      
      msg_ok "Pacotes instalados com sucesso!"
    else
      msg_warning "Instalação cancelada. O ambiente não está completo."
      return 1
    fi
  else
    msg_ok "Todas as dependências estão instaladas!"
  fi
  
  # Create necessary directories
  msg "Criando diretórios..."
  mkdir -p "$OUTPUT_DIR"
  mkdir -p "$HOME/.config/manjaro-tools"
  
  msg_ok "Ambiente configurado com sucesso!"
  echo
  read -rp "Pressione ENTER para continuar..."
}

# =============================================================================
# OUTPUT DIRECTORY CONFIGURATION
# =============================================================================

configure_output_dir() {
  clear
  echo -e "${cyan}════════════════════════════════════════${reset}"
  echo -e "${white}   Configurar Diretório de Saída        ${reset}"
  echo -e "${cyan}════════════════════════════════════════${reset}"
  echo
  
  msg_info "Diretório atual: ${yellow}$OUTPUT_DIR${reset}"
  echo
  
  # Show available mount points
  msg_info "Partições disponíveis:"
  echo
  lsblk -o NAME,SIZE,MOUNTPOINT,FSTYPE | grep -E "^[a-z]|─" || true
  echo
  
  read -rp "Digite o novo diretório (ou ENTER para manter atual): " new_dir
  
  if [[ -n "$new_dir" ]]; then
    # Expand ~ if used
    new_dir="${new_dir/#\~/$HOME}"
    
    # Check if directory exists or can be created
    if [[ -d "$new_dir" ]] || mkdir -p "$new_dir" 2>/dev/null; then
      OUTPUT_DIR="$new_dir"
      save_config
      msg_ok "Diretório alterado para: $OUTPUT_DIR"
    else
      msg_warning "Não foi possível criar o diretório. Tente com sudo ou escolha outro."
    fi
  else
    msg_info "Mantendo diretório atual."
  fi
  
  echo
  read -rp "Pressione ENTER para continuar..."
}

# =============================================================================
# ISO BUILD
# =============================================================================

select_option() {
  local prompt="$1"
  shift
  local options=("$@")
  local selected=0
  local key
  
  while true; do
    echo -e "\n$prompt"
    for i in "${!options[@]}"; do
      if [[ $i -eq $selected ]]; then
        echo -e "  ${green}▶ ${options[$i]}${reset}"
      else
        echo -e "    ${options[$i]}"
      fi
    done
    
    read -rsn1 key
    case "$key" in
      A) ((selected--)) ;; # Up arrow
      B) ((selected++)) ;; # Down arrow
      '') break ;;
    esac
    
    # Wrap around
    ((selected < 0)) && selected=$((${#options[@]} - 1))
    ((selected >= ${#options[@]})) && selected=0
    
    # Clear previous output
    echo -en "\033[${#options[@]}A\033[0J"
  done
  
  echo "${options[$selected]}"
}

build_iso() {
  clear
  echo -e "${cyan}════════════════════════════════════════${reset}"
  echo -e "${white}          Gerar ISO                     ${reset}"
  echo -e "${cyan}════════════════════════════════════════${reset}"
  echo
  
  # Select distribution
  echo -e "${white}Escolha a distribuição:${reset}"
  echo "  1) bigcommunity"
  echo "  2) biglinux"
  read -rp "Opção [1]: " opt
  case "${opt:-1}" in
    1) DISTRO="bigcommunity" ;;
    2) DISTRO="biglinux" ;;
    *) DISTRO="bigcommunity" ;;
  esac
  
  # Select edition
  echo
  echo -e "${white}Escolha a edição:${reset}"
  echo "  1) gnome"
  echo "  2) kde"
  echo "  3) xfce"
  echo "  4) cinnamon"
  read -rp "Opção [1]: " opt
  case "${opt:-1}" in
    1) EDITION="gnome" ;;
    2) EDITION="kde" ;;
    3) EDITION="xfce" ;;
    4) EDITION="cinnamon" ;;
    *) EDITION="gnome" ;;
  esac
  
  # Select Manjaro branch
  echo
  echo -e "${white}Branch do Manjaro:${reset}"
  echo "  1) stable"
  echo "  2) testing"
  echo "  3) unstable"
  read -rp "Opção [1]: " opt
  case "${opt:-1}" in
    1) MANJARO_BRANCH="stable" ;;
    2) MANJARO_BRANCH="testing" ;;
    3) MANJARO_BRANCH="unstable" ;;
    *) MANJARO_BRANCH="stable" ;;
  esac
  
  # Select BigLinux branch
  echo
  echo -e "${white}Branch do BigLinux:${reset}"
  echo "  1) stable"
  echo "  2) testing"
  read -rp "Opção [1]: " opt
  case "${opt:-1}" in
    1) BIGLINUX_BRANCH="stable" ;;
    2) BIGLINUX_BRANCH="testing" ;;
    *) BIGLINUX_BRANCH="stable" ;;
  esac
  
  # Select BigCommunity branch (only for bigcommunity distro)
  if [[ "$DISTRO" == "bigcommunity" ]]; then
    echo
    echo -e "${white}Branch do BigCommunity:${reset}"
    echo "  1) stable"
    echo "  2) testing"
    read -rp "Opção [1]: " opt
    case "${opt:-1}" in
      1) BIGCOMMUNITY_BRANCH="stable" ;;
      2) BIGCOMMUNITY_BRANCH="testing" ;;
      *) BIGCOMMUNITY_BRANCH="stable" ;;
    esac
  else
    BIGCOMMUNITY_BRANCH=""
  fi
  
  # Select kernel
  echo
  echo -e "${white}Escolha o kernel:${reset}"
  echo "  1) lts (6.12)"
  echo "  2) latest (6.13)"
  read -rp "Opção [1]: " opt
  case "${opt:-1}" in
    1) KERNEL="lts" ;;
    2) KERNEL="latest" ;;
    *) KERNEL="lts" ;;
  esac
  
  # Save preferences
  save_config
  
  # Confirm
  echo
  echo -e "${cyan}════════════════════════════════════════${reset}"
  echo -e "${white}Resumo da configuração:${reset}"
  echo -e "  Distribuição:       ${yellow}$DISTRO${reset}"
  echo -e "  Edição:             ${yellow}$EDITION${reset}"
  echo -e "  Manjaro Branch:     ${yellow}$MANJARO_BRANCH${reset}"
  echo -e "  BigLinux Branch:    ${yellow}$BIGLINUX_BRANCH${reset}"
  if [[ "$DISTRO" == "bigcommunity" ]]; then
    echo -e "  BigCommunity Branch:${yellow}$BIGCOMMUNITY_BRANCH${reset}"
  fi
  echo -e "  Kernel:             ${yellow}$KERNEL${reset}"
  echo -e "  Saída:              ${yellow}$OUTPUT_DIR${reset}"
  echo -e "${cyan}════════════════════════════════════════${reset}"
  echo
  
  read -rp "Iniciar build? [S/n] " response
  response=${response:-S}
  
  if [[ ! "${response,,}" =~ ^(s|sim|y|yes)$ ]]; then
    msg_warning "Build cancelado."
    return
  fi
  
  # Set environment variables for build-iso.sh
  export USERNAME="$USER"
  export HOME_FOLDER="$HOME"
  export DISTRONAME="$DISTRO"
  export DISTRONAME_ISOPROFILES="$DISTRO"
  export EDITION="$EDITION"
  export MANJARO_BRANCH="$MANJARO_BRANCH"
  export BIGCOMMUNITY_BRANCH="$BIGCOMMUNITY_BRANCH"
  export BIGLINUX_BRANCH="$BIGLINUX_BRANCH"
  export KERNEL="$KERNEL"
  export WORK_PATH="$OUTPUT_DIR/work"
  export WORK_PATH_ISO_PROFILES="$OUTPUT_DIR/work/iso-profiles"
  export PROFILE_PATH="$OUTPUT_DIR/work/iso-profiles/$DISTRO"
  export PROFILE_PATH_EDITION="$OUTPUT_DIR/work/iso-profiles/$DISTRO/$EDITION"
  export ISO_PROFILES_REPO="https://github.com/big-comm/iso-profiles"
  export PATH_MANJARO_ISO_PROFILES="/usr/share/manjaro-tools/iso-profiles"
  export PATH_MANJARO_TOOLS="/usr/share/manjaro-tools"
  export VAR_CACHE_MANJARO_TOOLS="/var/cache/manjaro-tools"
  export VAR_CACHE_MANJARO_TOOLS_ISO="/var/cache/manjaro-tools/iso"
  export SCOPE="minimal"
  export OFFICE="false"
  export RELEASE_TAG="$(date +%Y.%m.%d)"
  export DEBUG="false"
  export LOCAL_BUILD="true"  # Skip cleaning system directories
  
  # Create work directory
  mkdir -p "$WORK_PATH"
  mkdir -p "$OUTPUT_DIR"
  
  msg "Iniciando build da ISO..."
  msg_info "Este processo pode demorar de 30 minutos a 2 horas"
  echo
  
  # Validate sudo and keep it alive during the build
  msg_info "Validando permissões sudo..."
  sudo -v
  # Keep sudo alive in background
  (while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null) &
  SUDO_KEEP_ALIVE_PID=$!
  
  # Run the main build script (using source to maintain environment)
  cd "$SCRIPT_DIR"
  set +e  # Disable exit on error temporarily
  source ./build-iso.sh
  local build_result=$?
  set -e
  
  if [[ $build_result -eq 0 ]]; then
    # Kill sudo keep-alive process
    kill $SUDO_KEEP_ALIVE_PID 2>/dev/null || true
    
    msg_ok "ISO gerada com sucesso!"
    
    # Move ISO to output directory
    local iso_cache_dir="/var/cache/manjaro-tools/iso/${DISTRO}/${EDITION}/${MANJARO_BRANCH}"
    if [[ -d "$iso_cache_dir" ]]; then
      msg_info "Movendo ISO para $OUTPUT_DIR..."
      sudo mv "$iso_cache_dir"/*.iso "$OUTPUT_DIR/" 2>/dev/null || true
      sudo mv "$iso_cache_dir"/*.sha* "$OUTPUT_DIR/" 2>/dev/null || true
      sudo mv "$iso_cache_dir"/*.torrent "$OUTPUT_DIR/" 2>/dev/null || true
      sudo chown "$USER:$USER" "$OUTPUT_DIR"/*.iso 2>/dev/null || true
      sudo chown "$USER:$USER" "$OUTPUT_DIR"/*.sha* 2>/dev/null || true
      sudo chown "$USER:$USER" "$OUTPUT_DIR"/*.torrent 2>/dev/null || true
      msg_ok "ISO disponível em: $OUTPUT_DIR"
      ls -lh "$OUTPUT_DIR"/*.iso 2>/dev/null || true
    else
      msg_warning "ISO gerada mas não encontrada em $iso_cache_dir"
      msg_info "Verifique em /var/cache/manjaro-tools/iso/"
    fi
    
    # Offer cleanup
    echo
    read -rp "Deseja limpar arquivos temporários? [s/N] " cleanup_response
    if [[ "${cleanup_response,,}" =~ ^(s|sim|y|yes)$ ]]; then
      cleanup_build
    fi
  else
    # Kill sudo keep-alive process
    kill $SUDO_KEEP_ALIVE_PID 2>/dev/null || true
    msg_warning "Falha ao gerar ISO. Verifique os logs acima."
  fi
  
  echo
  read -rp "Pressione ENTER para continuar..."
}

# Cleanup function
cleanup_build() {
  msg "Limpando arquivos temporários..."
  
  # Clean manjaro-tools cache
  if [[ -d "/var/cache/manjaro-tools" ]]; then
    msg_info "Limpando cache do manjaro-tools..."
    sudo rm -rf /var/cache/manjaro-tools/iso/* 2>/dev/null || true
    sudo rm -rf /var/lib/manjaro-tools/buildiso/* 2>/dev/null || true
  fi
  
  # Clean work directory (except ISO output)
  if [[ -d "$OUTPUT_DIR/work" ]]; then
    msg_info "Limpando diretório de trabalho..."
    rm -rf "$OUTPUT_DIR/work" 2>/dev/null || true
  fi
  
  msg_ok "Limpeza concluída!"
}

# =============================================================================
# MAIN MENU
# =============================================================================

show_menu() {
  while true; do
    clear
    echo -e "${cyan}╔══════════════════════════════════════╗${reset}"
    echo -e "${cyan}║${reset}     ${white}BigCommunity ISO Builder${reset}         ${cyan}║${reset}"
    echo -e "${cyan}╠══════════════════════════════════════╣${reset}"
    echo -e "${cyan}║${reset} 1. Configurar ambiente (primeira vez)${cyan}║${reset}"
    echo -e "${cyan}║${reset} 2. Configurar diretório de saída     ${cyan}║${reset}"
    echo -e "${cyan}║${reset} 3. Gerar ISO                         ${cyan}║${reset}"
    echo -e "${cyan}║${reset} 4. Limpar cache de compilação        ${cyan}║${reset}"
    echo -e "${cyan}║${reset} 0. Sair                              ${cyan}║${reset}"
    echo -e "${cyan}╚══════════════════════════════════════╝${reset}"
    echo
    echo -e "${white}Diretório atual:${reset} ${yellow}$OUTPUT_DIR${reset}"
    echo
    read -rp "Escolha uma opção: " choice
    
    case "$choice" in
      1) setup_environment ;;
      2) configure_output_dir ;;
      3) build_iso ;;
      4) 
        cleanup_build
        read -rp "Pressione ENTER para continuar..."
        ;;
      0) 
        msg_ok "Até logo!"
        exit 0
        ;;
      *)
        msg_warning "Opção inválida!"
        sleep 1
        ;;
    esac
  done
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  # Load configuration
  load_config
  
  # Show menu
  show_menu
}

main "$@"
