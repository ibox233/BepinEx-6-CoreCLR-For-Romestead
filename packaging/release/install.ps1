$ErrorActionPreference = "Stop"

function Get-GameRoot {
    $scriptRoot = $PSScriptRoot

    if (Test-Path -LiteralPath (Join-Path $scriptRoot "Romestead.runtimeconfig.json")) {
        return $scriptRoot
    }

    throw "Romestead.runtimeconfig.json was not found. Extract the contents of this archive directly into the Romestead game directory, then run install.bat again."
}

function Set-StartupHook {
    param(
        [string] $GameRoot
    )

    $runtimeConfig = Join-Path $GameRoot "Romestead.runtimeconfig.json"
    $loaderPath = Join-Path $GameRoot "BepInEx.NET.CoreCLR.dll"
    $loaderDepsPath = Join-Path $GameRoot "BepInEx.NET.CoreCLR.deps.json"
    $corePath = Join-Path $GameRoot "BepInEx\core\BepInEx.Core.dll"

    if (-not (Test-Path -LiteralPath $loaderPath)) {
        throw "Loader file is missing: $loaderPath"
    }

    if (-not (Test-Path -LiteralPath $loaderDepsPath)) {
        throw "Loader deps file is missing: $loaderDepsPath"
    }

    if (-not (Test-Path -LiteralPath $corePath)) {
        throw "BepInEx core files are missing: $corePath"
    }

    $backup = "$runtimeConfig.bepinex-backup"
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $runtimeConfig -Destination $backup -Force
        Write-Host "Backup created: $backup"
    }

    $json = Get-Content -LiteralPath $runtimeConfig -Raw | ConvertFrom-Json

    if ($null -eq $json.runtimeOptions) {
        $json | Add-Member -MemberType NoteProperty -Name runtimeOptions -Value ([pscustomobject]@{})
    }

    if ($null -eq $json.runtimeOptions.configProperties) {
        $json.runtimeOptions | Add-Member -MemberType NoteProperty -Name configProperties -Value ([pscustomobject]@{})
    }

    $properties = $json.runtimeOptions.configProperties
    $hookValue = (Resolve-Path -LiteralPath $loaderPath).Path

    if ($properties.PSObject.Properties.Name -contains "STARTUP_HOOKS") {
        $properties.STARTUP_HOOKS = $hookValue
    } else {
        $properties | Add-Member -MemberType NoteProperty -Name STARTUP_HOOKS -Value $hookValue
    }

    $json | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $runtimeConfig -Encoding UTF8
    Write-Host "Startup hook set to: $hookValue"
}

$gameRoot = Get-GameRoot
Set-StartupHook -GameRoot $gameRoot

Write-Host ""
Write-Host "Romestead BepInEx mod loader installed."
Write-Host "Launch the game through Steam."
