using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using BepInEx.Logging;
using BepInEx.NET.CoreCLR;
using BepInEx.NET.Shared;
using BepInEx.Preloader.Core;

internal class StartupHook
{
    public static List<string> ResolveDirectories = new();

    public static string DoesNotExistPath = "_doesnotexist_.exe";

    private static int initialized;
    private static Mutex initializationMutex;

    private const string AppDomainInitializedKey = "Romestead.BepInEx.NET.CoreCLR.StartupHook.Initialized";

    public static void Initialize()
    {
        if (!TryBeginInitialize())
            return;

        var silentExceptionLog = $"bepinex_preloader_{DateTime.Now:yyyyMMdd_HHmmss_fff}.log";

        try
        {
//#if DEBUG
//          filename =
//              Path.Combine(Directory.GetCurrentDirectory(),
//                           Path.GetFileName(Process.GetCurrentProcess().MainModule.FileName));
//          ResolveDirectories.Add(Path.GetDirectoryName(filename));

//          // for debugging within VS
//          ResolveDirectories.Add(Path.GetDirectoryName(Process.GetCurrentProcess().MainModule.FileName));
//#else
            
            var executableFilename = Process.GetCurrentProcess().MainModule.FileName;
            
            var assemblyFilename = TryDetermineAssemblyNameFromDotnet(executableFilename)
                                ?? TryDetermineAssemblyNameFromStubExecutable(executableFilename)
                                ?? TryDetermineAssemblyNameFromCurrentAssembly(executableFilename);

            string gameDirectory = null;

            if (assemblyFilename != null)
                gameDirectory = Path.GetDirectoryName(assemblyFilename);

            var bepinexRootDirectory = TryDetermineBepInExRootFromDoorstopTarget()
                                    ?? TryDetermineBepInExRootFromCurrentAssembly()
                                    ?? TryDetermineBepInExRootFromGameDirectory(gameDirectory);

            string bepinexCoreDirectory = null;

            if (bepinexRootDirectory != null)
                bepinexCoreDirectory = Path.Combine(bepinexRootDirectory, "core");

            if (assemblyFilename == null || gameDirectory == null || !Directory.Exists(bepinexCoreDirectory))
            {
                throw new Exception("Could not determine game location, or BepInEx install location");
            }
            
            silentExceptionLog = Path.Combine(gameDirectory, silentExceptionLog);
            
            ResolveDirectories.Add(bepinexCoreDirectory);
//#endif

            AppDomain.CurrentDomain.AssemblyResolve += SharedEntrypoint.RemoteResolve(ResolveDirectories);

            NetCorePreloaderRunner.OuterMain(assemblyFilename, bepinexRootDirectory);
        }
        catch (Exception ex)
        {
            string executableLocation = null;
            string arguments = null;

            try
            {
                executableLocation = Process.GetCurrentProcess().MainModule?.FileName;
                arguments = string.Join(' ', Environment.GetCommandLineArgs());
            }
            catch { }

            string exceptionString = $"Unhandled fatal exception\r\n" +
                                     $"Executable location: {executableLocation ?? "<null>"}\r\n" +
                                     $"Arguments: {arguments ?? "<null>"}\r\n" +
                                     $"{ex}";

            File.WriteAllText(silentExceptionLog, exceptionString);

            Console.WriteLine("Unhandled exception");
            Console.WriteLine($"Executable location: {executableLocation ?? "<null>"}");
            Console.WriteLine($"Arguments: {arguments ?? "<null>"}");
            Console.WriteLine(ex);
        }
    }

    private static bool TryBeginInitialize()
    {
        if (Interlocked.Exchange(ref initialized, 1) == 1)
            return false;

        if (AppDomain.CurrentDomain.GetData(AppDomainInitializedKey) != null)
            return false;

        try
        {
            var mutexName = $"Romestead.BepInEx.NET.CoreCLR.StartupHook.{Environment.ProcessId}";
            initializationMutex = new Mutex(true, mutexName, out var createdNew);

            if (!createdNew)
                return false;
        }
        catch
        {
            // AppDomain data still protects the common duplicate-load case. The mutex
            // only covers separate AssemblyLoadContexts entering at the same time.
        }

        AppDomain.CurrentDomain.SetData(AppDomainInitializedKey, true);
        return true;
    }

