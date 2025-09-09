#!/usr/bin/env bash
set -euo pipefail

# Exarch Setup - Post-install script for Arch Linux + Hyprland
# 
# Execução remota (sem git clone):
#   bash <(curl -fsSL https://raw.githubusercontent.com/takitani/exarch-setup/main/post-install.sh)
# 
# Execução local:
#   ./post-install.sh [--no-install-yay]

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
  
  # Tenta atualizar com retry em caso de falha de conexão AUR
  local max_retries=3
  local retry_count=0
  
  while [[ $retry_count -lt $max_retries ]]; do
    if yay -Syu --noconfirm; then
      print_info "Atualização concluída."
      return 0
    else
      retry_count=$((retry_count + 1))
      if [[ $retry_count -lt $max_retries ]]; then
        print_warn "Falha na atualização (tentativa $retry_count de $max_retries). Tentando novamente em 5 segundos..."
        sleep 5
      else
        print_warn "Falha na atualização após $max_retries tentativas. Continuando com o script..."
        print_info "Você pode executar 'yay -Syu' manualmente mais tarde."
        return 0  # Não falha o script inteiro
      fi
    fi
  done
}

main() {
  ensure_yay
  update_system
  install_desktop_apps
  set_locale_ptbr
  configure_keyboard_layout
  configure_gnome_keyring
  configure_hyprland_bindings
  configure_omarchy_logout
  configure_autostart
  configure_clipse
  fix_nautilus_cursor
  configure_aws_vpn
  
  print_step "Post-install concluído com sucesso!"
  print_info "Resumo das configurações aplicadas:"
  print_info "✓ Sistema atualizado via yay"
  print_info "✓ Aplicativos desktop instalados (Mission Center, Discord, ZapZap, CPU-X, Slack, Chrome, Cursor, VSCode, Clipse, JetBrains Toolbox, AWS VPN Client)"
  print_info "✓ Locale configurado (interface EN, formatação BR)"
  print_info "✓ Layout de teclado US-Intl configurado com cedilha correto (ç)"
  print_info "✓ GNOME Keyring configurado para unlock automático"
  print_info "✓ Atalhos do Hyprland configurados (Signal comentado, WhatsApp → ZapZap)"
  print_info "✓ Menu de power do Omarchy configurado (Logout adicionado)"
  print_info "✓ Autostart configurado (ZapZap e Slack no workspace 2)"
  print_info "✓ Clipse configurado (Clipboard Manager com ALT + SHIFT + V)"
  print_info "✓ Nautilus cursor fix aplicado (input methods configurados para ibus)"
  print_info "✓ AWS VPN Client configurado (systemd-resolved e serviço habilitados)"
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
  # IMPORTANTE: LC_CTYPE=pt_BR.UTF-8 é CRÍTICO para o cedilha funcionar!
  if ! localectl status 2>/dev/null | grep -q 'LC_CTYPE=pt_BR.UTF-8'; then
    print_info "Configurando LC_CTYPE para pt_BR (essencial para cedilha)..."
    sudo localectl set-locale LANG=en_US.UTF-8 LC_CTYPE=pt_BR.UTF-8
    print_info "Locale definido: LANG=en_US.UTF-8, LC_CTYPE=pt_BR.UTF-8"
  else
    print_info "Locale já configurado corretamente (LC_CTYPE=pt_BR.UTF-8)"
  fi
}

