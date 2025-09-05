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
  print_step "Post-install: etapa de update finalizada"
  print_info "Pronto para próximas configurações."
}

main "$@"

set_locale_ptbr() {
  print_step "Configurando locale pt_BR.UTF-8"

  # Garante que a linha exista e esteja descomentada em /etc/locale.gen
  if ! grep -Eq '^[^#]*pt_BR\.UTF-8\s+UTF-8' /etc/locale.gen 2>/dev/null; then
    # Tenta descomentar, caso exista comentada
    if grep -Eq '^#\s*pt_BR\.UTF-8\s+UTF-8' /etc/locale.gen 2>/dev/null; then
      sudo sed -i 's/^#\s*pt_BR\.UTF-8\s\+UTF-8/pt_BR.UTF-8 UTF-8/' /etc/locale.gen || true
    else
      printf '\npt_BR.UTF-8 UTF-8\n' | sudo tee -a /etc/locale.gen >/dev/null || true
    fi
  fi

  # Gera locales
  sudo locale-gen

  # Define locale do sistema
  if localectl status 2>/dev/null | grep -q 'LANG=pt_BR.UTF-8'; then
    print_info "Locale já definido para pt_BR.UTF-8"
  else
    sudo localectl set-locale LANG=pt_BR.UTF-8
    print_info "Locale definido: LANG=pt_BR.UTF-8"
  fi
}

configure_keyboard_layout() {
  print_step "Configurando layout de teclado PT-BR (Hyprland + Waybar)"

  # Hyprland input.conf
  local hypr_input="$HOME/.config/hypr/input.conf"
  if [[ -f "$hypr_input" ]]; then
    cp -n "$hypr_input" "$hypr_input.bak" 2>/dev/null || cp "$hypr_input" "$hypr_input.bak"

    if ! grep -qE '^\s*kb_layout\s*=\s*us,br' "$hypr_input"; then
      # Tenta substituir exemplo comentado; se não houver, assegura a linha
      sed -i 's/^#\s*kb_layout\s*=\s*us,dk,eu/kb_layout = us,br/' "$hypr_input" || true
      if ! grep -qE '^\s*kb_layout\s*=\s*us,br' "$hypr_input"; then
        printf '\nkb_layout = us,br\n' >> "$hypr_input"
      fi

      # Ajusta kb_options conforme exemplo fornecido
      if grep -qE 'kb_options\s*=\s*compose:caps\s*#\s*,grp:alts_toggle' "$hypr_input"; then
        sed -i 's/kb_options\s*=\s*compose:caps\s*#\s*,grp:alts_toggle/kb_options = compose:caps,grp:alts_toggle/' "$hypr_input"
      fi

      # Adiciona kb_variant intl, após a linha de layout, se ainda não existir
      if ! grep -qE '^\s*kb_variant\s*=\s*intl,' "$hypr_input"; then
        sed -i '/^\s*kb_layout\s*=\s*us,br/a\  kb_variant = intl,' "$hypr_input"
      fi
      print_info "Hyprland: PT-BR e US-Intl configurados (Alt+Alt alterna)"
    else
      print_info "Hyprland: kb_layout us,br já presente"
    fi
  else
    print_warn "Hyprland: arquivo não encontrado: $hypr_input (pulando)"
  fi

  # Waybar config.jsonc
  local waybar_config="$HOME/.config/waybar/config.jsonc"
  if [[ -f "$waybar_config" ]]; then
    cp -n "$waybar_config" "$waybar_config.bak" 2>/dev/null || cp "$waybar_config" "$waybar_config.bak"
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
      cp -n "$waybar_css" "$waybar_css.bak" 2>/dev/null || cp "$waybar_css" "$waybar_css.bak"
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
  local pkgs=(mission-center discord zapzap cpu-x)
  yay -S --noconfirm --needed "${pkgs[@]}"
  print_info "Aplicativos desktop instalados/atualizados"
}
