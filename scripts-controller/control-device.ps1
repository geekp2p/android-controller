<#+
.SYNOPSIS
    Helper script to control an Android device via adb.

.DESCRIPTION
    Provides simple commands for taps, swipes, and key events using adb.

.EXAMPLE
    # Swipe from left to right on the default device
    .\control-device.ps1 -Action Swipe -X 200 -Y 1000 -X2 900 -Y2 1000 -Duration 300

.EXAMPLE
    # Send the HOME key event to a specific device
    .\control-device.ps1 -Action Key -KeyName HOME -Serial emulator-5554

.NOTES
    Requires adb to be available in PATH.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Tap", "Swipe", "Key")]
    [string]$Action,

    [Parameter()]
    [int]$X,

    [Parameter()]
    [int]$Y,

    [Parameter()]
    [int]$X2,

    [Parameter()]
    [int]$Y2,

    [Parameter()]
    [int]$Duration = 300,

    [Parameter()]
    [int]$Keycode,

    [Parameter()]
    [string]$KeyName,

    [Parameter()]
    [string]$Serial
)

function Invoke-AdbCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $adbArgs = @()
    if ($Serial) {
        $adbArgs += "-s"
        $adbArgs += $Serial
    }

    $adbArgs += $Arguments

    & adb @adbArgs
    if ($LASTEXITCODE -ne 0) {
        throw "adb exited with code $LASTEXITCODE"
    }
}

switch ($Action) {
    "Tap" {
        if ($PSBoundParameters.ContainsKey("X") -and $PSBoundParameters.ContainsKey("Y")) {
            Invoke-AdbCommand -Arguments @("shell", "input", "tap", $X, $Y)
        } else {
            throw "Tap action requires -X and -Y parameters."
        }
    }
    "Swipe" {
        $required = @("X", "Y", "X2", "Y2")
        foreach ($paramName in $required) {
            if (-not $PSBoundParameters.ContainsKey($paramName)) {
                throw "Swipe action requires -X, -Y, -X2, and -Y2 parameters."
            }
        }

        Invoke-AdbCommand -Arguments @("shell", "input", "swipe", $X, $Y, $X2, $Y2, $Duration)
    }
    "Key" {
        if ($PSBoundParameters.ContainsKey("Keycode")) {
            Invoke-AdbCommand -Arguments @("shell", "input", "keyevent", $Keycode)
        } elseif ($PSBoundParameters.ContainsKey("KeyName")) {
            Invoke-AdbCommand -Arguments @("shell", "input", "keyevent", $KeyName)
        } else {
            throw "Key action requires either -Keycode or -KeyName."
        }
    }
    default {
        throw "Unsupported action: $Action"
    }
}

Write-Host "Command completed successfully." -ForegroundColor Green