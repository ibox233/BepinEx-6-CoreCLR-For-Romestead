using System.Collections.Generic;
using BepInEx.Configuration;
using BepInEx.Logging;

namespace BepInEx.Preloader.Core.Logging;

/// <summary>
///     Log listener that buffers messages produced before the chainloader loggers are ready.
/// </summary>
public class PreloaderConsoleListener : ILogListener
{
    private static readonly ConfigEntry<LogLevel> ConfigConsoleDisplayedLevel = ConfigFile.CoreConfig.Bind(
     "Logging.Console", "LogLevels",
     LogLevel.Fatal | LogLevel.Error | LogLevel.Warning | LogLevel.Message | LogLevel.Info,
     "Which log levels to show in the console output.");

    /// <summary>
    ///     A list of all <see cref="LogEventArgs" /> objects that this listener has received.
    /// </summary>
    public static List<LogEventArgs> LogEvents { get; } = new();

    /// <inheritdoc />
    public LogLevel LogLevelFilter => ConfigConsoleDisplayedLevel.Value;

    /// <inheritdoc />
    public void LogEvent(object sender, LogEventArgs eventArgs) => LogEvents.Add(eventArgs);

    /// <inheritdoc />
    public void Dispose() { }
}
