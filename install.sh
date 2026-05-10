#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║          PiTV OS - Script d'Installation v1.1               ║
# ║  Compatible: Raspberry Pi 3B/4/5 · Linux x86_64 · ARM      ║
# ║  Windows : utiliser install.ps1 ou WSL                      ║
# ╚══════════════════════════════════════════════════════════════╝

set -e
SCRIPT_VERSION="1.1.0"
PITV_DIR="/opt/pitv"
PITV_SERVICE="pitv-server"
KIOSK_SERVICE="pitv-kiosk"
PITV_USER="pitv"
NODE_VERSION="20"
PORT=8080

# ─── Couleurs ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ─── Bannière ─────────────────────────────────────────────────────────────────
print_banner() {
  clear
  echo -e "${CYAN}"
  echo "  ██████╗ ██╗    ████████╗██╗   ██╗       ██████╗ ███████╗"
  echo "  ██╔══██╗██║       ██╔══╝╚██╗ ██╔╝      ██╔═══██╗██╔════╝"
  echo "  ██████╔╝██║       ██║    ╚████╔╝       ██║   ██║███████╗"
  echo "  ██╔═══╝ ██║       ██║    ██╔═██╗       ██║   ██║╚════██║"
  echo "  ██║     ██║       ██║   ██╔╝ ╚██╗      ╚██████╔╝███████║"
  echo "  ╚═╝     ╚═╝       ╚═╝   ╚═╝   ╚═╝       ╚═════╝ ╚══════╝"
  echo -e "${NC}"
  echo -e "  ${DIM}Raspberry Pi IPTV Operating System — v${SCRIPT_VERSION}${NC}"
  echo -e "  ${DIM}Source: https://github.com/iptv-org/iptv${NC}"
  echo ""
  echo -e "  ${YELLOW}⚡ Ce script va installer PiTV OS sur votre Raspberry Pi${NC}"
  echo ""
}

# ─── Fonctions utilitaires ────────────────────────────────────────────────────
log()     { echo -e "  ${CYAN}[INFO]${NC} $*"; }
ok()      { echo -e "  ${GREEN}[  OK  ]${NC} $*"; }
warn()    { echo -e "  ${YELLOW}[ WARN ]${NC} $*"; }
error()   { echo -e "  ${RED}[ERROR]${NC} $*"; exit 1; }
step()    { echo -e "\n  ${BOLD}${BLUE}▶ $*${NC}"; }
hr()      { echo -e "  ${DIM}────────────────────────────────────────${NC}"; }

confirm() {
  echo -e "\n  ${YELLOW}$1${NC}"
  echo -ne "  Continuer ? [O/n] "
  read -r ans
  case $ans in
    n|N|non|no) echo "  Annulé."; exit 0;;
    *) return 0;;
  esac
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    error "Ce script doit être exécuté en root : sudo bash install.sh"
  fi
}

