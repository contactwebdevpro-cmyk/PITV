# ╔══════════════════════════════════════════════════════════════╗
# ║          PiTV OS - Script d'Installation Windows v1.1       ║
# ║  Compatible : Windows 10/11 x64                             ║
# ║  Nécessite : PowerShell 5+ en Administrateur                ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage :
#   Set-ExecutionPolicy Bypass -Scope Process
#   .\install.ps1
#
# Installe :
#   - Node.js LTS (via winget ou téléchargement direct)
#   - Le serveur PiTV OS
#   - Une tâche planifiée pour démarrer au boot
#   - Ouvre l'interface dans le navigateur par défaut

param(
    [int]$Port = 8080,
    [string]$InstallDir = "$env:ProgramFiles\PiTV",
    [switch]$NoKiosk = $false,
    [switch]$Uninstall = $false
)

$ErrorActionPreference = "Stop"
$ScriptVersion = "1.1.0"

# ─── Couleurs ─────────────────────────────────────────────────────────────────
function Write-Step  { param($msg) Write-Host "`n  [>] $msg" -ForegroundColor Cyan }
function Write-OK    { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  [!!] $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "  [ERR] $msg" -ForegroundColor Red; exit 1 }
function Write-Info  { param($msg) Write-Host "  [i]  $msg" -ForegroundColor Gray }

# ─── Bannière ─────────────────────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "  ██████╗ ██╗    ████████╗██╗   ██╗" -ForegroundColor Cyan
Write-Host "  ██╔══██╗██║       ██╔══╝╚██╗ ██╔╝" -ForegroundColor Cyan
Write-Host "  ██████╔╝██║       ██║    ╚████╔╝ " -ForegroundColor Cyan
Write-Host "  ██╔═══╝ ██║       ██║    ██╔═██╗ " -ForegroundColor Cyan
Write-Host "  ██║     ██║       ██║   ██╔╝ ╚██╗" -ForegroundColor Cyan
Write-Host "  ╚═╝     ╚═╝       ╚═╝   ╚═╝   ╚═╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  PiTV OS — Windows Installer v$ScriptVersion" -ForegroundColor DarkGray
Write-Host "  IPTV Player pour Raspberry Pi, Windows et Linux" -ForegroundColor DarkGray
Write-Host ""

# ─── Désinstallation ──────────────────────────────────────────────────────────
if ($Uninstall) {
    Write-Step "Désinstallation de PiTV OS"
    Stop-ScheduledTask -TaskName "PiTV OS" -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName "PiTV OS" -Confirm:$false -ErrorAction SilentlyContinue
    if (Test-Path $InstallDir) {
        Remove-Item -Recurse -Force $InstallDir
        Write-OK "Répertoire supprimé : $InstallDir"
    }
    Write-OK "PiTV OS désinstallé"
    exit 0
}

# ─── Vérification admin ───────────────────────────────────────────────────────
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "Ce script doit être exécuté en tant qu'Administrateur.
    Clic droit sur PowerShell -> Exécuter en tant qu'administrateur"
}

# ─── Vérification OS ──────────────────────────────────────────────────────────
Write-Step "Vérification du système"
$os = Get-CimInstance Win32_OperatingSystem
Write-OK "OS : $($os.Caption) — Architecture : $($os.OSArchitecture)"
if ([System.Version]$os.Version -lt [System.Version]"10.0") {
    Write-Err "Windows 10 ou supérieur requis."
}

# ─── Résumé ───────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Résumé de l'installation :" -ForegroundColor White
Write-Host "  • Répertoire : $InstallDir" -ForegroundColor Cyan
Write-Host "  • Port serveur : $Port" -ForegroundColor Cyan
Write-Host "  • Mode kiosque : $(-not $NoKiosk)" -ForegroundColor Cyan
Write-Host "  • Node.js LTS + npm" -ForegroundColor Cyan
Write-Host ""
$confirm = Read-Host "  Continuer ? [O/n]"
if ($confirm -match '^[nN]') { Write-Host "  Annulé."; exit 0 }

