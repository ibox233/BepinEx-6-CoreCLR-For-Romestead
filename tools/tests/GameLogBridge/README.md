# Game log bridge tests

Run from the loader repository root with .NET 8. The fixtures contain simulated
game methods; these tests do not run Romestead or display real dialogs.

```powershell
$root = (Get-Location).Path.Replace('\', '/') + '/'
$fixture = 'tools/tests/GameLogBridge/Fixtures/Fixtures.csproj'
foreach ($name in @('Romestead', 'CandideCreator.Shared', 'RiptideNetworking', 'MonoGame.Framework', 'System.Windows.Forms')) {
    dotnet build $fixture -c Release "-p:FixtureName=$name" "-p:OutputPath=${root}artifacts/game-log-bridge/fixtures/$name/" "-p:IntermediateOutputPath=obj/$name/"
    if ($LASTEXITCODE -ne 0) { throw 'Fixture build failed' }
}
foreach ($name in @('Romestead', 'CandideCreator.Shared')) {
    dotnet build $fixture -c Release "-p:FixtureName=$name" '-p:DefineConstants=CHANGED' "-p:OutputPath=${root}artifacts/game-log-bridge/changed/$name/" "-p:IntermediateOutputPath=obj/changed/$name/"
    if ($LASTEXITCODE -ne 0) { throw 'Fixture build failed' }
}
dotnet build $fixture -c Release '-p:FixtureName=Romestead' '-p:DefineConstants=MISSING' "-p:OutputPath=${root}artifacts/game-log-bridge/missing/Romestead/" '-p:IntermediateOutputPath=obj/missing/'
if ($LASTEXITCODE -ne 0) { throw 'Fixture build failed' }

$test = 'tools/tests/GameLogBridge/GameLogBridge.Tests.csproj'
dotnet build $test -c Release "-p:SolutionDir=$root"
if ($LASTEXITCODE -ne 0) { throw 'Test build failed' }
foreach ($mode in @('normal', 'disabled', 'changed', 'missing', 'startup-failure')) {
    $folder = if ($mode -in @('normal', 'disabled', 'startup-failure')) { 'fixtures' } else { $mode }
    dotnet run --project $test -c Release --no-build -- "artifacts/game-log-bridge/$folder" $mode
    if ($LASTEXITCODE -ne 0) { throw "Tests failed: $mode" }
}
```

Checks cover output levels, exception details, exception deduplication, preserved
dialog results and original exceptions, late assembly loads, concurrent output,
recursive/throwing listeners, failed installation, changed/missing APIs, live
disable, startup-disable and guarded startup failure, file flushing, and actual chainloader
plugin discovery/loading. Each run uses a new temporary BepInEx directory.

This is managed integration coverage, not game or Proton runtime validation.
