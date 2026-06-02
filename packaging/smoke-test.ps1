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
$gameDir = Join-Path $testRoot "game"

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
Console.WriteLine("SmokeGame main reached");
"@ | Set-Content -LiteralPath (Join-Path $projectDir "Program.cs") -Encoding UTF8

    dotnet publish (Join-Path $projectDir "SmokeGame.csproj") -c Release -f net8.0 --self-contained false -o $gameDir | Out-Null

    Expand-Archive -LiteralPath $resolvedPackagePath -DestinationPath $gameDir -Force

    $loaderPath = Join-Path $gameDir "BepInEx.NET.CoreCLR.dll"
    $corePath = Join-Path (Join-Path (Join-Path $gameDir "BepInEx") "core") "BepInEx.Core.dll"
    $gameDll = Join-Path $gameDir "SmokeGame.dll"
    $logPath = Join-Path (Join-Path $gameDir "BepInEx") "LogOutput.log"

    Assert-FileExists -Path $loaderPath -Description "Startup hook loader"
    Assert-FileExists -Path $corePath -Description "BepInEx core assembly"
    Assert-FileExists -Path $gameDll -Description "Smoke game assembly"

    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue

    $previousStartupHooks = [Environment]::GetEnvironmentVariable("DOTNET_STARTUP_HOOKS", "Process")
    [Environment]::SetEnvironmentVariable("DOTNET_STARTUP_HOOKS", (Resolve-Path -LiteralPath $loaderPath).Path, "Process")

    try {
        & dotnet $gameDll | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "Smoke game exited with code $LASTEXITCODE"
        }
    }
    finally {
        [Environment]::SetEnvironmentVariable("DOTNET_STARTUP_HOOKS", $previousStartupHooks, "Process")
    }

    Assert-FileExists -Path $logPath -Description "BepInEx disk log"
    $log = Get-Content -LiteralPath $logPath -Raw

    Assert-LogContains -Log $log -Text "Preloader started"
    Assert-LogContains -Log $log -Text "Preloader finished"
    Assert-LogContains -Log $log -Text "Chainloader initialized"
    Assert-LogContains -Log $log -Text "0 plugins to load"
    Assert-LogContains -Log $log -Text "Chainloader startup complete"

    $hasFatalPreloaderError = $log.IndexOf("[Fatal  : Preloader]", [System.StringComparison]::Ordinal) -ge 0 -or
                              $log.IndexOf("Unhandled fatal exception", [System.StringComparison]::Ordinal) -ge 0

    if ($hasFatalPreloaderError) {
        throw "Smoke test log contains a fatal preloader error."
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
