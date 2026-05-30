$ErrorActionPreference = "Stop"

function Get-GameRoot {
    $scriptRoot = $PSScriptRoot

    if (Test-Path -LiteralPath (Join-Path $scriptRoot "Romestead.runtimeconfig.json")) {
        return $scriptRoot
    }

    $parent = Split-Path -Parent $scriptRoot
    if (Test-Path -LiteralPath (Join-Path $parent "Romestead.runtimeconfig.json")) {
        return $parent
    }

    throw "Romestead.runtimeconfig.json was not found. Run uninstall.ps1 from the game directory or from the extracted package directory."
}

$gameRoot = Get-GameRoot
$runtimeConfig = Join-Path $gameRoot "Romestead.runtimeconfig.json"
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

Remove-Item -LiteralPath (Join-Path $gameRoot "BepInEx.NET.CoreCLR.dll") -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $gameRoot "BepInEx.NET.CoreCLR.deps.json") -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Loader hook removed. The BepInEx folder was kept so user plugins/configs are not deleted."
