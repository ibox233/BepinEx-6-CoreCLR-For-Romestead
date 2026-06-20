param(
    [Parameter(Mandatory = $true)]
    [string] $PackagePath,

    [switch] $KeepTemp
)

$ErrorActionPreference = "Stop"

function Assert-FileExists {
    param(
        [string] $Path,
        [string] $Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description was not found: $Path"
    }
}

function Assert-LogContains {
    param(
        [string] $Log,
        [string] $Text
    )

    if ($Log.IndexOf($Text, [System.StringComparison]::Ordinal) -lt 0) {
        throw "Smoke test log did not contain expected text: $Text"
    }
}

function Assert-LogContainsExactlyOnce {
    param(
        [string] $Log,
        [string] $Text
    )

    $count = [System.Text.RegularExpressions.Regex]::Matches(
        $Log,
        [System.Text.RegularExpressions.Regex]::Escape($Text)
    ).Count

    if ($count -ne 1) {
        throw "Smoke test log expected '$Text' exactly once, but found $count occurrence(s)."
    }
}

function Assert-SmokeLog {
    param(
        [string] $Log
    )

    Assert-LogContains -Log $Log -Text "Preloader started"
    Assert-LogContains -Log $Log -Text "Preloader finished"
    Assert-LogContains -Log $Log -Text "Chainloader initialized"
    Assert-LogContains -Log $Log -Text "1 plugin to load"
    Assert-LogContains -Log $Log -Text "Loading [Smoke Test Plugin 1.0.0]"
    Assert-LogContains -Log $Log -Text "Smoke test plugin loaded"
    Assert-LogContains -Log $Log -Text "Chainloader startup complete"
    Assert-LogContainsExactlyOnce -Log $Log -Text "Preloader started"
    Assert-LogContainsExactlyOnce -Log $Log -Text "Chainloader initialized"
    Assert-LogContainsExactlyOnce -Log $Log -Text "1 plugin to load"
    Assert-LogContainsExactlyOnce -Log $Log -Text "Loading [Smoke Test Plugin 1.0.0]"
    Assert-LogContainsExactlyOnce -Log $Log -Text "Smoke test plugin loaded"
    Assert-LogContainsExactlyOnce -Log $Log -Text "Chainloader startup complete"

    $hasFatalPreloaderError = $Log.IndexOf("[Fatal  : Preloader]", [System.StringComparison]::Ordinal) -ge 0 -or
                              $Log.IndexOf("Unhandled fatal exception", [System.StringComparison]::Ordinal) -ge 0

    if ($hasFatalPreloaderError) {
        throw "Smoke test log contains a fatal preloader error."
    }
}

