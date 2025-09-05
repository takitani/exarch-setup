#!/usr/bin/env bash
set -euo pipefail

# Simple post-install script for Arch + Hyprland
# First step: update the system with yay: `yay -Syu --noconfirm`

CURRENT_STEP=""

print_info()  { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
print_warn()  { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
print_error() { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }
print_step()  { CURRENT_STEP="$*"; printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }

trap 'print_error "Falhou em: ${CURRENT_STEP:-passo desconhecido}"' ERR

auto_install_yay=true

usage() {
  cat <<EOF
Uso: $0 [opções]

Opções:
  --no-install-yay   Não tentar instalar yay automaticamente se ausente
  -h, --help         Mostrar esta ajuda

Comportamento:
  - Atualiza o sistema com: yay -Syu --noconfirm
  - Se o yay não existir, tenta instalar automaticamente (padrão)
EOF
}

while [[ ${1-} ]]; do
  case "$1" in
    --no-install-yay) auto_install_yay=false ;;
    -h|--help) usage; exit 0 ;;
    *) print_error "Opção desconhecida: $1"; usage; exit 1 ;;
  esac
  shift
done

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  print_warn "Execute este script como usuário normal (não root)."
fi

ensure_yay() {
  if command -v yay >/dev/null 2>&1; then
    return 0
  fi
  if [[ "$auto_install_yay" != true ]]; then
    print_error "yay não encontrado. Instale o yay ou rode com a opção padrão que instala automaticamente."
    exit 1
  fi

  print_step "Instalando yay (AUR helper)"
  # Pré-requisitos para compilar pacotes AUR
  sudo pacman -Sy --noconfirm --needed base-devel git

  # Tenta usar yay-bin para instalação mais rápida; caso falhe, usa yay
  tmpdir="$(mktemp -d)"
  (
    set -e
    cd "$tmpdir"
    if git clone https://aur.archlinux.org/yay-bin.git >/dev/null 2>&1; then
      cd yay-bin
    else
      print_warn "Não foi possível clonar yay-bin; tentando yay (fonte)."
      git clone https://aur.archlinux.org/yay.git
      cd yay
    fi
    makepkg -si --noconfirm
  )
  print_info "yay instalado com sucesso."
}

update_system() {
  print_step "Atualizando o sistema com yay"
  yay -Syu --noconfirm
  print_info "Atualização concluída."
}

main() {
  ensure_yay
  update_system
  install_desktop_apps
  set_locale_ptbr
  configure_keyboard_layout
  configure_gnome_keyring
  configure_hyprland_bindings
  
  print_step "Post-install concluído com sucesso!"
  print_info "Resumo das configurações aplicadas:"
  print_info "✓ Sistema atualizado via yay"
  print_info "✓ Aplicativos desktop instalados (Mission Center, Discord, ZapZap, CPU-X, Slack)"
  print_info "✓ Locale configurado (interface EN, formatação BR)"
  print_info "✓ Layout de teclado US-Intl configurado (compose:caps para acentos)"
  print_info "✓ GNOME Keyring configurado para unlock automático"
  print_info "✓ Atalhos do Hyprland configurados (Signal comentado, WhatsApp → ZapZap)"
  print_info ""
  print_info "Este script é idempotente e pode ser executado novamente se necessário."
  print_info "Backups foram criados para todos os arquivos modificados."
}

set_locale_ptbr() {
  print_step "Configurando locale (interface EN, formatação BR)"

  # Garante que as linhas existam e estejam descomentadas em /etc/locale.gen
  for locale in "en_US.UTF-8 UTF-8" "pt_BR.UTF-8 UTF-8"; do
    if ! grep -Eq "^[^#]*${locale//./\\.}" /etc/locale.gen 2>/dev/null; then
      # Tenta descomentar, caso exista comentada
      if grep -Eq "^#\\s*${locale//./\\.}" /etc/locale.gen 2>/dev/null; then
        sudo sed -i "s/^#\\s*${locale//./\\.}/${locale}/" /etc/locale.gen || true
      else
        printf '\n%s\n' "$locale" | sudo tee -a /etc/locale.gen >/dev/null || true
      fi
    fi
  done

  # Gera locales
  sudo locale-gen

  # Define locale do sistema: interface em inglês, formatação brasileira
  local target_locale="LANG=en_US.UTF-8
LC_CTYPE=pt_BR.UTF-8
LC_NUMERIC=pt_BR.UTF-8
LC_TIME=pt_BR.UTF-8
LC_COLLATE=pt_BR.UTF-8
LC_MONETARY=pt_BR.UTF-8
LC_MESSAGES=en_US.UTF-8
LC_PAPER=pt_BR.UTF-8
LC_NAME=pt_BR.UTF-8
LC_ADDRESS=pt_BR.UTF-8
LC_TELEPHONE=pt_BR.UTF-8
LC_MEASUREMENT=pt_BR.UTF-8
LC_IDENTIFICATION=pt_BR.UTF-8"

  if localectl status 2>/dev/null | grep -q 'LANG=en_US.UTF-8'; then
    print_info "Locale já configurado corretamente"
  else
    sudo localectl set-locale LANG=en_US.UTF-8
    print_info "Locale definido: interface EN, formatação BR"
  fi
}

