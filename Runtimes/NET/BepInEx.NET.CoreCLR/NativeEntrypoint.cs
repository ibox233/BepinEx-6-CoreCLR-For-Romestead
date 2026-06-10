using System;

namespace BepInEx.NET.CoreCLR
{
    public static class NativeEntrypoint
    {
        public static int Initialize(IntPtr args, int sizeBytes)
        {
            StartupHook.Initialize();
            return 0;
        }
    }
}