# ─── DÉTECTION OS & ARCHITECTURE ──────────────────────────────────────────────
detect_os() {
  step "Détection du système d'exploitation"

  # Windows : impossible de continuer avec bash natif
  if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || -n "$WINDIR" ]]; then
    echo ""
    echo -e "  ${RED}${BOLD}⚠  Windows détecté${NC}"
    echo -e "  ${YELLOW}Ce script bash ne fonctionne pas nativement sous Windows.${NC}"
    echo ""
    echo -e "  ${BOLD}Options pour Windows :${NC}"
    echo -e "  ${CYAN}1. WSL (recommandé) :${NC}"
    echo -e "     wsl --install   # dans PowerShell en admin"
    echo -e "     puis relancer ce script dans WSL"
    echo ""
    echo -e "  ${CYAN}2. Script PowerShell (install.ps1) :${NC}"
    echo -e "     Ouvrez PowerShell en administrateur puis :"
    echo -e "     Set-ExecutionPolicy Bypass -Scope Process"
    echo -e "     .\\install.ps1"
    echo ""
    echo -e "  ${CYAN}3. Mode standalone (sans installation) :${NC}"
    echo -e "     Ouvrez directement index.html dans Chrome/Edge"
    echo -e "     (connexion Internet requise pour les chaînes)"
    echo ""
    exit 1
  fi

  # Détecte la distribution Linux
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_NAME="$NAME"
    OS_ID="$ID"
    OS_VERSION="${VERSION_ID:-?}"
  elif [[ -f /etc/debian_version ]]; then
    OS_NAME="Debian"
    OS_ID="debian"
  else
    OS_NAME="Linux (inconnu)"
    OS_ID="linux"
  fi

  # Architecture
  ARCH=$(uname -m)
  case "$ARCH" in
    aarch64|arm64) ARCH_LABEL="ARM64 (Pi 4/5 64-bit)" ;;
    armv7l|armhf)  ARCH_LABEL="ARMv7 (Pi 3B/4 32-bit)" ;;
    x86_64)        ARCH_LABEL="x86_64 (PC/Serveur)" ;;
    *)             ARCH_LABEL="$ARCH" ;;
  esac

  ok "OS : ${OS_NAME} ${OS_VERSION} — Architecture : ${ARCH_LABEL}"

  # macOS non supporté par ce script (installation via Homebrew à faire manuellement)
  if [[ "$OSTYPE" == "darwin"* ]]; then
    warn "macOS détecté — le mode kiosque et systemd ne seront pas configurés"
    warn "Seul le serveur Node.js sera installé"
    IS_MACOS=true
  else
    IS_MACOS=false
  fi
}

detect_pi() {
  step "Détection du matériel"
  if grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    PI_MODEL=$(grep "Model" /proc/cpuinfo | tail -1 | cut -d: -f2 | xargs)
    IS_PI=true
    ok "Raspberry Pi détecté : ${PI_MODEL}"
  else
    IS_PI=false
    PI_MODEL="Linux générique (${ARCH_LABEL:-$(uname -m)})"
    ok "Matériel : ${PI_MODEL}"
  fi

  # Détecte si c'est Lite (pas de display manager)
  if dpkg -l lightdm 2>/dev/null | grep -q '^ii'; then
    HAS_DESKTOP=true
    ok "Environnement desktop détecté (LightDM)"
  elif dpkg -l lxde 2>/dev/null | grep -q '^ii'; then
    HAS_DESKTOP=true
    ok "Environnement desktop détecté (LXDE)"
  elif dpkg -l gdm3 2>/dev/null | grep -q '^ii' || dpkg -l sddm 2>/dev/null | grep -q '^ii'; then
    HAS_DESKTOP=true
    ok "Environnement desktop détecté (GDM3/SDDM)"
  else
    HAS_DESKTOP=false
    warn "Pas d'environnement desktop — installation de X11 + Openbox"
  fi

  # Détecte l'utilisateur courant pour le kiosque
  # Sur Pi c'est 'pi', sur Ubuntu 'ubuntu', sinon le premier utilisateur non-root
  if id "pi" &>/dev/null; then
    KIOSK_USER="pi"
  elif id "ubuntu" &>/dev/null; then
    KIOSK_USER="ubuntu"
  elif id "admin" &>/dev/null; then
    KIOSK_USER="admin"
  else
    KIOSK_USER=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
    if [[ -z "$KIOSK_USER" ]]; then KIOSK_USER="pitv"; fi
  fi
  ok "Utilisateur kiosque : ${KIOSK_USER}"
}

# ─── VÉRIFICATIONS INITIALES ──────────────────────────────────────────────────
check_root
print_banner
detect_os
detect_pi

hr
echo -e "  ${BOLD}Résumé de l'installation :${NC}"
echo -e "  • OS : ${CYAN}${OS_NAME:-Linux} ${OS_VERSION:-}${NC}"
echo -e "  • Matériel : ${CYAN}${PI_MODEL}${NC}"
echo -e "  • Répertoire : ${CYAN}${PITV_DIR}${NC}"
echo -e "  • Port serveur : ${CYAN}${PORT}${NC}"
echo -e "  • Utilisateur kiosque : ${CYAN}${KIOSK_USER}${NC}"
echo -e "  • Desktop : ${HAS_DESKTOP} ($(${HAS_DESKTOP} && echo 'existant' || echo 'à installer'))"
echo -e "  • Node.js ${NODE_VERSION} + npm"
echo -e "  • Chromium en mode kiosque"
echo -e "  • Services systemd"
[[ "$IS_PI" == "true" ]] && echo -e "  • Boot splash Plymouth + config GPU"
hr

