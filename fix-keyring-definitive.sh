#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Solução DEFINITIVA para o GNOME Keyring ===${NC}"
echo -e "${YELLOW}Este script resolve o problema do keyring pedindo senha${NC}\n"

# 1. Parar todos os processos
echo -e "${GREEN}[1/7] Parando processos...${NC}"
pkill -f gnome-keyring-daemon || true
pkill -f chrome || true
sleep 3

# 2. Limpar completamente os keyrings
echo -e "${GREEN}[2/7] Limpando keyrings...${NC}"
if [ -d "$HOME/.local/share/keyrings" ]; then
    BACKUP_DIR="$HOME/.local/share/keyrings.bak.$(date +%Y%m%d%H%M%S)"
    echo -e "${YELLOW}Fazendo backup em $BACKUP_DIR${NC}"
    mv "$HOME/.local/share/keyrings" "$BACKUP_DIR"
fi

# 3. Limpar sockets
echo -e "${GREEN}[3/7] Limpando sockets...${NC}"
rm -rf "$XDG_RUNTIME_DIR/keyring" || true
rm -rf "$XDG_RUNTIME_DIR/gnome-keyring" || true

# 4. Corrigir PAM - usar configuração mais robusta
echo -e "${GREEN}[4/7] Configurando PAM...${NC}"
if [ ! -f /etc/pam.d/login.bak.keyring ]; then
    sudo cp /etc/pam.d/login /etc/pam.d/login.bak.keyring
fi

# Configuração PAM mais robusta
sudo tee /etc/pam.d/login > /dev/null << 'EOF'
#%PAM-1.0

auth       requisite    pam_nologin.so
auth       include      system-local-login
auth       optional     pam_gnome_keyring.so
account    include      system-local-login
password   include      system-local-login
session    include      system-local-login
session    optional     pam_gnome_keyring.so auto_start
EOF

# 5. Configurar Hyprland corretamente
echo -e "${GREEN}[5/7] Configurando Hyprland...${NC}"
HYPR_CONFIG="$HOME/.config/hypr/hyprland.conf"

if [ -f "$HYPR_CONFIG" ]; then
    # Remove todas as linhas do gnome-keyring
    sed -i '/gnome-keyring-daemon/d' "$HYPR_CONFIG"
    
    # Adiciona configuração correta
    cat >> "$HYPR_CONFIG" << 'EOF'

# GNOME Keyring - Configuração definitiva
exec-once = gnome-keyring-daemon --start --components=pkcs11,secrets,ssh
exec-once = systemctl --user import-environment GNOME_KEYRING_CONTROL GNOME_KEYRING_PID SSH_AUTH_SOCK
EOF
fi

# 6. Configurar variáveis de ambiente
echo -e "${GREEN}[6/7] Configurando variáveis de ambiente...${NC}"
mkdir -p "$HOME/.config/environment.d"
cat > "$HOME/.config/environment.d/99-gnome-keyring.conf" << 'EOF'
SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/keyring/ssh
GNOME_KEYRING_CONTROL=$XDG_RUNTIME_DIR/keyring
EOF

# 7. Corrigir Chrome flags (remover duplicatas)
echo -e "${GREEN}[7/7] Corrigindo Chrome flags...${NC}"
CHROME_FLAGS="$HOME/.config/chrome-flags.conf"
mkdir -p "$(dirname "$CHROME_FLAGS")"

# Remove arquivo antigo e cria novo
rm -f "$CHROME_FLAGS"
cat > "$CHROME_FLAGS" << 'EOF'
--password-store=gnome
--enable-features=UseOzonePlatform
--ozone-platform=wayland
EOF

echo -e "\n${GREEN}=== Correção Completa! ===${NC}"
echo -e "\n${RED}INSTRUÇÕES CRÍTICAS:${NC}"
echo -e "${YELLOW}1.${NC} Faça ${RED}LOGOUT COMPLETO${NC} agora"
echo -e "${YELLOW}2.${NC} Faça login novamente"
echo -e "${YELLOW}3.${NC} ${GREEN}Se aparecer janela pedindo senha do keyring:${NC}"
echo -e "    - Digite sua ${RED}SENHA DE LOGIN${NC}"
echo -e "    - Marque '${RED}Usar esta senha para desbloquear automaticamente${NC}'"
echo -e "    - Clique em ${RED}Unlock${NC}"
echo -e "${YELLOW}4.${NC} O Chrome não deve mais pedir senha!"
echo -e "\n${YELLOW}Se ainda pedir senha:${NC}"
echo -e "- Execute: ${GREEN}seahorse${NC}"
echo -e "- Delete o keyring 'Default Keyring'"
echo -e "- Faça logout/login novamente"
echo -e "- Crie novo keyring com senha igual ao login"
