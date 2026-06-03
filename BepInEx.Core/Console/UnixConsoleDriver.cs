using System;
using System.IO;

namespace BepInEx;

internal class UnixConsoleDriver : IConsoleDriver
{
    public TextWriter StandardOut { get; private set; }
    public TextWriter ConsoleOut { get; private set; }

    public bool ConsoleActive { get; private set; }
    public bool ConsoleIsExternal => false;

    public void Initialize(bool alreadyActive, bool useManagedEncoder)
    {
        StandardOut = Console.Out;
        ConsoleOut = Console.Out;
        ConsoleActive = alreadyActive;
    }

    public void CreateConsole(uint codepage)
    {
        StandardOut = Console.Out;
        ConsoleOut = Console.Out;
        ConsoleActive = true;
    }

    public void PreventClose() { }

    public void DetachConsole()
    {
        ConsoleOut = TextWriter.Null;
        ConsoleActive = false;
    }

    public void SetConsoleColor(ConsoleColor color)
    {
        try
        {
            Console.ForegroundColor = color;
        }
        catch
        {
            // Some redirected or headless Unix terminals do not support colors.
        }
    }

    public void SetConsoleTitle(string title)
    {
        try
        {
            Console.Title = title;
        }
        catch
        {
            // Console titles are optional on Unix terminals.
        }
    }
}
