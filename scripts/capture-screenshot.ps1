param(
    [Parameter(Mandatory = $false)]
    [string]$Device,
    [switch]$VerboseLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) {
    throw 'PSScriptRoot is not available. Please run this script from a file, not via stdin.'
}
$repoRoot = Split-Path -Parent $scriptRoot
if (-not (Test-Path -LiteralPath $repoRoot)) {
    throw "Repository root '$repoRoot' not found."
}

$imgDir = Join-Path -Path $repoRoot -ChildPath 'img'
if (-not (Test-Path -LiteralPath $imgDir)) {
    New-Item -ItemType Directory -Path $imgDir -Force | Out-Null
}

$timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$fileName = "screen-$timestamp.png"

if ($VerboseLog) {
    Write-Host "Using repository root: $repoRoot"
    Write-Host "Saving screenshot to: $imgDir\$fileName"
}

$deviceArg = if ($Device) { $Device } else { '' }

$innerScriptTemplate = @'
set -euo pipefail

if [ ! -d /img ]; then
  echo "[error] /img mount is missing. Check docker-compose volumes." >&2
  exit 1
fi

DEVICE_ARG="{0}"
if [ -z "$DEVICE_ARG" ]; then
  DEVICE_ARG=$(adb devices | awk '$2 == "device" {print $1; exit}')
fi

if [ -z "$DEVICE_ARG" ]; then
  echo "[error] ไม่พบอุปกรณ์ที่สถานะพร้อมใช้งาน (device). ใช้พารามิเตอร์ --device <serial|ip:port>." >&2
  exit 1
fi

if ! adb devices | awk '$2 == "device" {print $1}' | grep -qx "$DEVICE_ARG"; then
  case "$DEVICE_ARG" in
    *:*)
      echo "[info] เชื่อมต่อไปยัง $DEVICE_ARG ..." >&2
      adb connect "$DEVICE_ARG" || true
      ;;
  esac
fi

if ! adb devices | awk '$2 == "device" {print $1}' | grep -qx "$DEVICE_ARG"; then
  echo "[error] อุปกรณ์ $DEVICE_ARG ยังไม่พร้อม (status != device)." >&2
  exit 1
fi

TARGET="/img/{1}"
adb -s "$DEVICE_ARG" exec-out screencap -p > "$TARGET"
ls -lh "$TARGET"
'@

$innerScript = [string]::Format($innerScriptTemplate, $deviceArg, $fileName)

if ($VerboseLog) {
    Write-Host "ADB inner script:" -ForegroundColor Cyan
    Write-Host $innerScript
}

$composeCommandTemplate = @'
set -euo pipefail
cat <<'EOF' >/tmp/adb-screencap.sh
{0}
EOF
bash /tmp/adb-screencap.sh
'@
$composeCommand = [string]::Format($composeCommandTemplate, $innerScript)

if ($VerboseLog) {
    Write-Host "Executing docker compose command..." -ForegroundColor Cyan
}

Push-Location -LiteralPath $repoRoot
try {
    $composeArgs = @('compose', 'exec', '-T', 'controller', 'bash', '-lc', $composeCommand)
    & docker @composeArgs
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "docker compose exec exited with code $exitCode"
    }
}
finally {
    Pop-Location
}

$hostPath = Join-Path -Path $imgDir -ChildPath $fileName
if (Test-Path -LiteralPath $hostPath) {
    Write-Host "✅ Screenshot saved to $hostPath"
} else {
    Write-Warning "Screenshot command finished but file not found at $hostPath"
}