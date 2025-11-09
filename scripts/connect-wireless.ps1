param(
    [Parameter(Mandatory = $false, HelpMessage = 'Specify IP or IP:PORT to force connecting to a specific device')]
    [string]$Device,

    [Parameter(Mandatory = $false, HelpMessage = 'Pair with the device before connecting, e.g. 10.1.1.242:39191')]
    [string]$PairingAddress,

    [Parameter(Mandatory = $false, HelpMessage = 'Pairing port when the IP is provided without a port')]
    [int]$PairingPort,

    [Parameter(Mandatory = $false, HelpMessage = 'Pairing code shown on the device (required when Pairing address is provided)')]
    [string]$PairingCode,

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
@@ -48,154 +48,154 @@ function Invoke-DockerCompose {
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

$pairTarget = $null
if ($PairingAddress -or $PairingPort -or $PairingCode) {
    if (-not $PairingAddress) {
        throw 'You must specify -PairingAddress when using pairing options (e.g. 10.1.1.242 or 10.1.1.242:39191).'
    }

    if (-not $PairingCode) {
        throw 'You must specify -PairingCode together with -PairingAddress to pair automatically.'
    }

    $pairTarget = $PairingAddress
    if ($PairingPort -and ($PairingAddress -notmatch ':')) {
        $pairTarget = "$PairingAddress`:$PairingPort"
    }

    if ($PairingPort -and ($PairingAddress -match ':')) {
        Write-Warning 'Ignoring -PairingPort because -PairingAddress already contains a port.'
    }
}

Push-Location -LiteralPath $repoRoot
try {
    $innerScript = @'
set -eu
set -o pipefail 2>/dev/null || true

device_filter="${DEVICE_FILTER:-}"
allow_multiple="${ALLOW_MULTIPLE:-0}"
pair_target="${PAIR_TARGET:-}"
pair_code="${PAIR_CODE:-}"

if [ -n "$pair_target" ]; then␊
  if [ -z "$pair_code" ]; then␊
    echo "[error] Pairing code is required when using a Pairing address" >&2
    exit 1
  fi

  echo "[info] Pairing with $pair_target" >&2
  if ! adb pair "$pair_target" "$pair_code"; then␊
    echo "[error] Pairing failed. Check the code and port and try again" >&2
    exit 1
  fi
fi

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
      echo "[warn] Using adb_known_hosts history instead of mDNS." >&2
      mdns_candidates="$fallback_candidates"
    fi
  fi
fi

if [ -z "$mdns_candidates" ] && [ -n "$device_filter" ]; then
  # Fall back to the provided device if mDNS lookup did not find it
  mdns_candidates="$device_filter"
fi

if [ -z "$mdns_candidates" ]; then␊
  echo "[error] No wireless devices found via mDNS (_adb-tls-connect)." >&2
  echo "[hint] Ensure Wireless debugging is enabled or provide -Device <IP:PORT>" >&2
  exit 1
fi

connected=0
for target in $mdns_candidates; do␊
  [ -n "$target" ] || continue␊
  echo "[info] Attempting to connect to $target" >&2
  if adb connect "$target"; then
    connected=$((connected + 1))
    if [ "$allow_multiple" != "1" ]; then
      break
    fi
  else␊
    echo "[warn] Failed to connect to $target" >&2
  fi
done

if [ "$connected" -eq 0 ]; then␊
  echo "[error] Unable to connect to any devices" >&2
  exit 1
fi

echo "[info] Current device list:" >&2
adb devices -l
'@

    $innerScript = $innerScript.Replace("`r`n", "`n").Replace("`r", "`n")
    $innerScriptBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($innerScript))

    $envArguments = @('--env', "ADB_INNER_SCRIPT=$innerScriptBase64")

    if ($Device) {
        $envArguments += @('--env', "DEVICE_FILTER=$Device")
    }

    if ($pairTarget) {
        $envArguments += @('--env', "PAIR_TARGET=$pairTarget")
        $envArguments += @('--env', "PAIR_CODE=$PairingCode")
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