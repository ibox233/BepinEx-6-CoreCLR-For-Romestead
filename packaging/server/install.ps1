$ErrorActionPreference = "Stop"

$RuntimeConfigName = "Server.runtimeconfig.json"
$ServerExeName = "Server.exe"
$ServerDllName = "Server.dll"

function Get-ServerRoot {
    $scriptRoot = $PSScriptRoot

    if (Test-Path -LiteralPath (Join-Path $scriptRoot $RuntimeConfigName)) {
        return $scriptRoot
    }

    throw "$RuntimeConfigName was not found. Extract the contents of this archive directly into the Romestead dedicated server directory, then run install.bat again."
}

function Set-StartupHook {
    param(
        [string] $ServerRoot
    )

    $runtimeConfig = Join-Path $ServerRoot $RuntimeConfigName
    $serverExe = Join-Path $ServerRoot $ServerExeName
    $serverDll = Join-Path $ServerRoot $ServerDllName
    $loaderPath = Join-Path $ServerRoot "BepInEx.NET.CoreCLR.dll"
    $loaderDepsPath = Join-Path $ServerRoot "BepInEx.NET.CoreCLR.deps.json"
    $corePath = Join-Path $ServerRoot "BepInEx\core\BepInEx.Core.dll"

    if (-not (Test-Path -LiteralPath $serverExe) -and -not (Test-Path -LiteralPath $serverDll)) {
        throw "Server executable files were not found. Expected $ServerExeName or $ServerDllName in: $ServerRoot"
    }

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

$serverRoot = Get-ServerRoot
Set-StartupHook -ServerRoot $serverRoot

Write-Host ""
Write-Host "Romestead Server BepInEx mod loader installed."