    private static string TryDetermineAssemblyNameFromDotnet(string executableFilename)
    {
        if (Path.GetFileNameWithoutExtension(executableFilename) == "dotnet")
        {
            // We're in a special setup that uses dotnet directly to start a .dll, instead of a .exe that launches dotnet implicitly

            var args = Environment.GetCommandLineArgs();

            foreach (var arg in args)
            {
                if (!arg.EndsWith(".dll", StringComparison.OrdinalIgnoreCase)
                 && !arg.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                if (File.Exists(arg))
                {
                    return Path.GetFullPath(arg);
                }
            }
        }

        return null;
    }

    private static string TryDetermineAssemblyNameFromStubExecutable(string executableFilename)
    {
        string dllFilename = Path.ChangeExtension(executableFilename, ".dll");

        if (File.Exists(dllFilename))
            return dllFilename;

        return null;
    }

    private static string TryDetermineAssemblyNameFromCurrentAssembly(string executableFilename)
    {
        string assemblyLocation = typeof(StartupHook).Assembly.Location.Replace('/', Path.DirectorySeparatorChar);

        string coreFolderPath = Path.GetDirectoryName(assemblyLocation);

        if (coreFolderPath == null)
            return null; // throw new Exception("Could not find a valid path to the BepInEx directory");

        string gameDirectory = Path.GetDirectoryName(Path.GetDirectoryName(coreFolderPath));

        if (gameDirectory == null)
            return null; // throw new Exception("Could not find a valid path to the game directory");

        return Path.Combine(gameDirectory, DoesNotExistPath);
    }

    private static string TryDetermineBepInExRootFromDoorstopTarget()
    {
        var targetAssembly = GetCommandLineArgValue("--doorstop-target")
                          ?? GetCommandLineArgValue("--doorstop-target-assembly")
                          ?? GetCommandLineArgValue("--doorstop_target_assembly");

        if (string.IsNullOrWhiteSpace(targetAssembly))
            return null;

        return TryDetermineBepInExRootFromTargetAssembly(targetAssembly);
    }

    private static string TryDetermineBepInExRootFromTargetAssembly(string targetAssembly)
    {
        string fullTargetAssemblyPath;

        try
        {
            fullTargetAssemblyPath = Path.GetFullPath(targetAssembly);
        }
        catch
        {
            return null;
        }

        if (!File.Exists(fullTargetAssemblyPath))
            return null;

        if (!string.Equals(Path.GetFileName(fullTargetAssemblyPath), "BepInEx.NET.CoreCLR.dll",
                           StringComparison.OrdinalIgnoreCase))
            return null;

        var targetDirectory = Path.GetDirectoryName(fullTargetAssemblyPath);

        if (targetDirectory == null)
            return null;

        if (string.Equals(Path.GetFileName(targetDirectory), "core", StringComparison.OrdinalIgnoreCase))
        {
            var bepinexRoot = ParentDirectory(fullTargetAssemblyPath, 2);

            if (HasBepInExCoreDirectory(bepinexRoot))
                return bepinexRoot;
        }

        return TryDetermineBepInExRootFromGameDirectory(targetDirectory);
    }

    private static string TryDetermineBepInExRootFromCurrentAssembly()
    {
        var assemblyLocation = typeof(StartupHook).Assembly.Location.Replace('/', Path.DirectorySeparatorChar);
        return TryDetermineBepInExRootFromTargetAssembly(assemblyLocation);
    }

    private static string TryDetermineBepInExRootFromGameDirectory(string gameDirectory)
    {
        if (string.IsNullOrWhiteSpace(gameDirectory))
            return null;

        var bepinexRoot = Path.Combine(gameDirectory, "BepInEx");

        return HasBepInExCoreDirectory(bepinexRoot) ? bepinexRoot : null;
    }

    private static bool HasBepInExCoreDirectory(string bepinexRoot)
    {
        return !string.IsNullOrWhiteSpace(bepinexRoot)
            && Directory.Exists(Path.Combine(bepinexRoot, "core"));
    }

    private static string GetCommandLineArgValue(string name)
    {
        var args = Environment.GetCommandLineArgs();

        for (var i = 1; i < args.Length - 1; i++)
        {
            if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
                return args[i + 1];
        }

        return null;
    }

    private static string ParentDirectory(string path, int levels)
    {
        for (var i = 0; i < levels; i++)
            path = Path.GetDirectoryName(path);

        return path;
    }
}

namespace BepInEx.NET.CoreCLR
{
    internal static class NetCorePreloaderRunner
    {
        internal static void PreloaderMain()
        {
            ConsoleManager.Initialize(false, true);

            if (ConsoleManager.ConsoleEnabled)
            {
                ConsoleManager.CreateConsole();
                Logger.Listeners.Add(new ConsoleLogListener());
            }

            try
            {
                NetCorePreloader.Start();
            }
            catch (Exception ex)
            {
                PreloaderLogger.Log.Log(LogLevel.Fatal, "Unhandled exception");
                PreloaderLogger.Log.Log(LogLevel.Fatal, ex);
            }
        }

        internal static void OuterMain(string filename, string bepinexRootPath)
        {
            PlatformUtils.SetPlatform();

            Paths.SetDotNetGamePath(filename, bepinexRootPath);

            AppDomain.CurrentDomain.AssemblyResolve += SharedEntrypoint.LocalResolve;

            PreloaderMain();
        }
    }
}
