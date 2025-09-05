#!/bin/bash

# Script para aplicar apenas a correção do keyring no sistema atual
# Baseado na função configure_gnome_keyring() do post-install.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info()  { printf "\033[1;34m[i]\033[0m %s\n" "$*"; }
print_warn()  { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
print_error() { printf "\033[1;31m[x]\033[0m %s\n" "$*"; }
print_step()  { printf "\n\033[1;36m==> %s\033[0m\n" "$*"; }

print_step "Aplicando correção do GNOME Keyring no sistema atual"

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
    backup_dir="$HOME/.local/share/keyrings.bak.$(date +%Y%m%d%H%M%S)"
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
hypr_config="$HOME/.config/hypr/hyprland.conf"
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
env_file="$HOME/.config/environment.d/99-gnome-keyring.conf"
mkdir -p "$HOME/.config/environment.d"
cat > "$env_file" << 'EOF'
SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/keyring/ssh
GNOME_KEYRING_CONTROL=$XDG_RUNTIME_DIR/keyring
EOF

# Configura Chrome para usar keyring corretamente
print_info "Configurando Chrome para usar keyring..."
chrome_flags="$HOME/.config/chrome-flags.conf"
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