confirm "L'installation va modifier le système."

# ─── 1. MISE À JOUR SYSTÈME ────────────────────────────────────────────────────
step "Mise à jour du système"
apt-get update -y 2>&1 | tail -3
apt-get upgrade -y 2>&1 | tail -3
ok "Système à jour"

# ─── 2. DÉPENDANCES DE BASE ────────────────────────────────────────────────────
step "Installation des dépendances de base"
apt-get install -y \
  curl wget git ca-certificates gnupg lsb-release \
  build-essential unzip jq net-tools \
  2>&1 | tail -5
ok "Dépendances de base installées"

# ─── 3. NODE.JS ────────────────────────────────────────────────────────────────
step "Installation de Node.js ${NODE_VERSION}"
if node --version 2>/dev/null | grep -q "^v${NODE_VERSION}"; then
  ok "Node.js ${NODE_VERSION} déjà installé"
else
  curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - 2>&1 | tail -5
  apt-get install -y nodejs 2>&1 | tail -3
  ok "Node.js $(node --version) installé"
fi

# ─── 4. ENVIRONNEMENT X11 / DESKTOP (si Lite) ─────────────────────────────────
if [[ "$HAS_DESKTOP" == "false" ]]; then
  step "Installation de l'environnement graphique minimal"
  
  apt-get install -y \
    xserver-xorg x11-xserver-utils xinit \
    openbox obconf \
    xdotool xrandr \
    unclutter \
    fonts-dejavu fonts-liberation fonts-noto \
    2>&1 | tail -10
  ok "X11 + Openbox installés"

  # Configurer l'autologin en mode console
  step "Configuration de l'autologin console"
  mkdir -p /etc/systemd/system/getty@tty1.service.d
  cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${KIOSK_USER} --noclear %I \$TERM
Type=simple
EOF
  ok "Autologin configuré pour l'utilisateur '${KIOSK_USER}'"

  # Profil bash pour démarrer X automatiquement
  step "Configuration du démarrage automatique de X"
  BASH_PROFILE_CONTENT='
# PiTV OS - Auto-start X
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
  exec startx /opt/pitv/start-kiosk.sh -- :0 -nocursor
fi
'
  # Ajoute pour l'utilisateur kiosque
  if id "${KIOSK_USER}" &>/dev/null; then
    USER_HOME=$(getent passwd "${KIOSK_USER}" | cut -d: -f6)
    if ! grep -q "PiTV OS" "${USER_HOME}/.bash_profile" 2>/dev/null; then
      echo "$BASH_PROFILE_CONTENT" >> "${USER_HOME}/.bash_profile"
    fi
    ok "Auto-start X configuré pour '${KIOSK_USER}'"
  fi

else
  step "Installation des outils X complémentaires"
  apt-get install -y xdotool unclutter fonts-noto 2>&1 | tail -3
  ok "Outils X installés"
fi

# ─── 5. CHROMIUM ────────────────────────────────────────────────────────────────
step "Installation de Chromium"

# Détecte le bon nom de paquet selon la distro/version
# Raspberry Pi OS Bookworm (Debian 12+) : paquet "chromium"
# Anciennes versions / Ubuntu : "chromium-browser"
find_chromium_package() {
  # Déjà installé ?
  if command -v chromium &>/dev/null; then echo "installed:chromium"; return; fi
  if command -v chromium-browser &>/dev/null; then echo "installed:chromium-browser"; return; fi

  # Cherche quel paquet est disponible dans apt
  if apt-cache show chromium &>/dev/null 2>&1; then
    echo "pkg:chromium"
  elif apt-cache show chromium-browser &>/dev/null 2>&1; then
    echo "pkg:chromium-browser"
  else
    echo "none"
  fi
}

