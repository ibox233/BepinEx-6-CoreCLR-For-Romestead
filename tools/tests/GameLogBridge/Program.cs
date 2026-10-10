using System;
using System.Collections.Concurrent;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Threading.Tasks;
using BepInEx;
using BepInEx.Configuration;
using BepInEx.Logging;
using BepInEx.NET.Common;

internal static class Program
{
    private static readonly ConcurrentQueue<LogEventArgs> Records = new();
    private static int checks;

    private static int Main(string[] args)
    {
        try
        {
            Run(args[0], args[1]);
            Console.WriteLine($"PASS {args[1]}: {checks} checks");
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error);
            return 1;
        }
    }

    private static void Run(string fixtures, string mode)
    {
        var root = Path.Combine(Path.GetTempPath(), "RomesteadGameLogBridge", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        Paths.SetDotNetGamePath(Path.Combine(root, "Romestead.dll"));
        ConfigEntry<bool> cfg = null;
        if (mode == "startup-failure")
            ConfigFile.CoreConfig.Bind("Logging.Game", "Enabled", "conflicting binding", "Test setting");
        else
            cfg = ConfigFile.CoreConfig.Bind("Logging.Game", "Enabled", mode != "disabled", "Test setting");
        ConfigFile.CoreConfig.Bind("Logging.Console", "Enabled", false, "Test setting");
        ConfigFile.CoreConfig.Bind("Logging.Disk", "Enabled", false, "Test setting");
        Logger.Listeners.Add(new Capture());
        using var disk = new DiskLogListener("LogOutput.log", LogLevel.All, delayedFlushing: true);
        Logger.Listeners.Add(disk);

        var game = Assembly.LoadFrom(Path.Combine(fixtures, "Romestead", "Romestead.dll"));
        var chainloader = new NetChainloader();
        chainloader.Initialize();
        File.Copy(typeof(Program).Assembly.Location, Path.Combine(Paths.PluginPath, "BridgeTest.dll"));
        var loader = Assembly.Load("BepInEx.NET.CoreCLR");
        var bridge = loader.GetType("BepInEx.NET.CoreCLR.GameLogBridge", true);
        var start = loader.GetType("BepInEx.NET.CoreCLR.NetCorePreloader", true).GetMethod("SetupGameLogs", BindingFlags.Static | BindingFlags.NonPublic);
        start.Invoke(null, null);
        start.Invoke(null, null);

        if (mode == "startup-failure")
        {
            Check(bridge.GetField("started", BindingFlags.Static | BindingFlags.NonPublic).GetValue(null).Equals(false), "conflicting config prevents bridge initialization");
            Check(Records.IsEmpty, "failed bridge emits nothing");
            CheckPlugin(chainloader);
            return;
        }

        if (mode == "missing")
        {
            Check(game.GetType("Candide.Program", false) == null, "game logging type is absent");
            Check(Records.IsEmpty, "missing target is skipped");
            CheckPlugin(chainloader);
            return;
        }

        var debug = Load(fixtures, "CandideCreator.Shared", "CandideCreator.Shared.Helpers.DebugHelper");
        var debugMethod = debug.GetMethod("PrintAndConsole");
        var program = game.GetType("Candide.Program", true);
        var handler = program.GetMethod("Game_UnhandledExceptionHandler");
        var error = MakeError();
        var result = handler.Invoke(null, new object[] { error });
        debugMethod.Invoke(null, new object[] { "中文输出" });

        if (mode == "disabled")
        {
            Check(Records.IsEmpty, "disabled bridge emits nothing");
            Check(Equals(result, true), "disabled bridge preserves return");
            Check((int)debug.GetField("Calls").GetValue(null) == 1, "disabled bridge preserves original");
            CheckPlugin(chainloader);
            return;
        }

        if (mode == "changed")
        {
            Check(Equals(result, 7), "changed return type is untouched");
            Check(Records.IsEmpty, "changed signatures are skipped, including object/string binder conversion");
            program.GetMethod("App_DispatcherUnhandledException").Invoke(null, new object[] { null, new UnhandledExceptionEventArgs(error, false) });
            Check(Records.Count == 1, "valid target still works beside changed targets");
            Check((int)debug.GetField("Calls").GetValue(null) == 1, "changed original still runs");
            CheckPlugin(chainloader);
            return;
        }

        Check(Equals(result, true), "exception handler return is preserved");
        Check(Has("outer error", LogLevel.Error) && Has("inner error", LogLevel.Error) && Has("MakeError", LogLevel.Error), "exception contains stack and inner error");
        Check(Has("中文输出", LogLevel.Info), "late-loaded game output is bridged");
        using (var stream = new FileStream(Path.Combine(Paths.BepInExRootPath, "LogOutput.log"), FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
        using (var reader = new StreamReader(stream))
            Check(reader.ReadToEnd().Contains("outer error"), "error flushes file buffer");

        var count = Records.Count;
        program.GetMethod("App_DispatcherUnhandledException").Invoke(null, new object[] { null, new UnhandledExceptionEventArgs(error, true) });
        Check(Records.Count == count, "same exception is recorded once");
        Check((int)program.GetField("Calls").GetValue(null) == 2, "both original exception handlers run");

        var riptide = Load(fixtures, "RiptideNetworking", "Riptide.Utils.RiptideLogger");
        var logType = riptide.Assembly.GetType("Riptide.Utils.LogType", true);
        foreach (var name in new[] { "Debug", "Info", "Warning", "Error" })
        {
            var method = riptide.GetMethod("Log", new[] { logType, typeof(string) });
            method.Invoke(null, new[] { Enum.Parse(logType, name), "network " + name });
            Check(Has("network " + name, Enum.Parse<LogLevel>(name)), "network level " + name);
        }
        riptide.GetMethod("Log", new[] { logType, typeof(string), typeof(string) }).Invoke(null, new[] { Enum.Parse(logType, "Info"), "Server", "named log" });
        Check(Has("[Server] named log", LogLevel.Info), "named network overload");
        Check((int)riptide.GetField("Calls").GetValue(null) == 5, "network originals remain active");

        var mono = Load(fixtures, "MonoGame.Framework", "Microsoft.Xna.Framework.Input.MessageBox");
        var task = (Task<int?>)mono.GetMethod("Show").Invoke(null, new object[] { "Game startup", "dialog body", new[] { "OK" } });
        Check(task.GetAwaiter().GetResult() == 2 && (int)mono.GetField("Calls").GetValue(null) == 1, "async dialog result and body unchanged");
        Check(Has("Game startup: dialog body", LogLevel.Warning), "MonoGame dialog text");

        var forms = Load(fixtures, "System.Windows.Forms", "System.Windows.Forms.MessageBox");
        var buttons = forms.Assembly.GetType("System.Windows.Forms.MessageBoxButtons", true);
        var icon = forms.Assembly.GetType("System.Windows.Forms.MessageBoxIcon", true);
        var dialog = forms.GetMethod("Show").Invoke(null, new[] { "弹窗内容", "错误标题", Enum.Parse(buttons, "CancelTryContinue"), Enum.Parse(icon, "Hand") });
        Check(dialog.ToString() == "Continue", "WinForms dialog result unchanged");
        Check(Has("错误标题: 弹窗内容", LogLevel.Error), "WinForms error text");

        count = Records.Count;
        cfg.Value = false;
        debugMethod.Invoke(null, new object[] { "off" });
        Check(Records.Count == count, "live config disables output");
        cfg.Value = true;

        var broken = new Broken();
        Logger.Listeners.Add(broken);
        debugMethod.Invoke(null, new object[] { "listener throws" });
        Logger.Listeners.Remove(broken);
        Check((int)debug.GetField("Calls").GetValue(null) == 3, "throwing listener cannot stop original");
        debugMethod.Invoke(null, new object[] { "after failure" });
        Check(Has("after failure", LogLevel.Info), "bridge still usable after listener failure");

        var recursive = new Recursive(debugMethod);
        Logger.Listeners.Add(recursive);
        count = Records.Count;
        debugMethod.Invoke(null, new object[] { "recursive" });
        Logger.Listeners.Remove(recursive);
        Check(Records.Count == count + 1, "listener recursion is guarded");

        Parallel.For(0, 20, i => debugMethod.Invoke(null, new object[] { "parallel " + i }));
        Check(Records.Count(e => e.Data.ToString().StartsWith("parallel ")) == 20, "concurrent output");
        try
        {
            debugMethod.Invoke(null, new object[] { "original throws" });
            throw new Exception("Original exception was swallowed");
        }
        catch (TargetInvocationException thrown)
        {
            Check(thrown.InnerException.Message == "original exception", "original exceptions remain unchanged");
        }

        // 注入安装失败，检查它不会从桥的 Patch 入口传播。
        var harmony = bridge.GetField("harmony", BindingFlags.Static | BindingFlags.NonPublic);
        var saved = harmony.GetValue(null);
        harmony.SetValue(null, null);
        bridge.GetMethod("Patch", BindingFlags.Static | BindingFlags.NonPublic).Invoke(null, new object[] { debug, "PrintAndConsole", typeof(void), new[] { typeof(string) } });
        harmony.SetValue(null, saved);
        debugMethod.Invoke(null, new object[] { "after install failure" });
        Check(Has("after install failure", LogLevel.Info), "isolated installation failure");

        CheckPlugin(chainloader);
        Logger.Listeners.Remove(disk);
        Console.WriteLine("Isolated log: " + Path.Combine(Paths.BepInExRootPath, "LogOutput.log"));
    }

    private static Type Load(string fixtures, string name, string type)
    {
        return Assembly.LoadFrom(Path.Combine(fixtures, name, name + ".dll")).GetType(type, true);
    }

    private static void CheckPlugin(NetChainloader chainloader)
    {
        chainloader.Execute();
        Check(chainloader.Plugins.ContainsKey("bridge.test") && TestPlugin.Loaded, "chainloader discovers and loads plugin after bridge setup/failures");
    }

    private static Exception MakeError()
    {
        try
        {
            throw new InvalidOperationException("outer error", new Exception("inner error"));
        }
        catch (Exception error)
        {
            return error;
        }
    }

    private static bool Has(string text, LogLevel level)
    {
        return Records.Any(e => e.Source.SourceName == "Game" && e.Level == level && e.Data.ToString().Contains(text));
    }

    private static void Check(bool condition, string message)
    {
        if (!condition)
            throw new Exception("FAIL: " + message);

        checks++;
    }

    private sealed class Capture : ILogListener
    {
        public LogLevel LogLevelFilter => LogLevel.All;

        public void LogEvent(object sender, LogEventArgs args)
        {
            if (args.Source.SourceName == "Game")
                Records.Enqueue(args);
        }

        public void Dispose() { }
    }

    private sealed class Broken : ILogListener
    {
        public LogLevel LogLevelFilter => LogLevel.All;
        public void LogEvent(object sender, LogEventArgs args)
        {
            throw new IOException("listener failure");
        }

        public void Dispose() { }
    }

    private sealed class Recursive(MethodInfo method) : ILogListener
    {
        public LogLevel LogLevelFilter => LogLevel.All;
        public void LogEvent(object sender, LogEventArgs args)
        {
            method.Invoke(null, new object[] { "nested output" });
        }

        public void Dispose() { }
    }

}

[BepInPlugin("bridge.test", "Bridge test", "1.0.0")]
public sealed class TestPlugin : BasePlugin
{
    public static bool Loaded;

    public override void Load()
    {
        Loaded = true;
    }
}
