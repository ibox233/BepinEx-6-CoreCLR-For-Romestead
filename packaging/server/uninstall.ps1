$ErrorActionPreference = "Stop"

$RuntimeConfigName = "Server.runtimeconfig.json"

function Get-ServerRoot {
    $scriptRoot = $PSScriptRoot

    if (Test-Path -LiteralPath (Join-Path $scriptRoot $RuntimeConfigName)) {
        return $scriptRoot
    }

    $parent = Split-Path -Parent $scriptRoot
    if (Test-Path -LiteralPath (Join-Path $parent $RuntimeConfigName)) {
        return $parent
    }

    throw "$RuntimeConfigName was not found. Run uninstall.ps1 from the dedicated server directory or from the extracted package directory."
}

$serverRoot = Get-ServerRoot
$runtimeConfig = Join-Path $serverRoot $RuntimeConfigName
$backup = "$runtimeConfig.bepinex-backup"

if (Test-Path -LiteralPath $backup) {
    Copy-Item -LiteralPath $backup -Destination $runtimeConfig -Force
    Write-Host "Runtime config restored from: $backup"
} else {
    $json = Get-Content -LiteralPath $runtimeConfig -Raw | ConvertFrom-Json
    $properties = $json.runtimeOptions.configProperties

    if ($null -ne $properties -and $properties.PSObject.Properties.Name -contains "STARTUP_HOOKS") {
        $hookValue = [string] $properties.STARTUP_HOOKS
        if ($hookValue.EndsWith("BepInEx.NET.CoreCLR.dll", [System.StringComparison]::OrdinalIgnoreCase)) {
            $properties.PSObject.Properties.Remove("STARTUP_HOOKS")
            $json | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $runtimeConfig -Encoding UTF8
            Write-Host "Startup hook removed from runtime config."
        } else {
            Write-Host "STARTUP_HOOKS points to another loader; runtime config was left unchanged."
        }
    } else {
        Write-Host "No STARTUP_HOOKS entry found."
    }
}

Remove-Item -LiteralPath (Join-Path $serverRoot "BepInEx.NET.CoreCLR.dll") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $serverRoot "BepInEx.NET.CoreCLR.deps.json") -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Loader hook removed. The BepInEx folder was kept so server plugins/configs are not deleted."