CHROMIUM_PKG=$(find_chromium_package)

case "$CHROMIUM_PKG" in
  installed:*)
    CHROMIUM_BIN=$(command -v chromium 2>/dev/null || command -v chromium-browser 2>/dev/null)
    ok "Chromium déjà installé : ${CHROMIUM_BIN}"
    ;;
  pkg:chromium)
    apt-get install -y chromium 2>&1 | tail -5
    CHROMIUM_BIN=$(command -v chromium)
    ok "Chromium installé (paquet: chromium)"
    ;;
  pkg:chromium-browser)
    apt-get install -y chromium-browser 2>&1 | tail -5
    CHROMIUM_BIN=$(command -v chromium-browser)
    ok "Chromium installé (paquet: chromium-browser)"
    ;;
  none)
    warn "Chromium non trouvé dans apt — tentative via snap..."
    if command -v snap &>/dev/null; then
      snap install chromium 2>&1 | tail -3
      CHROMIUM_BIN=$(command -v chromium || echo "/snap/bin/chromium")
      ok "Chromium installé via snap"
    else
      warn "Impossible d'installer Chromium automatiquement."
      warn "Installez-le manuellement : sudo apt install chromium"
      CHROMIUM_BIN="/usr/bin/chromium"
    fi
    ;;
esac

# Vérifie que le binaire existe vraiment
if [[ ! -x "$CHROMIUM_BIN" ]]; then
  CHROMIUM_BIN=$(command -v chromium 2>/dev/null || command -v chromium-browser 2>/dev/null || echo "/usr/bin/chromium")
fi

ok "Binaire Chromium : ${CHROMIUM_BIN}"

# ─── 6. PLYMOUTH (boot splash) — Raspberry Pi uniquement ─────────────────────
if [[ "$IS_PI" == "true" ]]; then
step "Installation du splash screen Plymouth"
if apt-get install -y plymouth plymouth-themes 2>&1 | tail -3; then
  ok "Plymouth installé"

  # Créer un thème PiTV personnalisé
  THEME_DIR="/usr/share/plymouth/themes/pitv"
  mkdir -p "$THEME_DIR"

  cat > "${THEME_DIR}/pitv.plymouth" << 'PLYM'
[Plymouth Theme]
Name=PiTV OS
Description=PiTV OS Boot Theme
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/pitv
ScriptFile=/usr/share/plymouth/themes/pitv/pitv.script
PLYM

  cat > "${THEME_DIR}/pitv.script" << 'SCRIPT'
# PiTV OS Plymouth Boot Script
Window.SetBackgroundTopColor(0.03, 0.04, 0.06);
Window.SetBackgroundBottomColor(0.03, 0.04, 0.06);

title_image = Image("pitv-logo.png");
if (!title_image) {
  logo = Sprite();
} else {
  logo = Sprite(title_image);
  logo.SetX(Window.GetWidth() / 2 - title_image.GetWidth() / 2);
  logo.SetY(Window.GetHeight() / 2 - title_image.GetHeight() / 2 - 40);
}

progress_box = Sprite();
progress_box.SetPosition(Window.GetWidth() / 2 - 140, Window.GetHeight() * 0.7);

bar_image = Image.CreateFilledRectangle(280, 2, 0.0, 0.9, 1.0, 0.8);
bar = Sprite(bar_image);
bar.SetPosition(Window.GetWidth() / 2 - 140, Window.GetHeight() * 0.7);

status_msg = "Démarrage de PiTV OS...";

fun refresh_callback() {
  msg.SetText(status_msg);
}

fun progress_callback(dur) {
  new_image = Image.CreateFilledRectangle(Math.Int(280 * dur), 2, 0.0, 0.9, 1.0, 0.8);
  bar.SetImage(new_image);
}

