# Exarch Setup - Arch Linux + Hyprland Post-Install Script

Script de pós-instalação automatizado para Arch Linux com Hyprland, otimizado para configuração brasileira com interface em inglês.

## 🚀 Execução Rápida (Remota)

Execute o script diretamente sem clonar o repositório:

```bash
# Via curl
bash <(curl -fsSL https://raw.githubusercontent.com/SEU_USUARIO/exarch-setup/main/post-install.sh)

# Via wget
bash <(wget -qO- https://raw.githubusercontent.com/SEU_USUARIO/exarch-setup/main/post-install.sh)

# Com opções (exemplo: sem instalar yay)
bash <(curl -fsSL https://raw.githubusercontent.com/SEU_USUARIO/exarch-setup/main/post-install.sh) --no-install-yay
```

## 📦 O que o script faz

### Sistema e Pacotes
- ✅ Instala o **yay** (AUR helper) se não estiver presente
- ✅ Atualiza todo o sistema via `yay -Syu`
- ✅ Instala aplicativos desktop essenciais:
  - Mission Center (monitor de sistema)
  - Discord
  - ZapZap (WhatsApp client)
  - CPU-X (informações de hardware)
  - Slack Desktop
  - Google Chrome
  - Cursor (IDE)
  - Visual Studio Code
  - Clipse (clipboard manager)
  - JetBrains Toolbox

### Configurações de Localização
- ✅ **Interface em inglês** com **formatação brasileira**
  - `LANG=en_US.UTF-8` (interface)
  - `LC_CTYPE=pt_BR.UTF-8` (suporte a caracteres brasileiros)
- ✅ **Teclado US Internacional** com cedilha (ç) funcionando corretamente
  - Layout: US International
  - Variante: intl
  - Compose key: Caps Lock

### Integrações do Sistema
- ✅ **GNOME Keyring** configurado para unlock automático
- ✅ **Hyprland** com atalhos personalizados
- ✅ **Waybar** com indicador de layout de teclado
- ✅ **Clipse** clipboard manager (ALT+SHIFT+V)
- ✅ **Autostart** de aplicações no workspace 2

## 💾 Instalação Local

```bash
# Clone o repositório
git clone https://github.com/SEU_USUARIO/exarch-setup.git
cd exarch-setup

# Torne o script executável
chmod +x post-install.sh

# Execute
./post-install.sh
```

## 🔧 Opções de Execução

```bash
# Execução padrão (instala yay se necessário)
./post-install.sh

# Não instalar yay automaticamente
./post-install.sh --no-install-yay

# Ver ajuda
./post-install.sh --help
```

## 🔒 Características de Segurança

- **Backups automáticos**: Cria backup com timestamp de todos os arquivos antes de modificar
- **Idempotente**: Pode ser executado múltiplas vezes sem causar problemas
- **Verificações**: Checa se configurações já existem antes de aplicar
- **Não destrutivo**: Preserva configurações existentes do usuário
- **Correção automática**: Detecta e corrige configurações incorretas (ex: xkb_* → kb_*)

## 📁 Arquivos Modificados

O script modifica os seguintes arquivos (sempre criando backups):

- `/etc/locale.gen` - Configuração de locales
- `/etc/pam.d/login` - PAM para GNOME Keyring
- `/etc/pam.d/system-login` - PAM para GNOME Keyring
- `~/.config/hypr/input.conf` - Configuração de teclado
- `~/.config/hypr/hyprland.conf` - Configurações do Hyprland
- `~/.config/hypr/bindings.conf` - Atalhos do Hyprland
- `~/.config/waybar/config.jsonc` - Configuração do Waybar
- `~/.config/waybar/style.css` - Estilos do Waybar
- `~/.config/environment.d/` - Variáveis de ambiente
- `~/.config/chrome-flags.conf` - Flags do Chrome
- `~/.config/autostart/` - Aplicações no autostart
- `~/.XCompose` - Configuração de cedilha
- `~/.bashrc` - Variáveis de ambiente

## 🐛 Solução de Problemas

### Erro de configuração do teclado
Se aparecer erro sobre `xkb_layout` ou similar:
- O script agora detecta e corrige automaticamente
- Execute o script novamente para aplicar correções

### Cedilha não funciona
Certifique-se de:
1. Reiniciar após executar o script
2. Usar `'` + `c` para obter ç
3. Verificar se `LC_CTYPE=pt_BR.UTF-8` está configurado

### GNOME Keyring não desbloqueia
1. Faça logout e login novamente
2. Na primeira vez, defina a senha igual à senha de login
3. Nas próximas vezes, desbloqueará automaticamente

## 📝 Logs e Backups

O script cria backups com timestamp:
- `arquivo.bak.YYYYMMDDHHMMSS` - Backups com data/hora
- `arquivo.bak.keyring` - Backups específicos do GNOME Keyring
- `arquivo.bak.clipse` - Backups específicos do Clipse

## 🤝 Contribuindo

Sinta-se à vontade para abrir issues ou pull requests!

## 📄 Licença

MIT License - veja o arquivo LICENSE para detalhes.

## ⚠️ Avisos

- Execute como **usuário normal**, não como root
- Recomendado para instalações limpas do Arch Linux com Hyprland
- Testado com Hyprland 0.40+ e Waybar 0.10+
- O script é voltado para o layout de teclado ABNT2 físico com US International no sistema