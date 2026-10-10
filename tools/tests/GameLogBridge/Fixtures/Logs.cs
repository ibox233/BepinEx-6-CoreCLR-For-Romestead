using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;

#if !MISSING
namespace Candide
{
    public static class Program
    {
        public static int Calls;

#if CHANGED
        [MethodImpl(MethodImplOptions.NoInlining)]
        public static int Game_UnhandledExceptionHandler(Exception exception)
        {
            Calls++;
            return 7;
        }
#else
        [MethodImpl(MethodImplOptions.NoInlining)]
        public static bool Game_UnhandledExceptionHandler(Exception exception)
        {
            Calls++;
            return true;
        }
#endif

        [MethodImpl(MethodImplOptions.NoInlining)]
        public static void App_DispatcherUnhandledException(object sender, UnhandledExceptionEventArgs args)
        {
            Calls++;
        }
    }
}
#endif

namespace CandideCreator.Shared.Helpers
{
    public static class DebugHelper
    {
        public static int Calls;

        [MethodImpl(MethodImplOptions.NoInlining)]
#if CHANGED
        public static void PrintAndConsole(object str)
#else
        public static void PrintAndConsole(string str)
#endif
        {
            Interlocked.Increment(ref Calls);
            if (Equals(str, "original throws"))
                throw new InvalidOperationException("original exception");
        }
    }
}

namespace Riptide.Utils
{
    // 刻意使用与游戏不同的数字，检查桥是否按名称处理等级。
    public enum LogType { Debug = 10, Info = 20, Warning = 30, Error = 40 }

    public static class RiptideLogger
    {
        public static int Calls;

        [MethodImpl(MethodImplOptions.NoInlining)]
        public static void Log(LogType logType, string message)
        {
            Calls++;
        }

        [MethodImpl(MethodImplOptions.NoInlining)]
        public static void Log(LogType logType, string logName, string message)
        {
            Calls++;
        }
    }
}

namespace Microsoft.Xna.Framework.Input
{
    public static class MessageBox
    {
        public static int Calls;

        [MethodImpl(MethodImplOptions.NoInlining)]
        public static Task<int?> Show(string title, string description, IEnumerable<string> buttons)
        {
            Calls++;
            return Task.FromResult<int?>(2);
        }
    }
}

namespace System.Windows.Forms
{
    public enum MessageBoxButtons { OK, CancelTryContinue }
    public enum MessageBoxIcon { None = 0, Hand = 16, Exclamation = 48 }
    public enum DialogResult { OK = 1, Continue = 11 }

    public static class MessageBox
    {
        public static int Calls;

        [MethodImpl(MethodImplOptions.NoInlining)]
        public static DialogResult Show(string text, string caption, MessageBoxButtons buttons, MessageBoxIcon icon)
        {
            Calls++;
            return DialogResult.Continue;
        }
    }
}
