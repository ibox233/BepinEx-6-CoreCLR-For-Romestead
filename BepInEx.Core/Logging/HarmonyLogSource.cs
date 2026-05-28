using System;
using BepInEx.Configuration;

namespace BepInEx.Logging;

public class HarmonyLogSource : ILogSource
{
    [Flags]
    private enum HarmonyLogChannel
    {
        None = 0,
        Info = 1,
        IL = 2,
        Warn = 4,
        Error = 8,
        Debug = 16,
        All = Info | IL | Warn | Error | Debug
    }

    private static readonly ConfigEntry<HarmonyLogChannel> LogChannels = ConfigFile.CoreConfig.Bind(
     "Harmony.Logger",
     "LogChannels",
     HarmonyLogChannel.Warn | HarmonyLogChannel.Error,
     "Specifies which Harmony log channels to listen to.\nNOTE: IL channel dumps the whole patch methods, use only when needed!");

    public HarmonyLogSource()
    {
        _ = LogChannels.Value;
    }

    public void Dispose()
    {
    }

    public string SourceName { get; } = "Harmony";
    public event EventHandler<LogEventArgs> LogEvent;
}
