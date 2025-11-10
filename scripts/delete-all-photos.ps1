[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $false, HelpMessage = 'Device serial or IP:PORT to target a specific device')]
    [string]$Device,

    [Parameter(Mandatory = $false, HelpMessage = 'Skip confirmation prompt')]
    [switch]$Force,

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
}

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) {
    throw 'PSScriptRoot is not available. Please run this script from a file, not via stdin.'
}
$repoRoot = Split-Path -Parent $scriptRoot
if (-not (Test-Path -LiteralPath $repoRoot)) {
    throw "Repository root '$repoRoot' not found."
}

$targetDescription = if ($Device) { "อุปกรณ์ $Device" } else { 'อุปกรณ์ที่เชื่อมต่ออยู่' }
if (-not $PSCmdlet.ShouldProcess($targetDescription, 'ลบรูปภาพทั้งหมดจากอุปกรณ์')) {
    Write-Host '[info] ยกเลิกการลบรูปภาพ.' -ForegroundColor Yellow
    return
}

if (-not $Force) {
    $warning = "การทำงานนี้จะลบรูปภาพทั้งหมดจาก $targetDescription (เช่น DCIM/Camera, DCIM/Screenshots, Pictures/Screenshots)"
    if (-not $PSCmdlet.ShouldContinue($warning, 'ยืนยันการลบรูปภาพทั้งหมดหรือไม่?')) {
        Write-Host '[info] ยกเลิกการลบรูปภาพ.' -ForegroundColor Yellow
        return
    }
}

$deleteTargets = @('/sdcard/DCIM/Camera', '/sdcard/DCIM/Screenshots', '/sdcard/Pictures/Screenshots')
$deleteTargetsValue = [string]::Join(' ', $deleteTargets)

$innerScript = @'
set -eu
set -o pipefail 2>/dev/null || true

device_arg="${DEVICE_ARG:-}"
delete_targets="${DELETE_TARGETS:-/sdcard/DCIM/Camera /sdcard/DCIM/Screenshots /sdcard/Pictures/Screenshots}"

if [ -z "$device_arg" ]; then
  device_arg=$(adb devices | awk '$2 == "device" {print $1; exit}')
fi

if [ -z "$device_arg" ]; then
  mdns_target=$(adb mdns services 2>/dev/null | awk '/_adb-tls-connect._tcp\./ {print $1; exit}')
  if [ -n "$mdns_target" ]; then
    echo "[info] ตรวจพบอุปกรณ์ผ่าน mDNS: $mdns_target" >&2
    adb connect "$mdns_target" || true
    device_arg=$(adb devices | awk '$2 == "device" {print $1; exit}')
  fi
fi

if [ -z "$device_arg" ]; then
  echo "[error] ไม่พบอุปกรณ์ที่สถานะพร้อมใช้งาน (device). ใช้ --device <serial|ip:port>." >&2
  exit 1
fi

if ! adb devices | awk '$2 == "device" {print $1}' | grep -qx "$device_arg"; then
  case "$device_arg" in
    *:*)
      echo "[info] เชื่อมต่อไปยัง $device_arg ..." >&2
      adb connect "$device_arg" || true
      ;;
  esac
fi

if ! adb devices | awk '$2 == "device" {print $1}' | grep -qx "$device_arg"; then
  echo "[error] อุปกรณ์ $device_arg ยังไม่พร้อม (status != device)." >&2
  exit 1
fi

deleted_any=0
for target in $delete_targets; do
  [ -n "$target" ] || continue
  escaped_target=$(printf '%s\n' "$target" | sed 's/"/\\"/g')
  if adb -s "$device_arg" shell "if [ -d \"$escaped_target\" ]; then exit 0; else exit 1; fi" >/dev/null 2>&1; then
    echo "[info] ลบข้อมูลใน $target" >&2
    if adb -s "$device_arg" shell "rm -rf \"$escaped_target\"" >/dev/null 2>&1; then
      adb -s "$device_arg" shell "mkdir -p \"$escaped_target\"" >/dev/null 2>&1 || true
      deleted_any=1
    else
      echo "[warn] ไม่สามารถลบ $target ได้" >&2
    fi
  else
    echo "[info] ข้าม $target (ไม่พบโฟลเดอร์)" >&2
  fi
done

if [ "$deleted_any" -eq 0 ]; then
  echo "[warn] ไม่พบโฟลเดอร์รูปภาพสำหรับลบ" >&2
  exit 0
fi

echo "[info] ลบรูปภาพทั้งหมดเสร็จสิ้น" >&2
'@

$innerScript = $innerScript.Replace("`r`n", "`n").Replace("`r", "`n")
$innerScriptBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($innerScript))

$envArguments = @('--env', "ADB_INNER_SCRIPT=$innerScriptBase64", '--env', "DELETE_TARGETS=$deleteTargetsValue")
if ($Device) {
    $envArguments += @('--env', "DEVICE_ARG=$Device")
}

Push-Location -LiteralPath $repoRoot
try {
    $composeArgs = @('exec', '-T') + $envArguments + @('controller', 'bash', '-lc', 'printf ''%s'' "$ADB_INNER_SCRIPT" | base64 -d | bash')
    Invoke-DockerCompose -Arguments $composeArgs -VerboseLog:$VerboseLog
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Docker Compose command exited with code $exitCode"
    }
}
finally {
    Pop-Location
}

Write-Host '✅ ลบรูปภาพทั้งหมดเรียบร้อยแล้ว'