Plymouth.SetBootProgressFunction(progress_callback);
Plymouth.SetRefreshFunction(refresh_callback);
SCRIPT

  # Image de remplacement si on ne peut pas créer une vraie image
  # On crée un script qui génère l'image via convert (ImageMagick)
  if command -v convert &>/dev/null; then
    convert -size 400x80 xc:'#07090f' \
      -fill '#00e5ff' -font /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf \
      -pointsize 48 -gravity center -annotate 0 'PiTV OS' \
      "${THEME_DIR}/pitv-logo.png" 2>/dev/null || true
  fi

  # Appliquer le thème
  plymouth-set-default-theme pitv 2>/dev/null || true
  update-initramfs -u 2>/dev/null | tail -3 || true
  ok "Thème Plymouth PiTV configuré"
else
  warn "Plymouth non disponible — splash screen ignoré"
fi
# Fin bloc IS_PI Plymouth
fi

# ─── 7. CONFIGURATION GPU RASPBERRY PI ────────────────────────────────────────
if [[ "$IS_PI" == "true" ]]; then
step "Optimisation GPU Raspberry Pi"
if [[ -f /boot/config.txt ]]; then
  # GPU memory 128MB pour la vidéo
  if ! grep -q "gpu_mem=128" /boot/config.txt; then
    echo "" >> /boot/config.txt
    echo "# PiTV OS - GPU Configuration" >> /boot/config.txt
    echo "gpu_mem=128" >> /boot/config.txt
  fi

  # Forcer sortie HDMI
  if ! grep -q "hdmi_force_hotplug=1" /boot/config.txt; then
    echo "hdmi_force_hotplug=1" >> /boot/config.txt
    echo "hdmi_drive=2" >> /boot/config.txt
  fi

  # Désactiver le cursor clignotant sur console
  if [[ -f /boot/cmdline.txt ]]; then
    if ! grep -q "vt.global_cursor_default=0" /boot/cmdline.txt; then
      sed -i 's/$/ vt.global_cursor_default=0 logo.nologo quiet splash/' /boot/cmdline.txt
    fi
  fi

  ok "GPU configuré (128MB, HDMI forcé)"
elif [[ -f /boot/firmware/config.txt ]]; then
  if ! grep -q "gpu_mem=128" /boot/firmware/config.txt; then
    echo "" >> /boot/firmware/config.txt
    echo "# PiTV OS" >> /boot/firmware/config.txt
    echo "gpu_mem=128" >> /boot/firmware/config.txt
    echo "hdmi_force_hotplug=1" >> /boot/firmware/config.txt
    echo "hdmi_drive=2" >> /boot/firmware/config.txt
  fi
  ok "GPU configuré (Ubuntu /boot/firmware)"
else
  warn "Fichier config.txt non trouvé — configuration GPU ignorée"
fi
# Fin bloc IS_PI GPU
else
  log "Configuration GPU ignorée (non-Raspberry Pi)"
fi

# ─── 8. CRÉATION UTILISATEUR ──────────────────────────────────────────────────
step "Configuration de l'utilisateur système"
if ! id "$PITV_USER" &>/dev/null; then
  useradd -r -s /bin/false -d "$PITV_DIR" "$PITV_USER"
  ok "Utilisateur '${PITV_USER}' créé"
else
  ok "Utilisateur '${PITV_USER}' existe déjà"
fi

# ─── 9. INSTALLATION DE L'APPLICATION ────────────────────────────────────────
step "Installation de PiTV OS dans ${PITV_DIR}"

# Crée le répertoire
mkdir -p "${PITV_DIR}/public"
mkdir -p "${PITV_DIR}/logs"

# Copie les fichiers depuis le répertoire courant
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "${SCRIPT_DIR}/server.js" ]]; then
  cp "${SCRIPT_DIR}/server.js" "${PITV_DIR}/"
  cp "${SCRIPT_DIR}/package.json" "${PITV_DIR}/"
  cp -r "${SCRIPT_DIR}/public/"* "${PITV_DIR}/public/" 2>/dev/null || true
  ok "Fichiers de l'application copiés"
else
  # Téléchargement depuis GitHub (si disponible)
  warn "Fichiers source non trouvés localement — tentative de téléchargement..."
  # Vous pouvez remplacer cette URL par votre dépôt
  # wget -q --show-progress -O /tmp/pitv.tar.gz "https://github.com/votre-repo/pitv-os/archive/main.tar.gz"
  error "Placez les fichiers du projet dans le même dossier que ce script."
