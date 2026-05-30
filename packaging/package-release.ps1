param(
    [string] $Configuration = "Release"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$buildOutput = Join-Path $repoRoot "bin\NET.CoreCLR\net8.0"
$packageRoot = Join-Path $repoRoot "artifacts\release-package"
$artifactRoot = Join-Path $repoRoot "artifacts"
$releaseTemplate = Join-Path $repoRoot "packaging\release"

$loaderPaths = @(
    "BepInEx.Core",
    "BepInEx.Preloader.Core",
    "Runtimes/NET",
    "BepInEx.sln",
    "Directory.Build.props",
    "nuget.config"
)

if (-not (Test-Path -LiteralPath $buildOutput)) {
    throw "Build output was not found: $buildOutput"
}

$versionPrefix = ([xml] (Get-Content -LiteralPath (Join-Path $repoRoot "Directory.Build.props") -Raw)).Project.PropertyGroup.VersionPrefix
if ([string]::IsNullOrWhiteSpace($versionPrefix)) {
    throw "VersionPrefix was not found in Directory.Build.props."
}

$loaderSha = (& git -C $repoRoot log -1 --format=%h -- $loaderPaths).Trim()
if ([string]::IsNullOrWhiteSpace($loaderSha)) {
    throw "Could not resolve the last loader source commit."
}

$framework = "net8.0"
$runtime = "win-x64"
$packageName = "Romestead-BepInEx-NET.CoreCLR-$framework-$runtime-$versionPrefix-$loaderSha"
$zipPath = Join-Path $artifactRoot "$packageName.zip"

Remove-Item -LiteralPath $packageRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "BepInEx\core") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $packageRoot "licenses") | Out-Null

Copy-Item -LiteralPath (Join-Path $buildOutput "BepInEx.NET.CoreCLR.dll") -Destination $packageRoot -Force
Copy-Item -LiteralPath (Join-Path $buildOutput "BepInEx.NET.CoreCLR.deps.json") -Destination $packageRoot -Force

$coreFiles = @(
    "0Harmony.dll",
    "BepInEx.Core.dll",
    "BepInEx.Core.xml",
    "BepInEx.NET.Common.dll",
    "BepInEx.NET.Common.xml",
    "BepInEx.NET.CoreCLR.dll",
    "BepInEx.NET.CoreCLR.deps.json",
    "BepInEx.Preloader.Core.dll",
    "BepInEx.Preloader.Core.xml",
    "Mono.Cecil.dll",
    "Mono.Cecil.Mdb.dll",
    "Mono.Cecil.Pdb.dll",
    "Mono.Cecil.Rocks.dll",
    "MonoMod.Backports.dll",
    "MonoMod.Core.dll",
    "MonoMod.Iced.dll",
    "MonoMod.ILHelpers.dll",
    "MonoMod.RuntimeDetour.dll",
    "MonoMod.Utils.dll",
    "SemanticVersioning.dll"
)

foreach ($fileName in $coreFiles) {
    $source = Join-Path $buildOutput $fileName
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Expected build output is missing: $source"
    }

    Copy-Item -LiteralPath $source -Destination (Join-Path $packageRoot "BepInEx\core") -Force
}

Copy-Item -LiteralPath (Join-Path $releaseTemplate "install.bat") -Destination $packageRoot -Force
Copy-Item -LiteralPath (Join-Path $releaseTemplate "install.ps1") -Destination $packageRoot -Force
Copy-Item -LiteralPath (Join-Path $releaseTemplate "uninstall.bat") -Destination $packageRoot -Force
Copy-Item -LiteralPath (Join-Path $releaseTemplate "uninstall.ps1") -Destination $packageRoot -Force
Copy-Item -LiteralPath (Join-Path $releaseTemplate "README.txt") -Destination $packageRoot -Force

Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSE") -Destination (Join-Path $packageRoot "licenses\BepInEx-LGPL-2.1.txt") -Force
Copy-Item -LiteralPath (Join-Path $releaseTemplate "licenses\HarmonyX-MIT.txt") -Destination (Join-Path $packageRoot "licenses\HarmonyX-MIT.txt") -Force
Copy-Item -LiteralPath (Join-Path $releaseTemplate "licenses\MonoMod-MIT.txt") -Destination (Join-Path $packageRoot "licenses\MonoMod-MIT.txt") -Force
Copy-Item -LiteralPath (Join-Path $releaseTemplate "licenses\THIRD_PARTY_NOTICES.txt") -Destination (Join-Path $packageRoot "licenses\THIRD_PARTY_NOTICES.txt") -Force

$forbiddenPatterns = @(
    "Romestead.exe",
    "Romestead.dll",
    "CandideServer.dll",
    "Shared.dll",
    "CandideCreator.Shared.dll",
    "MonoGame.Framework.dll",
    "steam_api*.dll",
    "LogOutput.log",
    "*.sav",
    "*.zip"
)

foreach ($pattern in $forbiddenPatterns) {
    $matches = Get-ChildItem -LiteralPath $packageRoot -Recurse -File -Filter $pattern -ErrorAction SilentlyContinue
    if ($matches) {
        $names = ($matches | ForEach-Object { $_.FullName }) -join [Environment]::NewLine
        throw "Release package contains forbidden file(s): $names"
    }
}

Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath -Force

[pscustomobject]@{
    PackageName = $packageName
    AssetName = "$packageName.zip"
    AssetPath = $zipPath
    ReleaseTag = $packageName
    ReleaseName = $packageName
    LoaderSha = $loaderSha
    Version = $versionPrefix
}