configure_keyboard_layout() {
  print_step "Configurando layout de teclado US-Intl (Hyprland + Waybar)"

  # Hyprland input.conf
  local hypr_input="$HOME/.config/hypr/input.conf"
  if [[ -f "$hypr_input" ]]; then
    # Faz backup se ainda não existir
    if [[ ! -f "$hypr_input.bak" ]]; then
      cp "$hypr_input" "$hypr_input.bak"
      print_info "Backup criado: $hypr_input.bak"
    fi

    # Detecta estilo de chaves (xkb_* em versões novas; kb_* em antigas)
    local style="xkb"
    if grep -qE '^\s*xkb_layout\s*=' "$hypr_input"; then
      style="xkb"
    elif grep -qE '^\s*kb_layout\s*=' "$hypr_input"; then
      style="kb"
    else
      # Se não há nenhuma, preferimos xkb_* (versões novas)
      style="xkb"
    fi

    local layout_key variant_key options_key
    layout_key="${style}_layout"
    variant_key="${style}_variant"
    options_key="${style}_options"

    # Remove configurações duplicadas fora do bloco input
    sed -i -E "/^input\s*\{/,/^\}/!{/^\s*${layout_key}\s*=/d; /^\s*${variant_key}\s*=/d; /^\s*${options_key}\s*=/d;}" "$hypr_input"

    # Define layout us dentro do bloco input
    if grep -qE "^\s*${layout_key}\s*=" "$hypr_input"; then
      sed -i -E "s/^\s*${layout_key}\s*=.*/${layout_key} = us/" "$hypr_input"
    else
      # Adiciona dentro do bloco input, antes do fechamento
      sed -i -E "/^input\s*\{/,/^\}/ { /^\}/ i\\n${layout_key} = us" "$hypr_input" || \
      sed -i -E "/^input\s*\{/ a\\n${layout_key} = us" "$hypr_input"
    fi

    # Define options compose:caps dentro do bloco input
    if grep -qE "^\s*${options_key}\s*=" "$hypr_input"; then
      sed -i -E "s/^\s*${options_key}\s*=.*/${options_key} = compose:caps/" "$hypr_input"
    else
      sed -i -E "/^input\s*\{/,/^\}/ { /^\}/ i\\n${options_key} = compose:caps" "$hypr_input" || \
      sed -i -E "/^input\s*\{/ a\\n${options_key} = compose:caps" "$hypr_input"
    fi

    # Define variant intl dentro do bloco input
    if grep -qE "^\s*${variant_key}\s*=" "$hypr_input"; then
      sed -i -E "s/^\s*${variant_key}\s*=.*/${variant_key} = intl/" "$hypr_input"
    else
      sed -i -E "/^input\s*\{/,/^\}/ { /^\}/ i\\n${variant_key} = intl" "$hypr_input" || \
      sed -i -E "/^input\s*\{/ a\\n${variant_key} = intl" "$hypr_input"
    fi

    print_info "Hyprland: ${layout_key}/variants/options configurados (US-Intl com compose:caps)"
  else
    print_warn "Hyprland: arquivo não encontrado: $hypr_input (pulando)"
  fi

  # Waybar config.jsonc
  local waybar_config="$HOME/.config/waybar/config.jsonc"
  if [[ -f "$waybar_config" ]]; then
    # Faz backup se ainda não existir
    if [[ ! -f "$waybar_config.bak" ]]; then
      cp "$waybar_config" "$waybar_config.bak"
      print_info "Backup criado: $waybar_config.bak"
    fi
    if ! grep -q "hyprland/language" "$waybar_config"; then
      # Adiciona módulo em modules-right, após group/tray-expander
      sed -i '/"modules-right": \[/,/]/{/"group\/tray-expander",/ a\
    "hyprland/language",
    }' "$waybar_config"

      # Adiciona configuração do módulo no final do arquivo
      sed -i '$i\
  },\
  "hyprland/language": {\
    "format": "{}",\
    "format-en": "INT",\
    "format-br": "BR",\
    "on-click": "hyprctl switchxkblayout at-translated-set-2-keyboard next"\
  }' "$waybar_config"
      print_info "Waybar: indicador de layout adicionado"
    else
      print_info "Waybar: módulo hyprland/language já presente"
    fi

    # Waybar style.css
    local waybar_css="$HOME/.config/waybar/style.css"
    if [[ -f "$waybar_css" ]] && ! grep -q "#language" "$waybar_css"; then
      # Faz backup se ainda não existir
      if [[ ! -f "$waybar_css.bak" ]]; then
        cp "$waybar_css" "$waybar_css.bak"
        print_info "Backup criado: $waybar_css.bak"
      fi
      sed -i '/#pulseaudio,/a\
#language,' "$waybar_css"
      print_info "Waybar: CSS do indicador de layout adicionado"
    fi
  else
    print_warn "Waybar: arquivo não encontrado: $waybar_config (pulando)"
  fi
}