fi

# Installe les dépendances npm
step "Installation des dépendances Node.js"
cd "${PITV_DIR}"
npm install --production 2>&1 | tail -5
ok "Dépendances npm installées"

# Permissions
chown -R "${KIOSK_USER}:${KIOSK_USER}" "${PITV_DIR}" 2>/dev/null || true

# ─── 10. SCRIPT DE DÉMARRAGE KIOSK ────────────────────────────────────────────
step "Configuration du mode kiosque"

cat > "${PITV_DIR}/start-kiosk.sh" << KIOSK
#!/bin/bash
# PiTV OS - Script de démarrage kiosque

export DISPLAY=:0
export XAUTHORITY=/home/${KIOSK_USER}/.Xauthority

# Attendre que le serveur soit prêt
MAX_WAIT=30
for i in \$(seq 1 \$MAX_WAIT); do
  if curl -s http://127.0.0.1:${PORT}/api/status > /dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Paramètres écran
xset -dpms s off 2>/dev/null || true
xset s noblank 2>/dev/null || true
xset s 0 2>/dev/null || true

# Cacher le curseur
unclutter -idle 2 -root &

# Désactiver la mise en veille
xrandr --auto 2>/dev/null || true

# Chromium en mode kiosque
${CHROMIUM_BIN} \\
  --kiosk \\
  --no-sandbox \\
  --disable-infobars \\
  --disable-session-crashed-bubble \\
  --disable-notifications \\
  --disable-pinch \\
  --noerrdialogs \\
  --disable-translate \\
  --disable-features=TranslateUI \\
  --no-first-run \\
  --disable-background-networking \\
  --disable-sync \\
  --disable-extensions \\
  --password-store=basic \\
  --use-gl=egl \\
  --enable-gpu-rasterization \\
  --enable-zero-copy \\
  --disable-gpu-sandbox \\
  --ignore-gpu-blacklist \\
  --enable-hardware-overlays \\
  --process-per-site \\
  --window-size=1920,1080 \\
  --window-position=0,0 \\
  --start-fullscreen \\
  --app=http://127.0.0.1:${PORT}/ \\
  2>/dev/null

KIOSK
chmod +x "${PITV_DIR}/start-kiosk.sh"
ok "Script kiosque créé"

# ─── 11. CONFIGURATION OPENBOX (si Lite) ──────────────────────────────────────
if [[ "$HAS_DESKTOP" == "false" ]]; then
  step "Configuration d'Openbox"
  mkdir -p /etc/xdg/openbox

  # Vrai script de démarrage X
  cat > /etc/xdg/openbox/autostart << OBFULL
# PiTV OS - Openbox Autostart

# Attendre le serveur PiTV
WAIT=0
while ! curl -s http://127.0.0.1:${PORT}/api/status >/dev/null 2>&1; do
  sleep 1
  WAIT=\$((WAIT+1))
  if [ \$WAIT -gt 60 ]; then break; fi
done

# Désactiver économiseur d'écran
xset -dpms s off &
xset s noblank &
xset s 0 &

# Cacher le curseur après 2s d'inactivité
unclutter -idle 2 -root &

# Chromium kiosque
${CHROMIUM_BIN} \\
  --kiosk \\
  --no-sandbox \\
  --disable-infobars \\
  --disable-session-crashed-bubble \\
  --disable-notifications \\
  --disable-pinch \\
  --noerrdialogs \\
  --disable-translate \\
  --no-first-run \\
  --disable-background-networking \\
  --disable-sync \\
  --disable-extensions \\
  --use-gl=egl \\
  --enable-gpu-rasterization \\
  --enable-zero-copy \\
  --ignore-gpu-blacklist \\
  --process-per-site \\
  --start-fullscreen \\
  --app=http://127.0.0.1:${PORT}/ &

OBFULL

  ok "Openbox configuré pour le mode kiosque"
fi

# ─── 12. SERVICE SYSTEMD - SERVEUR NODE.JS ────────────────────────────────────
step "Création du service systemd (serveur Node.js)"

