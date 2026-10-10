using System;
using System.Collections.Generic;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using BepInEx.Configuration;
using BepInEx.Logging;
using HarmonyLib;

namespace BepInEx.NET.CoreCLR;

internal static class GameLogBridge
{
    private static readonly object Sync = new();
    private static readonly Queue<Assembly> Pending = new();
    private static readonly HashSet<Assembly> Seen = new();
    private static readonly ConditionalWeakTable<Exception, object> Errors = new();
    private static Harmony harmony;
    private static ManualLogSource log;
    private static ConfigEntry<bool> enabled;
    private static bool started;
    private static bool processing;

    [ThreadStatic]
    private static bool writing;

    [MethodImpl(MethodImplOptions.NoInlining)]
    internal static void Start()
    {
        lock (Sync)
        {
            if (started)
                return;

            enabled = ConfigFile.CoreConfig.Bind("Logging.Game", "Enabled", true, "Forward game logs and error dialogs to BepInEx. Restart to apply changes to installed hooks.");
            if (!enabled.Value)
                return;

            harmony = new Harmony("romestead.game-logs");
            log = Logger.CreateLogSource("Game");
            started = true;
            AppDomain.CurrentDomain.AssemblyLoad += OnAssemblyLoad;
        }

        foreach (var assembly in AppDomain.CurrentDomain.GetAssemblies())
            Add(assembly);
    }

    private static void OnAssemblyLoad(object sender, AssemblyLoadEventArgs args)
    {
        Add(args.LoadedAssembly);
    }

    private static void Add(Assembly assembly)
    {
        try
        {
            var name = assembly.GetName().Name;
            if (name != "Romestead" && name != "CandideCreator.Shared" && name != "RiptideNetworking" &&
                name != "MonoGame.Framework" && name != "System.Windows.Forms")
                return;

            lock (Sync)
            {
                if (!Seen.Add(assembly))
                    return;

                Pending.Enqueue(assembly);
                if (processing)
                    return;

                processing = true;
            }

            while (true)
            {
                Assembly next;
                lock (Sync)
                {
                    if (Pending.Count == 0)
                    {
                        processing = false;
                        return;
                    }

                    next = Pending.Dequeue();
                }

                try
                {
                    Setup(next);
                }
                catch (Exception)
                {
                }
            }
        }
        catch (Exception)
        {
        }
    }

    private static void Setup(Assembly assembly)
    {
        switch (assembly.GetName().Name)
        {
            case "Romestead":
                var program = assembly.GetType("Candide.Program", false);
                Patch(program, "Game_UnhandledExceptionHandler", typeof(bool), typeof(Exception));
                Patch(program, "App_DispatcherUnhandledException", typeof(void), typeof(object), typeof(UnhandledExceptionEventArgs));
                break;
            case "CandideCreator.Shared":
                Patch(assembly.GetType("CandideCreator.Shared.Helpers.DebugHelper", false), "PrintAndConsole", typeof(void), typeof(string));
                break;
            case "RiptideNetworking":
                var logger = assembly.GetType("Riptide.Utils.RiptideLogger", false);
                var level = assembly.GetType("Riptide.Utils.LogType", false);
                if (level?.IsEnum != true)
                    break;

                Patch(logger, "Log", typeof(void), level, typeof(string));
                Patch(logger, "Log", typeof(void), level, typeof(string), typeof(string));
                break;
            case "MonoGame.Framework":
                Patch(assembly.GetType("Microsoft.Xna.Framework.Input.MessageBox", false), "Show", typeof(Task<int?>), typeof(string), typeof(string), typeof(IEnumerable<string>));
                break;
            case "System.Windows.Forms":
                var buttons = assembly.GetType("System.Windows.Forms.MessageBoxButtons", false);
                var icon = assembly.GetType("System.Windows.Forms.MessageBoxIcon", false);
                var result = assembly.GetType("System.Windows.Forms.DialogResult", false);
                if (buttons?.IsEnum != true || icon?.IsEnum != true || result?.IsEnum != true)
                    break;

                Patch(assembly.GetType("System.Windows.Forms.MessageBox", false), "Show", result, typeof(string), typeof(string), buttons, icon);
                break;
        }
    }

    private static void Patch(Type type, string name, Type result, params Type[] args)
    {
        try
        {
            var method = type?.GetMethod(name, BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.DeclaredOnly, null, args, null);
            if (method == null || method.ReturnType != result || method.ContainsGenericParameters || method.GetMethodBody() == null)
                return;

            var parameters = method.GetParameters();
            for (var i = 0; i < args.Length; i++)
            {
                if (parameters[i].ParameterType != args[i])
                    return;
            }

            var prefix = typeof(GameLogBridge).GetMethod(nameof(Observe), BindingFlags.NonPublic | BindingFlags.Static);
            harmony.Patch(method, prefix: new HarmonyMethod(prefix));
        }
        catch (Exception)
        {
        }
    }

    private static void Observe(MethodBase __originalMethod, object[] __args)
    {
        if (writing)
            return;

        writing = true;
        try
        {
            if (enabled?.Value != true)
                return;

            var type = __originalMethod.DeclaringType.FullName;
            switch (type)
            {
                case "Candide.Program":
                    var error = __args[0] as Exception;
                    if (__originalMethod.Name == "App_DispatcherUnhandledException")
                        error = (__args[1] as UnhandledExceptionEventArgs)?.ExceptionObject as Exception;

                    if (error == null)
                        return;

                    lock (Errors)
                    {
                        if (Errors.TryGetValue(error, out _))
                            return;

                        Errors.Add(error, new object());
                    }

                    Write(LogLevel.Error, error.ToString());
                    break;
                case "CandideCreator.Shared.Helpers.DebugHelper":
                    Write(LogLevel.Info, (string)__args[0]);
                    break;
                case "Riptide.Utils.RiptideLogger":
                    var level = __args[0].ToString() switch
                    {
                        "Debug" => LogLevel.Debug,
                        "Warning" => LogLevel.Warning,
                        "Error" => LogLevel.Error,
                        _ => LogLevel.Info
                    };
                    var message = __args.Length == 3 ? $"[{__args[1]}] {__args[2]}" : (string)__args[1];
                    Write(level, message);
                    break;
                case "Microsoft.Xna.Framework.Input.MessageBox":
                    Write(LogLevel.Warning, $"{__args[0]}: {__args[1]}");
                    break;
                case "System.Windows.Forms.MessageBox":
                    var icon = __args[3].ToString();
                    var dialogLevel = icon is "Hand" or "Error" or "Stop" ? LogLevel.Error : LogLevel.Warning;
                    Write(dialogLevel, $"{__args[1]}: {__args[0]}");
                    break;
            }
        }
        catch (Exception)
        {
        }
        finally
        {
            writing = false;
        }
    }

    private static void Write(LogLevel level, string message)
    {
        log.Log(level, message);
        if (level != LogLevel.Error)
            return;

        foreach (var listener in Logger.Listeners)
        {
            if (listener is DiskLogListener disk)
                disk.LogWriter?.Flush();
        }
    }
}
