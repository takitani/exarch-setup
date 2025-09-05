# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a simple Arch Linux + Hyprland post-installation script project. The repository contains a single main shell script that automates system setup and configuration tasks.

## Development Principles

### Script Safety and Idempotency
The post-install script MUST follow these critical principles:

1. **Always backup before modifying**: Before modifying any existing configuration file, create a backup with a descriptive suffix (e.g., `.bak`, `.bak.keyring`, `.bak.YYYYMMDD`)
2. **Idempotent operations**: The script must be safe to run multiple times without causing errors or duplicate configurations
3. **Check before applying**: Always verify if a configuration has already been applied before attempting to apply it
4. **Non-destructive**: Never overwrite user customizations unnecessarily
5. **Graceful failure handling**: Use conditional checks and `|| true` where appropriate to prevent script termination on non-critical failures

### Implementation patterns to follow:
- Use `cp -n` for backups (no-clobber) or check if backup exists first
- Use `grep` to check if configurations already exist before adding
- Use `--needed` flag with package managers to avoid reinstalling
- Wrap potentially failing commands with proper error handling
- Provide clear feedback about what was done vs. what was already configured

## Architecture

The project consists of:
- `post-install.sh`: Main bash script that handles system updates, application installation, locale configuration, and keyboard layout setup for Hyprland/Waybar environments

## Key Functions

The post-install script provides these main functions:
- `ensure_yay()`: Installs yay (AUR helper) if not present
- `update_system()`: Updates system packages using yay
- `install_desktop_apps()`: Installs desktop applications (mission-center, discord, zapzap, cpu-x)
- `set_locale_ptbr()`: Configures Brazilian Portuguese locale
- `configure_keyboard_layout()`: Sets up US/BR keyboard layout switching for Hyprland and Waybar

## Development Commands

Since this is a shell script project, development primarily involves:
- Running the script: `./post-install.sh`
- Testing with options: `./post-install.sh --no-install-yay`
- Checking syntax: `bash -n post-install.sh`

## Configuration Details

The script modifies:
- `/etc/locale.gen` for locale configuration
- `~/.config/hypr/input.conf` for Hyprland keyboard settings
- `~/.config/waybar/config.jsonc` and `~/.config/waybar/style.css` for Waybar language indicator

The keyboard layout uses US international as primary with Brazilian layout as secondary, switchable via Alt+Alt.