# ─── 1. Node.js ───────────────────────────────────────────────────────────────
Write-Step "Vérification de Node.js"
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
if ($nodeCmd) {
    $nodeVer = node --version
    Write-OK "Node.js $nodeVer déjà installé"
} else {
    Write-Info "Installation de Node.js LTS..."

    # Essaie winget en premier (Windows 11 / Win10 récent)
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        try {
            winget install --id OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements
            Write-OK "Node.js installé via winget"
        } catch {
            Write-Warn "winget a échoué — téléchargement direct..."
            $nodeCmd = $null
        }
    }

    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        # Téléchargement direct du MSI Node.js LTS
        $nodeUrl = "https://nodejs.org/dist/lts/node-lts-x64.msi"
        $nodeMsi = "$env:TEMP\node-lts.msi"
        Write-Info "Téléchargement de Node.js LTS..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://nodejs.org/dist/latest-lts/node-v20.11.0-x64.msi" -OutFile $nodeMsi
        Start-Process msiexec.exe -ArgumentList "/i `"$nodeMsi`" /quiet /norestart" -Wait
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-OK "Node.js installé"
        Remove-Item $nodeMsi -ErrorAction SilentlyContinue
    }
}

# Vérifie npm
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if (-not $npmCmd) {
    Write-Err "npm introuvable après installation de Node.js. Redémarrez PowerShell et relancez."
}
Write-OK "npm $(npm --version) disponible"

# ─── 2. Répertoire d'installation ─────────────────────────────────────────────
Write-Step "Création du répertoire $InstallDir"
New-Item -ItemType Directory -Force -Path "$InstallDir\public" | Out-Null
New-Item -ItemType Directory -Force -Path "$InstallDir\logs" | Out-Null
Write-OK "Répertoire créé"

# ─── 3. Copie des fichiers ────────────────────────────────────────────────────
Write-Step "Copie des fichiers de l'application"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (Test-Path "$ScriptDir\server.js") {
    Copy-Item "$ScriptDir\server.js" "$InstallDir\" -Force
    Copy-Item "$ScriptDir\package.json" "$InstallDir\" -Force
    if (Test-Path "$ScriptDir\public") {
        Copy-Item "$ScriptDir\public\*" "$InstallDir\public\" -Recurse -Force
    }
    Write-OK "Fichiers copiés"
} else {
    Write-Warn "server.js introuvable — le fichier index.html seul sera copié"
    if (Test-Path "$ScriptDir\index.html") {
        Copy-Item "$ScriptDir\index.html" "$InstallDir\public\" -Force
        Write-OK "index.html copié dans $InstallDir\public\"
    } else {
        Write-Err "Aucun fichier source trouvé. Placez les fichiers du projet dans le même dossier que install.ps1"
    }
}

# ─── 4. Dépendances npm ───────────────────────────────────────────────────────
if (Test-Path "$InstallDir\package.json") {
    Write-Step "Installation des dépendances Node.js"
    Set-Location $InstallDir
    npm install --production 2>&1 | Select-Object -Last 5
    Write-OK "Dépendances installées"
}

# ─── 5. Variables d'environnement ─────────────────────────────────────────────
Write-Step "Configuration de l'environnement"
[Environment]::SetEnvironmentVariable("PORT", $Port, "Machine")
[Environment]::SetEnvironmentVariable("NODE_ENV", "production", "Machine")
Write-OK "Variables d'environnement définies (PORT=$Port)"

# ─── 6. Tâche planifiée (démarrage automatique) ───────────────────────────────
Write-Step "Création de la tâche planifiée (démarrage au boot)"

$nodePath = (Get-Command node).Source
$serverScript = if (Test-Path "$InstallDir\server.js") { "$InstallDir\server.js" } else { $null }

if ($serverScript) {
    $taskAction = New-ScheduledTaskAction `
        -Execute $nodePath `
        -Argument "`"$serverScript`"" `
        -WorkingDirectory $InstallDir

    $taskTrigger = New-ScheduledTaskTrigger -AtStartup

    $taskSettings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit ([TimeSpan]::Zero)

    $taskPrincipal = New-ScheduledTaskPrincipal `
        -UserId "SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest

    Register-ScheduledTask `
        -TaskName "PiTV OS" `
        -TaskPath "\PiTV" `
        -Action $taskAction `
        -Trigger $taskTrigger `
        -Settings $taskSettings `
        -Principal $taskPrincipal `
        -Description "PiTV OS — Serveur IPTV" `
        -Force | Out-Null

    Write-OK "Tâche planifiée créée (démarrage automatique au boot)"

    # Démarrer maintenant
    try {
        Start-ScheduledTask -TaskName "PiTV OS" -TaskPath "\PiTV"
        Write-OK "Serveur PiTV démarré"
        Start-Sleep -Seconds 2
    } catch {
        Write-Warn "Le serveur démarrera au prochain redémarrage"
    }
} else {
    Write-Warn "Pas de server.js — mode standalone uniquement (pas de tâche planifiée)"
}

# ─── 7. Règle pare-feu ───────────────────────────────────────────────────────
Write-Step "Ouverture du port $Port dans le pare-feu Windows"
New-NetFirewallRule `
    -DisplayName "PiTV OS" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort $Port `
    -Action Allow `
    -ErrorAction SilentlyContinue | Out-Null
Write-OK "Port $Port ouvert"

# ─── 8. Raccourci bureau ─────────────────────────────────────────────────────
Write-Step "Création du raccourci bureau"
$WshShell = New-Object -ComObject WScript.Shell
$shortcut = $WshShell.CreateShortcut("$env:PUBLIC\Desktop\PiTV OS.lnk")
if ($serverScript) {
    $shortcut.TargetPath = "http://localhost:$Port"
} else {
    $shortcut.TargetPath = "$InstallDir\public\index.html"
}
$shortcut.Description = "PiTV OS — IPTV Player"
$shortcut.Save()
Write-OK "Raccourci créé sur le bureau"

# ─── Résumé final ─────────────────────────────────────────────────────────────
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" } | Select-Object -First 1).IPAddress

Write-Host ""
Write-Host "  ════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  ✓ PiTV OS installé avec succès !" -ForegroundColor Green
Write-Host ""
Write-Host "  Accès local  : http://localhost:$Port" -ForegroundColor Cyan
if ($ip) {
    Write-Host "  Accès réseau : http://${ip}:${Port}" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "  Commandes utiles :" -ForegroundColor White
Write-Host "  Start-ScheduledTask -TaskName 'PiTV OS' -TaskPath '\PiTV'" -ForegroundColor DarkGray
Write-Host "  Stop-ScheduledTask  -TaskName 'PiTV OS' -TaskPath '\PiTV'" -ForegroundColor DarkGray
Write-Host "  .\install.ps1 -Uninstall   # Désinstaller" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  ════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ""

# Ouvrir le navigateur
$openBrowser = Read-Host "  Ouvrir PiTV OS dans le navigateur ? [O/n]"
if ($openBrowser -notmatch '^[nN]') {
    if ($serverScript) {
        Start-Process "http://localhost:$Port"
    } else {
        Start-Process "$InstallDir\public\index.html"
    }
}