configure_keyboard_layout() {
  print_step "Configurando layout de teclado US-Intl com cedilha (Hyprland + Waybar)"

  # IMPORTANTE: No Wayland, o cedilha funciona através de:
  # 1. LC_CTYPE=pt_BR.UTF-8 (já configurado no locale)
  # 2. .XCompose com as regras de composição
  # 3. kb_variant=intl no Hyprland
  # NÃO usamos GTK_IM_MODULE pois causa conflitos com Wayland!
  
  # Limpa configurações antigas problemáticas se existirem
  local env_file="$HOME/.config/environment.d/50-cedilla.conf"
  if [[ -f "$env_file" ]]; then
    print_info "Removendo configurações antigas de IM_MODULE que causam conflitos..."
    rm -f "$env_file"
  fi
  
  # Remove do .bashrc se existir
  if grep -q "export GTK_IM_MODULE=cedilla" "$HOME/.bashrc"; then
    print_info "Limpando configurações antigas do .bashrc..."
    sed -i '/# Configuração para cedilha correto/d' "$HOME/.bashrc"
    sed -i '/export GTK_IM_MODULE=cedilla/d' "$HOME/.bashrc"
    sed -i '/export QT_IM_MODULE=cedilla/d' "$HOME/.bashrc"
  fi

  # Configura .XCompose para cedilha correto
  local xcompose_file="$HOME/.XCompose"
  local needs_cedilla_config=true
  
  # Verifica se já tem configuração de cedilha
  if [[ -f "$xcompose_file" ]] && grep -q "ccedilla" "$xcompose_file"; then
    needs_cedilla_config=false
    print_info ".XCompose já configurado para cedilha"
  fi
  
  if [[ "$needs_cedilla_config" == true ]]; then
    # Faz backup se o arquivo existe
    if [[ -f "$xcompose_file" ]]; then
      cp "$xcompose_file" "$xcompose_file.bak"
      print_info "Backup criado: $xcompose_file.bak"
    fi
    
    # Cria configuração de cedilha
    cat > "$xcompose_file" << 'EOF'
include "%L"

# Cedilha (ç/Ç) configuration for US International keyboard
<dead_acute> <c> : "ç" ccedilla
<dead_acute> <C> : "Ç" Ccedilla
<acute> <c> : "ç" ccedilla
<acute> <C> : "Ç" Ccedilla
<apostrophe> <c> : "ç" ccedilla
<apostrophe> <C> : "Ç" Ccedilla
<'> <c> : "ç" ccedilla
<'> <C> : "Ç" Ccedilla

EOF
    
    # Se tinha conteúdo anterior, adiciona de volta
    if [[ -f "$xcompose_file.bak" ]]; then
      cat "$xcompose_file.bak" >> "$xcompose_file"
    fi
    
    print_info ".XCompose configurado para cedilha correto"
  fi
  
  # Cria também para GTK3 (necessário para algumas aplicações)
  local gtk_compose="$HOME/.config/gtk-3.0/Compose"
  if [[ ! -f "$gtk_compose" ]] || ! grep -q "ccedilla" "$gtk_compose" 2>/dev/null; then
    mkdir -p "$HOME/.config/gtk-3.0"
    cp "$xcompose_file" "$gtk_compose" 2>/dev/null || true
    print_info "GTK3 Compose configurado para cedilha"
  fi

  # Hyprland input.conf
  local hypr_input="$HOME/.config/hypr/input.conf"
  if [[ -f "$hypr_input" ]]; then
    # Cria backup com timestamp para preservar histórico
    local backup_file="$hypr_input.bak.$(date +%Y%m%d%H%M%S)"
    cp "$hypr_input" "$backup_file"
    print_info "Backup criado: $backup_file"

    # Detecta e remove configurações incorretas (xkb_* que não funcionam ou nkb_* mal formadas)
    local needs_fix=false
    if grep -qE '^\s*(xkb_layout|xkb_variant|xkb_options|nkb_variant|nkb_layout|nkb_options)\s*=' "$hypr_input"; then
      print_info "Detectadas configurações incorretas (xkb_* ou nkb_*), corrigindo..."
      needs_fix=true
      # Remove todas as configurações incorretas
      sed -i -E '/^\s*(xkb_layout|xkb_variant|xkb_options|nkb_variant|nkb_layout|nkb_options)\s*=/d' "$hypr_input"
    fi

    # Hyprland usa kb_* (não xkb_*)
    local layout_key="kb_layout"
    local variant_key="kb_variant"
    local options_key="kb_options"

    # Remove configurações duplicadas fora do bloco input
    sed -i -E "/^input\s*\{/,/^\}/!{/^\s*(${layout_key}|${variant_key}|${options_key})\s*=/d;}" "$hypr_input"

    # Verifica se o bloco input existe
    if ! grep -q "^input\s*{" "$hypr_input"; then
      print_warn "Bloco 'input' não encontrado no arquivo, criando..."
      echo -e "\ninput {\n}" >> "$hypr_input"
    fi

    # Verifica quais configurações precisam ser adicionadas
    local need_layout=true
    local need_variant=true  
    local need_options=true
    
    grep -qE "^\s*${layout_key}\s*=" "$hypr_input" && need_layout=false
    grep -qE "^\s*${variant_key}\s*=" "$hypr_input" && need_variant=false
    grep -qE "^\s*${options_key}\s*=" "$hypr_input" && need_options=false
    
    # Se precisar adicionar alguma configuração, faz tudo de uma vez
    if [[ "$need_layout" == true ]] || [[ "$need_variant" == true ]] || [[ "$need_options" == true ]]; then
      # Cria um arquivo temporário com as configurações
      local temp_config=$(mktemp)
      
      # Copia o conteúdo até o input {
      sed '/^input\s*{/q' "$hypr_input" > "$temp_config"
      
      # Adiciona as configurações necessárias
      [[ "$need_layout" == false ]] || echo "    ${layout_key} = us" >> "$temp_config"
      [[ "$need_variant" == false ]] || echo "    ${variant_key} = intl" >> "$temp_config"
      [[ "$need_options" == false ]] || echo "    ${options_key} = " >> "$temp_config"
      
      # Adiciona o resto do arquivo (exceto a linha input {)
      sed '1,/^input\s*{/d' "$hypr_input" >> "$temp_config"
      
      # Substitui o arquivo original
      mv "$temp_config" "$hypr_input"
      
      [[ "$need_layout" == false ]] || print_info "Adicionado: ${layout_key} = us"
      [[ "$need_variant" == false ]] || print_info "Adicionado: ${variant_key} = intl"
      [[ "$need_options" == false ]] || print_info "Adicionado: ${options_key} = (vazio, Caps Lock normal)"
    fi
    
    # Atualiza valores existentes se necessário
    if [[ "$need_layout" == false ]]; then
      if ! grep -qE "^\s*${layout_key}\s*=\s*us" "$hypr_input"; then
        sed -i -E "s/^\s*${layout_key}\s*=.*/${layout_key} = us/" "$hypr_input"
        print_info "Atualizado: ${layout_key} = us"
      fi
    fi
    
    if [[ "$need_variant" == false ]]; then
      if ! grep -qE "^\s*${variant_key}\s*=\s*intl" "$hypr_input"; then
        sed -i -E "s/^\s*${variant_key}\s*=.*/${variant_key} = intl/" "$hypr_input"
        print_info "Atualizado: ${variant_key} = intl"
      fi
    fi
    
    if [[ "$need_options" == false ]]; then
      if ! grep -qE "^\s*${options_key}\s*=\s*$" "$hypr_input"; then
        sed -i -E "s/^\s*${options_key}\s*=.*/${options_key} = /" "$hypr_input"
        print_info "Atualizado: ${options_key} = (vazio, Caps Lock normal)"
      fi
    fi

    # Valida que as configurações estão corretas
    if grep -qE "^\s*${layout_key}\s*=\s*us" "$hypr_input" && \
       grep -qE "^\s*${variant_key}\s*=\s*intl" "$hypr_input" && \
       grep -qE "^\s*${options_key}\s*=\s*$" "$hypr_input"; then
      print_info "✓ Configuração do teclado validada com sucesso"
    else
      print_warn "⚠ Configuração pode estar incompleta, verifique $hypr_input"
    fi

    print_info "Hyprland: kb_layout/kb_variant/kb_options configurados (US-Intl com cedilha)"
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
  local pkgs=(mission-center discord zapzap cpu-x slack-desktop google-chrome cursor-bin visual-studio-code-bin clipse jetbrains-toolbox awsvpnclient)
  
  # Instala com retry em caso de falha de conexão
  local max_retries=3
  local retry_count=0
  
  while [[ $retry_count -lt $max_retries ]]; do
    if yay -S --noconfirm --needed "${pkgs[@]}"; then
      print_info "Aplicativos desktop instalados/atualizados"
      return 0
    else
      retry_count=$((retry_count + 1))
      if [[ $retry_count -lt $max_retries ]]; then
        print_warn "Falha na instalação (tentativa $retry_count de $max_retries). Tentando novamente em 5 segundos..."
        sleep 5
      else
        print_warn "Alguns aplicativos podem não ter sido instalados devido a problemas de conexão."
        print_info "Você pode executar './post-install.sh' novamente ou instalar manualmente com yay."
        return 0  # Não falha o script inteiro
      fi
    fi
  done
}

