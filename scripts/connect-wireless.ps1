param(
    [Parameter(Mandatory = $false, HelpMessage = 'ระบุ IP หรือ IP:PORT เพื่อบังคับเชื่อมต่ออุปกรณ์เฉพาะ')]
    [string]$Device,

    [switch]$AllowMultiple,

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

Push-Location -LiteralPath $repoRoot
try {
    $innerScript = @'
set -eu
set -o pipefail 2>/dev/null || true

device_filter="${DEVICE_FILTER:-}"
allow_multiple="${ALLOW_MULTIPLE:-0}"

if [ -n "$device_filter" ] && ! printf '%s' "$device_filter" | grep -q ':'; then
  # If only IP is provided, search for matching IP from mDNS discovery
  mdns_candidates=$(adb mdns services 2>/dev/null | awk '/_adb-tls-connect._tcp\./ {print $1}' | grep -F "$device_filter:" || true)
else
  mdns_candidates=$(adb mdns services 2>/dev/null | awk '/_adb-tls-connect._tcp\./ {print $1}' || true)
  if [ -n "$device_filter" ]; then
    # Filter the discovered list to the requested host:port when provided
    mdns_candidates=$(printf '%s\n' "$mdns_candidates" | grep -F "$device_filter" || true)
  fi
fi

if [ -z "$mdns_candidates" ]; then
  known_hosts_file="$HOME/.android/adb_known_hosts"
  if [ -f "$known_hosts_file" ]; then
    if [ -n "$device_filter" ]; then
      if printf '%s' "$device_filter" | grep -q ':'; then
        fallback_candidates=$(awk '{print $1}' "$known_hosts_file" | grep -F "$device_filter" || true)
      else
        fallback_candidates=$(awk '{print $1}' "$known_hosts_file" | grep -E "^$device_filter:[0-9]+$" || true)
      fi
    else
      fallback_candidates=$(awk '{print $1}' "$known_hosts_file" | grep -E ':[0-9]+$' || true)
    fi

    fallback_candidates=$(printf '%s\n' "$fallback_candidates" | grep -v '^$' | sort -u)
    if [ -n "$fallback_candidates" ]; then
      echo "[warn] ใช้ประวัติจาก adb_known_hosts แทน mDNS." >&2
      mdns_candidates="$fallback_candidates"
    fi
  fi
fi

if [ -z "$mdns_candidates" ] && [ -n "$device_filter" ]; then
  # Fall back to the provided device if mDNS lookup did not find it
  mdns_candidates="$device_filter"
fi

if [ -z "$mdns_candidates" ]; then
  echo "[error] ไม่พบอุปกรณ์แบบ wireless ผ่าน mDNS (_adb-tls-connect)." >&2
  echo "[hint] ตรวจสอบว่าเปิด Wireless debugging แล้ว หรือระบุ -Device <IP:PORT>" >&2
  exit 1
fi

connected=0
for target in $mdns_candidates; do
  [ -n "$target" ] || continue
  echo "[info] พยายามเชื่อมต่อไปยัง $target" >&2
  if adb connect "$target"; then
    connected=$((connected + 1))
    if [ "$allow_multiple" != "1" ]; then
      break
    fi
  else
    echo "[warn] เชื่อมต่อ $target ไม่สำเร็จ" >&2
  fi
done

if [ "$connected" -eq 0 ]; then
  echo "[error] ไม่สามารถเชื่อมต่ออุปกรณ์ใด ๆ ได้" >&2
  exit 1
fi

echo "[info] รายการอุปกรณ์ปัจจุบัน:" >&2
adb devices -l
'@

    $innerScript = $innerScript.Replace("`r`n", "`n").Replace("`r", "`n")
    $innerScriptBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($innerScript))

    $envArguments = @('--env', "ADB_INNER_SCRIPT=$innerScriptBase64")

    if ($Device) {
        $envArguments += @('--env', "DEVICE_FILTER=$Device")
    }

    if ($AllowMultiple) {
        $envArguments += @('--env', 'ALLOW_MULTIPLE=1')
    }

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