cat > "/etc/systemd/system/${PITV_SERVICE}.service" << SERVICE
[Unit]
Description=PiTV OS - Serveur IPTV
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=${KIOSK_USER}
WorkingDirectory=${PITV_DIR}
ExecStart=$(command -v node) ${PITV_DIR}/server.js
Restart=always
RestartSec=5
StandardOutput=append:${PITV_DIR}/logs/server.log
StandardError=append:${PITV_DIR}/logs/server.error.log
Environment=NODE_ENV=production
Environment=PORT=${PORT}

[Install]
WantedBy=multi-user.target
SERVICE
ok "Service ${PITV_SERVICE} créé"

# ─── 13. SERVICE SYSTEMD - KIOSQUE CHROMIUM ───────────────────────────────────
step "Création du service systemd (kiosque Chromium)"

# Détermine le mode d'affichage
if [[ "$HAS_DESKTOP" == "true" ]]; then
  # Desktop existant : utilise le display manager
  KIOSK_EXEC="${PITV_DIR}/start-kiosk.sh"
  KIOSK_AFTER="graphical.target lightdm.service"
  KIOSK_WANTS="graphical.target"
else
  # Lite : démarre X manuellement
  KIOSK_EXEC="startx /etc/xdg/openbox/autostart -- :0 -nocursor"
  KIOSK_AFTER="graphical-session.target ${PITV_SERVICE}.service"
  KIOSK_WANTS="graphical-session.target"
fi

cat > "/etc/systemd/system/${KIOSK_SERVICE}.service" << KSERVICE
[Unit]
Description=PiTV OS - Interface Kiosque
After=${KIOSK_AFTER} ${PITV_SERVICE}.service
Wants=${KIOSK_WANTS}
Requires=${PITV_SERVICE}.service

[Service]
Type=simple
User=${KIOSK_USER}
Group=${KIOSK_USER}
PAMName=login
Environment=HOME=/home/${KIOSK_USER}
Environment=DISPLAY=:0
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u ${KIOSK_USER} 2>/dev/null || echo 1000)
ExecStartPre=/bin/sleep 5
ExecStart=${KIOSK_EXEC}
Restart=always
RestartSec=10
StandardOutput=append:${PITV_DIR}/logs/kiosk.log
StandardError=append:${PITV_DIR}/logs/kiosk.error.log

[Install]
WantedBy=graphical.target
KSERVICE
ok "Service ${KIOSK_SERVICE} créé"

# ─── 14. ACTIVER ET DÉMARRER LES SERVICES ────────────────────────────────────
step "Activation des services"
systemctl daemon-reload
systemctl enable "${PITV_SERVICE}"
systemctl enable "${KIOSK_SERVICE}"
ok "Services activés au démarrage"

# Démarrer maintenant
systemctl start "${PITV_SERVICE}" && ok "Serveur PiTV démarré" || warn "Le serveur démarrera au prochain boot"

# ─── 15. DÉSACTIVER L'ÉCONOMISEUR D'ÉCRAN SYSTÈME ─────────────────────────────
step "Désactivation de l'économiseur d'écran"

# LightDM
if [[ -f /etc/lightdm/lightdm.conf ]]; then
  sed -i 's/#xserver-command=X/xserver-command=X -nocursor/' /etc/lightdm/lightdm.conf 2>/dev/null || true
fi

# cron pour empêcher la mise en veille
cat > /etc/cron.d/pitv-screensaver << CRON
*/10 * * * * ${KIOSK_USER} DISPLAY=:0 xset s off -dpms 2>/dev/null || true
CRON
ok "Économiseur d'écran désactivé"

# ─── 16. CONFIGURATION RÉSEAU ─────────────────────────────────────────────────
step "Configuration pare-feu"
if command -v ufw &>/dev/null; then
  ufw allow ${PORT}/tcp comment "PiTV OS" 2>/dev/null || true
  ok "Port ${PORT} ouvert dans UFW"
fi