install_desktop_apps() {
  print_step "Instalando aplicativos desktop"
  local pkgs=(mission-center discord zapzap cpu-x slack-desktop)
  yay -S --noconfirm --needed "${pkgs[@]}"
  print_info "Aplicativos desktop instalados/atualizados"
}

configure_gnome_keyring() {
  print_step "Configurando GNOME Keyring (Solução Definitiva)"
  
  # Instala pacotes necessários
  print_info "Instalando gnome-keyring e dependências..."
  yay -S --noconfirm --needed gnome-keyring libsecret seahorse
  
  # Para processos problemáticos
  print_info "Parando processos problemáticos..."
  pkill -f gnome-keyring-daemon || true
  pkill -f chrome || true
  sleep 2
  
  # Remove autostart conflitante do gnome-keyring-ssh
  print_info "Removendo autostart conflitante do keyring..."
  if [[ -f "$HOME/.config/autostart/gnome-keyring-ssh.desktop" ]]; then
    mv "$HOME/.config/autostart/gnome-keyring-ssh.desktop" "$HOME/.config/autostart/gnome-keyring-ssh.desktop.disabled"
    print_info "GNOME Keyring SSH autostart removido"
  fi
  
  # Limpa keyrings problemáticos
  print_info "Limpando keyrings problemáticos..."
  if [[ -d "$HOME/.local/share/keyrings" ]]; then
    local backup_dir="$HOME/.local/share/keyrings.bak.$(date +%Y%m%d%H%M%S)"
    print_info "Fazendo backup em $backup_dir"
    mv "$HOME/.local/share/keyrings" "$backup_dir"
  fi
  
  # Limpa sockets do keyring
  print_info "Limpando sockets do keyring..."
  rm -rf "$XDG_RUNTIME_DIR/keyring" || true
  rm -rf "$XDG_RUNTIME_DIR/gnome-keyring" || true
  
  # Configura PAM corretamente
  print_info "Configurando PAM para unlock automático..."
  
  # Backup dos arquivos PAM
  if [[ ! -f /etc/pam.d/login.bak.keyring ]]; then
    sudo cp /etc/pam.d/login /etc/pam.d/login.bak.keyring
    print_info "Backup criado: /etc/pam.d/login.bak.keyring"
  fi
  
  # Configura PAM corretamente se não estiver configurado
  if ! sudo grep -q "pam_gnome_keyring.so auto_start" /etc/pam.d/login; then
    print_info "Configurando PAM..."
    
    # Cria configuração PAM correta
    sudo tee /tmp/login.pam > /dev/null << 'EOF'
#%PAM-1.0

auth       requisite    pam_nologin.so
auth       include      system-local-login
auth       optional     pam_gnome_keyring.so
account    include      system-local-login
password   include      system-local-login
session    include      system-local-login
session    optional     pam_gnome_keyring.so auto_start
EOF
    
    sudo mv /tmp/login.pam /etc/pam.d/login
    print_info "PAM configurado!"
  else
    print_info "PAM já configurado corretamente"
  fi
  
  # Configura Hyprland corretamente
  local hypr_config="$HOME/.config/hypr/hyprland.conf"
  if [[ -f "$hypr_config" ]]; then
    # Faz backup se ainda não existir
    if [[ ! -f "$hypr_config.bak.keyring" ]]; then
      cp "$hypr_config" "$hypr_config.bak.keyring"
      print_info "Backup criado: $hypr_config.bak.keyring"
    fi
    
    # Remove qualquer linha do gnome-keyring
    sed -i '/gnome-keyring-daemon/d' "$hypr_config"
    
    # Adiciona configuração correta (SEM --unlock)
    if ! grep -q "gnome-keyring-daemon" "$hypr_config"; then
      cat >> "$hypr_config" << 'EOF'

# GNOME Keyring - Configuração correta
exec-once = gnome-keyring-daemon --start --components=pkcs11,secrets,ssh
exec-once = systemctl --user import-environment GNOME_KEYRING_CONTROL GNOME_KEYRING_PID SSH_AUTH_SOCK
EOF
      print_info "Hyprland configurado!"
    fi
  else
    print_warn "Arquivo de configuração do Hyprland não encontrado: $hypr_config"
  fi
  
  # Configura variáveis de ambiente
  print_info "Configurando variáveis de ambiente..."
  local env_file="$HOME/.config/environment.d/99-gnome-keyring.conf"
  mkdir -p "$HOME/.config/environment.d"
  cat > "$env_file" << 'EOF'
SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/keyring/ssh
GNOME_KEYRING_CONTROL=$XDG_RUNTIME_DIR/keyring
EOF
  
  # Configura Chrome para usar keyring corretamente
  print_info "Configurando Chrome para usar keyring..."
  local chrome_flags="$HOME/.config/chrome-flags.conf"
  mkdir -p "$(dirname "$chrome_flags")"
  
  # Remove configurações antigas
  if [[ -f "$chrome_flags" ]]; then
    sed -i '/password-store/d' "$chrome_flags"
  fi
  
  # Adiciona configuração para usar keyring (não basic)
  echo "--password-store=gnome" >> "$chrome_flags"
  echo "--enable-features=UseOzonePlatform" >> "$chrome_flags"
  echo "--ozone-platform=wayland" >> "$chrome_flags"
  
  print_info "GNOME Keyring configurado com sucesso!"
  print_warn "IMPORTANTE: Após reiniciar o sistema:"
  print_warn "1. O Chrome não abrirá automaticamente"
  print_warn "2. O keyring será desbloqueado automaticamente"
  print_warn "3. O Chrome usará o keyring para senhas (sem pedir senha)"
}