function Remove-SmokeDirectory {
    param(
        [string] $Path,
        [string] $AllowedRoot
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return
    }

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $resolvedRoot = (Resolve-Path -LiteralPath $AllowedRoot).Path

    if (-not $resolvedPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove smoke directory outside the smoke root: $resolvedPath"
    }

    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$resolvedPackagePath = (Resolve-Path -LiteralPath $PackagePath).Path
$artifactsRoot = Join-Path $repoRoot "artifacts"
$smokeRoot = Join-Path $artifactsRoot "smoke-test"
$testRoot = Join-Path $smokeRoot ([Guid]::NewGuid().ToString("N"))
$projectDir = Join-Path $testRoot "SmokeGame"
$pluginProjectDir = Join-Path $testRoot "SmokePlugin"
$duplicateEntrypointDir = Join-Path $testRoot "DuplicateEntrypoint"
$gameDir = Join-Path $testRoot "game"
$r2GameDir = Join-Path $testRoot "r2-game"
$r2ProfileDir = Join-Path $testRoot "r2-profile"

New-Item -ItemType Directory -Force -Path $smokeRoot | Out-Null
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null

try {
    New-Item -ItemType Directory -Force -Path $projectDir | Out-Null

    @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
</Project>
"@ | Set-Content -LiteralPath (Join-Path $projectDir "SmokeGame.csproj") -Encoding UTF8

    @"
using System.Reflection;
using System.Runtime.Loader;

Console.WriteLine("SmokeGame main reached");

var duplicateEntrypoint = Environment.GetEnvironmentVariable("BEPINEX_SMOKE_DUPLICATE_ENTRYPOINT");
if (!string.IsNullOrWhiteSpace(duplicateEntrypoint) && File.Exists(duplicateEntrypoint))
{
    var duplicateLoadContext = new AssemblyLoadContext("BepInExDuplicateEntrypointSmokeTest", isCollectible: true);
    var duplicateAssembly = duplicateLoadContext.LoadFromAssemblyPath(duplicateEntrypoint);
    var entrypointType = duplicateAssembly.GetType("BepInEx.NET.CoreCLR.NativeEntrypoint", throwOnError: true)!;
    var initialize = entrypointType.GetMethod("Initialize", BindingFlags.Public | BindingFlags.Static)!;
    initialize.Invoke(null, new object[] { IntPtr.Zero, 0 });
    Console.WriteLine("Duplicate BepInEx native entrypoint reached");
}
"@ | Set-Content -LiteralPath (Join-Path $projectDir "Program.cs") -Encoding UTF8

    dotnet publish (Join-Path $projectDir "SmokeGame.csproj") -c Release -f net8.0 --self-contained false -o $gameDir | Out-Null

    Expand-Archive -LiteralPath $resolvedPackagePath -DestinationPath $gameDir -Force

    $loaderPath = Join-Path $gameDir "BepInEx.NET.CoreCLR.dll"
    $d3d11HookPath = Join-Path $gameDir "d3d11.dll"
    $bepInExRoot = Join-Path $gameDir "BepInEx"
    $coreDir = Join-Path $bepInExRoot "core"
    $pluginsDir = Join-Path $bepInExRoot "plugins"
    $corePath = Join-Path $coreDir "BepInEx.Core.dll"
    $commonPath = Join-Path $coreDir "BepInEx.NET.Common.dll"
    $gameDll = Join-Path $gameDir "SmokeGame.dll"
    $logPath = Join-Path $bepInExRoot "LogOutput.log"
    $duplicateLoaderPath = Join-Path $duplicateEntrypointDir "BepInEx.NET.CoreCLR.dll"

    Assert-FileExists -Path $loaderPath -Description "Startup hook loader"
    Assert-FileExists -Path $corePath -Description "BepInEx core assembly"
    Assert-FileExists -Path $commonPath -Description "BepInEx .NET common assembly"
    Assert-FileExists -Path $gameDll -Description "Smoke game assembly"

    Assert-FileExists -Path $d3d11HookPath -Description "Client d3d11 hook"

    New-Item -ItemType Directory -Force -Path $duplicateEntrypointDir | Out-Null
    Copy-Item -LiteralPath $loaderPath -Destination $duplicateLoaderPath -Force

    New-Item -ItemType Directory -Force -Path $pluginProjectDir | Out-Null
    New-Item -ItemType Directory -Force -Path $pluginsDir | Out-Null

    @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <CopyLocalLockFileAssemblies>false</CopyLocalLockFileAssemblies>
  </PropertyGroup>
  <ItemGroup>
    <Reference Include="BepInEx.Core">
      <HintPath>$corePath</HintPath>
      <Private>false</Private>
    </Reference>
    <Reference Include="BepInEx.NET.Common">
      <HintPath>$commonPath</HintPath>
      <Private>false</Private>
    </Reference>
  </ItemGroup>
</Project>
"@ | Set-Content -LiteralPath (Join-Path $pluginProjectDir "SmokePlugin.csproj") -Encoding UTF8

    @"
using BepInEx;
using BepInEx.NET.Common;

[BepInPlugin("romestead.bepinex.smoketest", "Smoke Test Plugin", "1.0.0")]
public sealed class SmokePlugin : BasePlugin
{
    public override void Load()
    {
        Log.LogInfo("Smoke test plugin loaded");
    }
}
"@ | Set-Content -LiteralPath (Join-Path $pluginProjectDir "SmokePlugin.cs") -Encoding UTF8

    dotnet publish (Join-Path $pluginProjectDir "SmokePlugin.csproj") -c Release -f net8.0 -o $pluginsDir | Out-Null
    Assert-FileExists -Path (Join-Path $pluginsDir "SmokePlugin.dll") -Description "Smoke plugin assembly"

    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

    $previousStartupHooks = [Environment]::GetEnvironmentVariable("DOTNET_STARTUP_HOOKS", "Process")
    $previousDuplicateEntrypoint = [Environment]::GetEnvironmentVariable("BEPINEX_SMOKE_DUPLICATE_ENTRYPOINT", "Process")
    [Environment]::SetEnvironmentVariable("DOTNET_STARTUP_HOOKS", (Resolve-Path -LiteralPath $loaderPath).Path, "Process")
    [Environment]::SetEnvironmentVariable("BEPINEX_SMOKE_DUPLICATE_ENTRYPOINT", (Resolve-Path -LiteralPath $duplicateLoaderPath).Path, "Process")

    try {
        & dotnet $gameDll | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Smoke game exited with code $LASTEXITCODE"
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable("DOTNET_STARTUP_HOOKS", $previousStartupHooks, "Process")
        [Environment]::SetEnvironmentVariable("BEPINEX_SMOKE_DUPLICATE_ENTRYPOINT", $previousDuplicateEntrypoint, "Process")
    }

    Assert-FileExists -Path $logPath -Description "BepInEx disk log"
    $log = Get-Content -LiteralPath $logPath -Raw

    Write-Host "----- Smoke test BepInEx log -----"
    Write-Host $log.TrimEnd()
    Write-Host "----- End smoke test BepInEx log -----"

    Assert-SmokeLog -Log $log

    dotnet publish (Join-Path $projectDir "SmokeGame.csproj") -c Release -f net8.0 --self-contained false -o $r2GameDir | Out-Null
    Expand-Archive -LiteralPath $resolvedPackagePath -DestinationPath $r2ProfileDir -Force

    $r2RootLoaderPath = Join-Path $r2ProfileDir "BepInEx.NET.CoreCLR.dll"
    $r2D3d11HookPath = Join-Path $r2ProfileDir "d3d11.dll"
    $r2BepInExRoot = Join-Path $r2ProfileDir "BepInEx"
    $r2CoreDir = Join-Path $r2BepInExRoot "core"
    $r2CoreLoaderPath = Join-Path $r2CoreDir "BepInEx.NET.CoreCLR.dll"
    $r2CorePath = Join-Path $r2CoreDir "BepInEx.Core.dll"
    $r2CommonPath = Join-Path $r2CoreDir "BepInEx.NET.Common.dll"
    $r2PluginsDir = Join-Path $r2BepInExRoot "plugins"
    $r2GameDll = Join-Path $r2GameDir "SmokeGame.dll"
    $r2LogPath = Join-Path $r2BepInExRoot "LogOutput.log"
    $r2GameLoaderPath = Join-Path $r2GameDir "BepInEx.NET.CoreCLR.dll"
    $r2GameHookPath = Join-Path $r2GameDir "d3d11.dll"

    Assert-FileExists -Path $r2RootLoaderPath -Description "r2 profile root startup hook loader"
    Assert-FileExists -Path $r2CoreLoaderPath -Description "r2 profile core startup hook loader"
    Assert-FileExists -Path $r2CorePath -Description "r2 profile BepInEx core assembly"
    Assert-FileExists -Path $r2CommonPath -Description "r2 profile BepInEx .NET common assembly"
    Assert-FileExists -Path $r2D3d11HookPath -Description "r2 profile d3d11 hook"
    Assert-FileExists -Path $r2GameDll -Description "r2 smoke game assembly"

    Copy-Item -LiteralPath $r2RootLoaderPath -Destination $r2GameLoaderPath -Force
    Copy-Item -LiteralPath $r2D3d11HookPath -Destination $r2GameHookPath -Force

    New-Item -ItemType Directory -Force -Path $r2PluginsDir | Out-Null

    @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <CopyLocalLockFileAssemblies>false</CopyLocalLockFileAssemblies>
  </PropertyGroup>
  <ItemGroup>
    <Reference Include="BepInEx.Core">
      <HintPath>$r2CorePath</HintPath>
      <Private>false</Private>
    </Reference>
    <Reference Include="BepInEx.NET.Common">
      <HintPath>$r2CommonPath</HintPath>
      <Private>false</Private>
    </Reference>
  </ItemGroup>
</Project>
"@ | Set-Content -LiteralPath (Join-Path $pluginProjectDir "SmokePlugin.csproj") -Encoding UTF8

    dotnet publish (Join-Path $pluginProjectDir "SmokePlugin.csproj") -c Release -f net8.0 -o $r2PluginsDir | Out-Null
    Assert-FileExists -Path (Join-Path $r2PluginsDir "SmokePlugin.dll") -Description "r2 smoke plugin assembly"

    Remove-Item -LiteralPath $r2LogPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $r2GameDir "BepInEx") -Recurse -Force -ErrorAction SilentlyContinue

    $previousStartupHooks = [Environment]::GetEnvironmentVariable("DOTNET_STARTUP_HOOKS", "Process")
    [Environment]::SetEnvironmentVariable("DOTNET_STARTUP_HOOKS", (Resolve-Path -LiteralPath $r2GameLoaderPath).Path, "Process")

    try {
        & dotnet $r2GameDll --doorstop-enable true --doorstop-target $r2CoreLoaderPath | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "r2 smoke game exited with code $LASTEXITCODE"
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable("DOTNET_STARTUP_HOOKS", $previousStartupHooks, "Process")
    }

    Assert-FileExists -Path $r2LogPath -Description "r2 BepInEx disk log"
    $r2Log = Get-Content -LiteralPath $r2LogPath -Raw

    Write-Host "----- r2 profile smoke test BepInEx log -----"
    Write-Host $r2Log.TrimEnd()
    Write-Host "----- End r2 profile smoke test BepInEx log -----"

    Assert-SmokeLog -Log $r2Log

    if (Test-Path -LiteralPath (Join-Path $r2GameDir "BepInEx")) {
        throw "r2 profile smoke test unexpectedly created a BepInEx folder in the game directory."
    }

    [pscustomobject]@{
        PackagePath = $resolvedPackagePath
        TestRoot = $testRoot
        LogPath = $logPath
        Result = "Passed"
    }
}
finally {
    if (-not $KeepTemp) {
        Remove-SmokeDirectory -Path $testRoot -AllowedRoot $smokeRoot
    }
}