# ─── 17. RACCOURCIS CLAVIER SYSTÈME ───────────────────────────────────────────
step "Configuration des raccourcis clavier"
if [[ "$HAS_DESKTOP" == "false" ]]; then
  # Openbox keyboard shortcuts
  mkdir -p /etc/xdg/openbox
  if [[ ! -f /etc/xdg/openbox/rc.xml ]]; then
    cat > /etc/xdg/openbox/rc.xml << 'OBXML'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <keyboard>
    <!-- Redémarrer le kiosque si Chromium se ferme -->
    <keybind key="F11">
      <action name="Execute">
        <command>pkill chromium; sleep 1; /opt/pitv/start-kiosk.sh</command>
      </action>
    </keybind>
    <!-- Quitter (pour debug) -->
    <keybind key="C-A-q">
      <action name="Execute">
        <command>openbox --exit</command>
      </action>
    </keybind>
  </keyboard>
</openbox_config>
OBXML
  fi
fi
ok "Raccourcis clavier configurés"

# ─── 18. SCRIPT DE GESTION ────────────────────────────────────────────────────
step "Création des outils de gestion"
cat > /usr/local/bin/pitv << 'MGMT'
#!/bin/bash
# PiTV OS - Outil de gestion
case "$1" in
  start)   systemctl start pitv-server pitv-kiosk ;;
  stop)    systemctl stop pitv-server pitv-kiosk ;;
  restart) systemctl restart pitv-server pitv-kiosk ;;
  status)  systemctl status pitv-server pitv-kiosk ;;
  logs)    journalctl -u pitv-server -f ;;
  kiosk-logs) journalctl -u pitv-kiosk -f ;;
  update)
    cd /opt/pitv
    npm install --production
    systemctl restart pitv-server
    echo "PiTV OS mis à jour"
    ;;
  channels)
    curl -s http://localhost:8080/api/status | python3 -m json.tool 2>/dev/null || \
    curl -s http://localhost:8080/api/status
    ;;
  ip)
    IP=$(hostname -I | awk '{print $1}')
    echo "PiTV OS accessible sur : http://${IP}:8080"
    ;;
  *)
    echo "Usage: pitv {start|stop|restart|status|logs|kiosk-logs|update|channels|ip}"
    ;;
esac
MGMT
chmod +x /usr/local/bin/pitv
ok "Commande 'pitv' disponible"

# ─── 19. RÉSUMÉ FINAL ─────────────────────────────────────────────────────────
echo ""
hr
echo -e "\n  ${GREEN}${BOLD}✓ PiTV OS installé avec succès !${NC}\n"
hr

IP=$(hostname -I | awk '{print $1}')
echo -e "  ${BOLD}Accès local :${NC}    ${CYAN}http://127.0.0.1:${PORT}${NC}"
echo -e "  ${BOLD}Accès réseau :${NC}   ${CYAN}http://${IP}:${PORT}${NC}"
echo ""
echo -e "  ${BOLD}Commandes utiles :${NC}"
echo -e "  ${DIM}pitv start${NC}    — Démarrer PiTV OS"
echo -e "  ${DIM}pitv stop${NC}     — Arrêter"
echo -e "  ${DIM}pitv restart${NC}  — Redémarrer"
echo -e "  ${DIM}pitv logs${NC}     — Voir les logs"
echo -e "  ${DIM}pitv status${NC}   — État des services"
echo -e "  ${DIM}pitv ip${NC}       — Adresse réseau"
echo ""
echo -e "  ${BOLD}Sources IPTV :${NC}"
echo -e "  ${DIM}https://iptv-org.github.io/iptv/index.m3u${NC}"
echo ""

hr
echo -ne "\n  ${YELLOW}Voulez-vous redémarrer maintenant ?${NC} [O/n] "
read -r ans
case $ans in
  n|N|non|no)
    echo -e "  ${CYAN}Redémarrez manuellement avec : sudo reboot${NC}"
    echo -e "  ${CYAN}PiTV OS démarrera automatiquement.${NC}"
    ;;
  *)
    echo -e "  ${GREEN}Redémarrage dans 5 secondes...${NC}"
    sleep 5
    reboot
    ;;
esac