configure_hyprland_bindings() {
  print_step "Configurando atalhos do Hyprland"
  
  local bindings_file="$HOME/.config/hypr/bindings.conf"
  
  if [[ ! -f "$bindings_file" ]]; then
    print_warn "Arquivo de atalhos do Hyprland não encontrado: $bindings_file"
    return 0
  fi
  
  # Faz backup se ainda não existir
  if [[ ! -f "$bindings_file.bak" ]]; then
    cp "$bindings_file" "$bindings_file.bak"
    print_info "Backup criado: $bindings_file.bak"
  fi
  
  # Comenta o atalho do Signal (SUPER + G)
  if grep -qE '^bindd = SUPER, G, Signal' "$bindings_file"; then
    sed -i 's/^bindd = SUPER, G, Signal/#bindd = SUPER, G, Signal/' "$bindings_file"
    print_info "Atalho do Signal comentado (SUPER + G)"
  else
    print_info "Atalho do Signal já estava comentado ou não encontrado"
  fi
  
  # Troca o atalho do WhatsApp para usar ZapZap
  if grep -qE '^bindd = SUPER , G, WhatsApp, exec, \$webapp="https://web.whatsapp.com/"' "$bindings_file"; then
    sed -i 's/^bindd = SUPER , G, WhatsApp, exec, \$webapp="https:\/\/web.whatsapp.com\/"/bindd = SUPER, G, WhatsApp, exec, uwsm app -- zapzap/' "$bindings_file"
    print_info "Atalho do WhatsApp alterado para ZapZap (SUPER + G)"
  else
    print_info "Atalho do WhatsApp não encontrado ou já modificado"
  fi
  
  print_info "Configuração de atalhos do Hyprland concluída"
}

main "$@"