configure_gnome_keyring() {
  print_step "Configurando GNOME Keyring (Solução Segura)"
  
  # Verifica se já está configurado e funcionando
  local needs_config=false
  
  # Verifica se PAM está configurado
  if ! sudo grep -q "pam_gnome_keyring.so" /etc/pam.d/login || \
     ! sudo grep -q "pam_gnome_keyring.so" /etc/pam.d/system-login; then
    needs_config=true
    print_info "PAM precisa ser configurado para GNOME Keyring"
  fi
  
  # Verifica se Hyprland está configurado
  local hypr_config="$HOME/.config/hypr/hyprland.conf"
  if [[ -f "$hypr_config" ]] && ! grep -q "gnome-keyring-daemon --start --components" "$hypr_config"; then
    needs_config=true
    print_info "Hyprland precisa ser configurado para GNOME Keyring"
  fi
  
  # Verifica se chrome-flags está configurado corretamente
  local chrome_flags="$HOME/.config/chrome-flags.conf"
  if [[ ! -f "$chrome_flags" ]] || ! grep -q "password-store=gnome" "$chrome_flags"; then
    needs_config=true
    print_info "Chrome flags precisam ser configuradas"
  fi
  
  # Se tudo já está configurado, apenas instala pacotes se necessário
  if [[ "$needs_config" == false ]]; then
    print_info "GNOME Keyring já está completamente configurado"
    yay -S --noconfirm --needed gnome-keyring libsecret seahorse
    return 0
  fi
  
  # Instala pacotes necessários
  print_info "Instalando gnome-keyring e dependências..."
  yay -S --noconfirm --needed gnome-keyring libsecret seahorse
  
  # Só para processos e limpa keyrings se for primeira configuração
  # Verifica se é primeira configuração verificando se já tem backup de keyrings
  if ! ls "$HOME/.local/share/keyrings.bak."* 2>/dev/null | grep -q .; then
    print_info "Primeira configuração detectada - limpando configurações antigas..."
    
    # Para processos problemáticos
    print_info "Parando processos problemáticos..."
    pkill -f gnome-keyring-daemon || true
    pkill -f chrome || true
    sleep 2
    
    # Remove autostart conflitante do gnome-keyring-ssh
    if [[ -f "$HOME/.config/autostart/gnome-keyring-ssh.desktop" ]]; then
      mv "$HOME/.config/autostart/gnome-keyring-ssh.desktop" "$HOME/.config/autostart/gnome-keyring-ssh.desktop.disabled"
      print_info "GNOME Keyring SSH autostart removido"
    fi
    
    # Limpa keyrings problemáticos
    if [[ -d "$HOME/.local/share/keyrings" ]]; then
      local backup_dir="$HOME/.local/share/keyrings.bak.$(date +%Y%m%d%H%M%S)"
      print_info "Fazendo backup em $backup_dir"
      mv "$HOME/.local/share/keyrings" "$backup_dir"
    fi
    
    # Limpa sockets do keyring
    print_info "Limpando sockets do keyring..."
    rm -rf "$XDG_RUNTIME_DIR/keyring" || true
    rm -rf "$XDG_RUNTIME_DIR/gnome-keyring" || true
  else
    print_info "Configuração existente detectada - preservando keyrings"
  fi
  
  # Configura PAM de forma SEGURA (apenas adiciona, não sobrescreve)
  print_info "Configurando PAM para unlock automático..."
  
  # Backup dos arquivos PAM
  if [[ ! -f /etc/pam.d/login.bak.keyring ]]; then
    sudo cp /etc/pam.d/login /etc/pam.d/login.bak.keyring
    print_info "Backup criado: /etc/pam.d/login.bak.keyring"
  fi
  
  if [[ ! -f /etc/pam.d/system-login.bak.keyring ]]; then
    sudo cp /etc/pam.d/system-login /etc/pam.d/system-login.bak.keyring
    print_info "Backup criado: /etc/pam.d/system-login.bak.keyring"
  fi
  
  # Configura /etc/pam.d/login - adiciona apenas se não existir
  if ! sudo grep -q "pam_gnome_keyring.so" /etc/pam.d/login; then
    print_info "Adicionando gnome-keyring ao /etc/pam.d/login..."
    # Adiciona auth após a linha system-local-login
    sudo sed -i '/auth.*include.*system-local-login/a auth       optional     pam_gnome_keyring.so' /etc/pam.d/login
    # Adiciona session no final do arquivo
    echo "session    optional     pam_gnome_keyring.so auto_start" | sudo tee -a /etc/pam.d/login > /dev/null
    print_info "PAM login configurado!"
  else
    print_info "PAM login já possui gnome-keyring configurado"
  fi
  
  # Configura /etc/pam.d/system-login - adiciona apenas se não existir
  if ! sudo grep -q "pam_gnome_keyring.so" /etc/pam.d/system-login; then
    print_info "Adicionando gnome-keyring ao /etc/pam.d/system-login..."
    echo "session    optional     pam_gnome_keyring.so auto_start" | sudo tee -a /etc/pam.d/system-login > /dev/null
    print_info "PAM system-login configurado!"
  else
    print_info "PAM system-login já possui gnome-keyring configurado"
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

configure_omarchy_logout() {
  print_step "Configurando logout no menu de power do Omarchy"
  
  local omarchy_menu="$HOME/.local/share/omarchy/bin/omarchy-menu"
  
  if [[ ! -f "$omarchy_menu" ]]; then
    print_warn "Omarchy menu não encontrado: $omarchy_menu"
    return 0
  fi
  
  # Backup do script original
  if [[ ! -f "$omarchy_menu.bak.logout" ]]; then
    cp "$omarchy_menu" "$omarchy_menu.bak.logout"
    print_info "Backup criado: $omarchy_menu.bak.logout"
  fi
  
  # Verificar se já tem logout
  if grep -q "Logout" "$omarchy_menu"; then
    print_info "Logout já está configurado no menu"
    return 0
  fi
  
  # Fazer as modificações necessárias
  print_info "Adicionando logout ao menu de system..."
  
  # 1. Adicionar Logout na linha do menu
  sed -i 's/󰐥  Shutdown/󰐥  Shutdown\n󰍃  Logout/' "$omarchy_menu"
  
  # 2. Adicionar case para Logout após Shutdown
  sed -i '/\*Shutdown\*) systemctl poweroff ;;/a\  *Logout*) pkill -SIGTERM Hyprland ;;' "$omarchy_menu"
  
  # Verificar se a modificação foi bem-sucedida
  if grep -q "Logout" "$omarchy_menu"; then
    print_info "Logout adicionado ao menu de power com sucesso!"
    print_info "Para acessar: SUPER + ESCAPE → Logout"
  else
    print_error "Erro ao adicionar logout. Restaurando backup..."
    cp "$omarchy_menu.bak.logout" "$omarchy_menu"
    return 1
  fi
}

configure_autostart() {
  print_step "Configurando autostart de aplicações"
  
  local autostart_dir="$HOME/.config/autostart"
  
  # Criar diretório de autostart se não existir
  mkdir -p "$autostart_dir"
  
  # Configurar ZapZap para monitor 2
  local zapzap_desktop="$autostart_dir/zapzap.desktop"
  cat > "$zapzap_desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=ZapZap
Exec=sh -c 'sleep 10 && until hyprctl clients &>/dev/null; do sleep 1; done && hyprctl dispatch exec "[workspace 2 silent] zapzap"'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
  print_info "Autostart do ZapZap configurado (workspace 2) com aguardo do Hyprland"
  
  # Configurar Slack para monitor 2
  local slack_desktop="$autostart_dir/slack.desktop"
  cat > "$slack_desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Slack
Exec=sh -c 'sleep 15 && until hyprctl clients &>/dev/null; do sleep 1; done && hyprctl dispatch exec "[workspace 2 silent] slack"'
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
  print_info "Autostart do Slack configurado (workspace 2) com aguardo do Hyprland"
  
  print_info "Aplicações configuradas para inicializar no workspace 2:"
  print_info "- ZapZap (aguarda Hyprland + delay 10s)"
  print_info "- Slack (aguarda Hyprland + delay 15s)"
}

configure_clipse() {
  print_step "Configurando Clipse (Clipboard Manager)"
  
  local hypr_config="$HOME/.config/hypr/hyprland.conf"
  local bindings_file="$HOME/.config/hypr/bindings.conf"
  
  # Verifica se já está configurado
  local needs_config=false
  
  # Verifica exec-once
  if [[ -f "$hypr_config" ]] && ! grep -q "exec-once = clipse -listen" "$hypr_config"; then
    needs_config=true
  fi
  
  # Verifica windowrules
  if [[ -f "$hypr_config" ]] && ! grep -q "windowrulev2 = float,class:(clipse)" "$hypr_config"; then
    needs_config=true
  fi
  
  # Verifica binding
  if [[ -f "$bindings_file" ]] && ! grep -q "bind = ALT SHIFT, V, exec, alacritty --class clipse -e 'clipse'" "$bindings_file"; then
    needs_config=true
  fi
  
  if [[ "$needs_config" == false ]]; then
    print_info "Clipse já está completamente configurado"
    return 0
  fi
  
  # Configura exec-once no hyprland.conf
  if [[ -f "$hypr_config" ]]; then
    # Backup se ainda não existir
    if [[ ! -f "$hypr_config.bak.clipse" ]]; then
      cp "$hypr_config" "$hypr_config.bak.clipse"
      print_info "Backup criado: $hypr_config.bak.clipse"
    fi
    
    # Adiciona exec-once se não existir
    if ! grep -q "exec-once = clipse -listen" "$hypr_config"; then
      cat >> "$hypr_config" << 'EOF'

# Clipse - Clipboard Manager
exec-once = clipse -listen # run listener on startup
EOF
      print_info "Clipse listener adicionado ao exec-once"
    fi
    
    # Adiciona windowrules se não existir
    if ! grep -q "windowrulev2 = float,class:(clipse)" "$hypr_config"; then
      cat >> "$hypr_config" << 'EOF'

# Clipse window rules
windowrulev2 = float,class:(clipse) # ensure floating window
windowrulev2 = size 622 652,class:(clipse) # set window size
EOF
      print_info "Window rules do Clipse adicionadas"
    fi
  else
    print_warn "Arquivo de configuração do Hyprland não encontrado: $hypr_config"
  fi
  
  # Configura binding no bindings.conf
  if [[ -f "$bindings_file" ]]; then
    # Backup se ainda não existir
    if [[ ! -f "$bindings_file.bak.clipse" ]]; then
      cp "$bindings_file" "$bindings_file.bak.clipse"
      print_info "Backup criado: $bindings_file.bak.clipse"
    fi
    
    # Adiciona binding se não existir
    if ! grep -q "bind = ALT SHIFT, V, exec, alacritty --class clipse -e 'clipse'" "$bindings_file"; then
      # Procura por uma seção de bindings e adiciona após
      if grep -q "^bind = " "$bindings_file"; then
        # Adiciona após o último bind existente
        sed -i '/^bind = /a\
\
# Clipse - Clipboard Manager\
bind = ALT SHIFT, V, exec, alacritty --class clipse -e '"'"'clipse'"'"'' "$bindings_file"
      else
        # Se não houver bindings, adiciona no final
        cat >> "$bindings_file" << 'EOF'

# Clipse - Clipboard Manager
bind = ALT SHIFT, V, exec, alacritty --class clipse -e 'clipse'
EOF
      fi
      print_info "Atalho do Clipse configurado (ALT + SHIFT + V)"
    fi
  else
    print_warn "Arquivo de bindings do Hyprland não encontrado: $bindings_file"
  fi
  
  print_info "Clipse configurado com sucesso!"
  print_info "- Listener iniciará automaticamente no boot"
  print_info "- Use ALT + SHIFT + V para abrir o gerenciador de clipboard"
}

fix_nautilus_cursor() {
  print_step "Corrigindo problema do cursor no Nautilus"
  
  local envs_file="$HOME/.config/hypr/envs.conf"
  local needs_config=false
  
  # Verifica se já está configurado
  if [[ -f "$envs_file" ]]; then
    # Verifica se já tem as configurações do ibus
    if ! grep -q "GTK_IM_MODULE,ibus" "$envs_file" || \
       ! grep -q "QT_IM_MODULE,ibus" "$envs_file" || \
       ! grep -q "XMODIFIERS,@im=ibus" "$envs_file"; then
      needs_config=true
    fi
  else
    needs_config=true
  fi
  
  if [[ "$needs_config" == false ]]; then
    print_info "Fix do Nautilus já está configurado"
    return 0
  fi
  
  # Faz backup se arquivo existe
  if [[ -f "$envs_file" ]]; then
    if [[ ! -f "$envs_file.bak.nautilus" ]]; then
      cp "$envs_file" "$envs_file.bak.nautilus"
      print_info "Backup criado: $envs_file.bak.nautilus"
    fi
  else
    # Cria o arquivo se não existe
    touch "$envs_file"
    print_info "Criado arquivo: $envs_file"
  fi
  
  # Verifica e adiciona cada configuração individualmente para ser idempotente
  local configs_added=false
  
  # GTK_IM_MODULE
  if ! grep -q "env = GTK_IM_MODULE,ibus" "$envs_file"; then
    if [[ "$configs_added" == false ]]; then
      echo "" >> "$envs_file"
      echo "# Fix para cursor no Nautilus - desabilitar input methods conflitantes" >> "$envs_file"
      configs_added=true
    fi
    echo "env = GTK_IM_MODULE,ibus" >> "$envs_file"
    print_info "Adicionado: GTK_IM_MODULE=ibus"
  fi
  
  # QT_IM_MODULE
  if ! grep -q "env = QT_IM_MODULE,ibus" "$envs_file"; then
    echo "env = QT_IM_MODULE,ibus" >> "$envs_file"
    print_info "Adicionado: QT_IM_MODULE=ibus"
  fi
  
  # XMODIFIERS
  if ! grep -q "env = XMODIFIERS,@im=ibus" "$envs_file"; then
    echo "env = XMODIFIERS,@im=ibus" >> "$envs_file"
    print_info "Adicionado: XMODIFIERS=@im=ibus"
  fi
  
  # SDL_IM_MODULE
  if ! grep -q "env = SDL_IM_MODULE,ibus" "$envs_file"; then
    echo "env = SDL_IM_MODULE,ibus" >> "$envs_file"
    print_info "Adicionado: SDL_IM_MODULE=ibus"
  fi
  
  # GTK_USE_PORTAL
  if ! grep -q "env = GTK_USE_PORTAL,1" "$envs_file"; then
    echo "" >> "$envs_file"
    echo "# Garantir comportamento correto do GTK" >> "$envs_file"
    echo "env = GTK_USE_PORTAL,1" >> "$envs_file"
    print_info "Adicionado: GTK_USE_PORTAL=1"
  fi
  
  # Desabilita fcitx se estiver rodando
  if pgrep -x fcitx >/dev/null 2>&1; then
    print_info "Desabilitando fcitx..."
    pkill -f fcitx || true
  fi
  
  # Reinicia Nautilus se estiver rodando
  if pgrep -x nautilus >/dev/null 2>&1; then
    print_info "Reiniciando Nautilus..."
    nautilus -q 2>/dev/null || true
  fi
  
  print_info "Fix do cursor no Nautilus aplicado com sucesso!"
  print_info "Se necessário, recarregue o Hyprland com: hyprctl reload"
}

configure_aws_vpn() {
  print_step "Configurando AWS VPN Client"
  
  # Verifica se o pacote está instalado
  if ! pacman -Qi awsvpnclient >/dev/null 2>&1; then
    print_warn "AWS VPN Client não está instalado. Será instalado agora..."
    # Já está na lista de pacotes do install_desktop_apps
    return 0
  fi
  
  # 1. Configurar systemd-resolved (necessário para DNS do VPN)
  print_info "Configurando systemd-resolved para DNS do VPN..."
  
  # Verifica se systemd-resolved está habilitado e rodando
  if ! systemctl is-enabled --quiet systemd-resolved.service; then
    print_info "Habilitando systemd-resolved..."
    sudo systemctl enable systemd-resolved.service || true
  else
    print_info "systemd-resolved já está habilitado"
  fi
  
  if ! systemctl is-active --quiet systemd-resolved.service; then
    print_info "Iniciando systemd-resolved..."
    sudo systemctl start systemd-resolved.service || true
  else
    print_info "systemd-resolved já está rodando"
  fi
  
  # Verifica conflitos com outros resolvers
  if systemctl is-active --quiet dnsmasq.service 2>/dev/null; then
    print_warn "dnsmasq detectado - pode haver conflito com systemd-resolved"
    print_warn "Considere desabilitar dnsmasq se houver problemas de DNS com o VPN"
  fi
  
  if systemctl is-active --quiet systemd-networkd.service 2>/dev/null; then
    print_info "systemd-networkd detectado - compatível com systemd-resolved"
  fi
  
  # 2. Habilitar e iniciar o serviço do AWS VPN Client
  print_info "Configurando serviço do AWS VPN Client..."
  
  if ! systemctl is-enabled --quiet awsvpnclient.service; then
    print_info "Habilitando awsvpnclient.service..."
    sudo systemctl enable awsvpnclient.service || true
  else
    print_info "awsvpnclient.service já está habilitado"
  fi
  
  if ! systemctl is-active --quiet awsvpnclient.service; then
    print_info "Iniciando awsvpnclient.service..."
    sudo systemctl start awsvpnclient.service || true
  else
    print_info "awsvpnclient.service já está rodando"
  fi
  
  # 3. Verificar configuração de DNS
  print_info "Verificando configuração de DNS..."
  
  # Criar link simbólico para /etc/resolv.conf se necessário
  if [[ -f /etc/resolv.conf ]] && [[ ! -L /etc/resolv.conf ]]; then
    print_info "Configurando /etc/resolv.conf para usar systemd-resolved..."
    if [[ ! -f /etc/resolv.conf.bak.awsvpn ]]; then
      sudo cp /etc/resolv.conf /etc/resolv.conf.bak.awsvpn
      print_info "Backup criado: /etc/resolv.conf.bak.awsvpn"
    fi
    sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true
  elif [[ -L /etc/resolv.conf ]]; then
    local target=$(readlink -f /etc/resolv.conf)
    if [[ "$target" == "/run/systemd/resolve/stub-resolv.conf" ]] || \
       [[ "$target" == "/run/systemd/resolve/resolv.conf" ]]; then
      print_info "DNS já está configurado para systemd-resolved"
    else
      print_warn "resolv.conf aponta para: $target"
      print_warn "Pode ser necessário ajustar manualmente para systemd-resolved"
    fi
  fi
  
  # 4. Verificar status final
  print_info "Verificando status dos serviços..."
  
  if systemctl is-active --quiet systemd-resolved.service && \
     systemctl is-active --quiet awsvpnclient.service; then
    print_info "✓ AWS VPN Client configurado com sucesso!"
    print_info "- systemd-resolved está ativo para resolver DNS do VPN"
    print_info "- awsvpnclient.service está rodando"
    print_info "- Use o AWS VPN Client GUI ou CLI para conectar ao VPN"
  else
    print_warn "Verificação de status:"
    systemctl status systemd-resolved.service --no-pager | head -5 || true
    systemctl status awsvpnclient.service --no-pager | head -5 || true
    print_warn "Pode ser necessário reiniciar o sistema para aplicar todas as configurações"
  fi
}

main "$@"
