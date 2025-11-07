param(
    [Parameter(Mandatory = $false)]
    [string]$Device,
    [switch]$VerboseLog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-DockerCompose {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$VerboseLog
    )

    $composeCommand = $null
    $commandArguments = $Arguments

    $dockerCommand = Get-Command -Name 'docker' -ErrorAction SilentlyContinue
    if ($dockerCommand) {
        & docker @('compose', 'version') *> $null
        if ($LASTEXITCODE -eq 0) {
            $composeCommand = 'docker'
            $commandArguments = @('compose') + $Arguments
        }
    }

    if (-not $composeCommand) {
        $dockerComposeCommand = Get-Command -Name 'docker-compose' -ErrorAction SilentlyContinue
        if ($dockerComposeCommand) {
            $composeCommand = 'docker-compose'
            $commandArguments = $Arguments
        }
    }

    if (-not $composeCommand) {
        throw 'Neither "docker compose" nor "docker-compose" is available on PATH. Install Docker with Compose support.'
    }

    if ($VerboseLog) {
        Write-Host "Using compose command: $composeCommand $($commandArguments -join ' ')" -ForegroundColor Yellow
    }

    & $composeCommand @commandArguments
    return $LASTEXITCODE
}

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
set -eu
set -o pipefail 2>/dev/null || true

if [ ! -d /img ]; then
  echo "[error] /img mount is missing. Check docker-compose volumes." >&2
  exit 1
fi

if [ -z "${DEVICE_ARG:-}" ]; then
  DEVICE_ARG=$(adb devices | awk '$2 == "device" {{print $1; exit}}')
fi

if [ -z "${DEVICE_ARG:-}" ]; then
  echo "[error] ไม่พบอุปกรณ์ที่สถานะพร้อมใช้งาน (device). ใช้พารามิเตอร์ --device <serial|ip:port>." >&2
  exit 1
fi

if ! adb devices | awk '$2 == "device" {{print $1}}' | grep -qx "$DEVICE_ARG"; then
  case "$DEVICE_ARG" in
    *:*)
      echo "[info] เชื่อมต่อไปยัง $DEVICE_ARG ..." >&2
      adb connect "$DEVICE_ARG" || true
      ;;
  esac
fi

if ! adb devices | awk '$2 == "device" {{print $1}}' | grep -qx "$DEVICE_ARG"; then
  echo "[error] อุปกรณ์ $DEVICE_ARG ยังไม่พร้อม (status != device)." >&2
  exit 1
fi

TARGET="/img/__FILENAME__"
adb -s "$DEVICE_ARG" exec-out screencap -p > "$TARGET"
if [ ! -s "$TARGET" ]; then
  echo "[error] ไม่สามารถบันทึกภาพหน้าจอได้" >&2
  exit 1
fi
ls -lh "$TARGET"
'@
$innerScript = $innerScriptTemplate.Replace('__FILENAME__', $fileName)
$innerScript = $innerScript.Replace("`r`n", "`n").Replace("`r", "`n")

if ($VerboseLog) {
    Write-Host "ADB inner script:" -ForegroundColor Cyan
    Write-Host $innerScript
    Write-Host "Passing device argument to container: '$deviceArg'"
}

Push-Location -LiteralPath $repoRoot
try {
    $composeArgs = @('exec', '-T', '--env', "DEVICE_ARG=$deviceArg", 'controller', 'bash', '-lc', $innerScript)
    $exitCode = Invoke-DockerCompose -Arguments $composeArgs -VerboseLog:$VerboseLog
    if ($exitCode -ne 0) {
        throw "Docker Compose command exited with code $exitCode"
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
