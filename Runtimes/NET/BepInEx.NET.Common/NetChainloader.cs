using System;
using System.Reflection;
using BepInEx.Bootstrap;
using BepInEx.Preloader.Core.Logging;

namespace BepInEx.NET.Common
{
    public class NetChainloader : BaseChainloader<BasePlugin>
    {
        // TODO: Remove once proper instance handling exists
        public static NetChainloader Instance { get; set; }

        public override void Initialize()
        {
            Instance = this;
            base.Initialize();
        }

        public override BasePlugin LoadPlugin(PluginInfo pluginInfo, Assembly pluginAssembly)
        {
            var type = pluginAssembly.GetType(pluginInfo.TypeName);

            var pluginInstance = (BasePlugin) Activator.CreateInstance(type);

            pluginInstance.Load();

            return pluginInstance;
        }

        protected override void InitializeLoggers()
        {
            base.InitializeLoggers();

            ChainloaderLogHelper.RewritePreloaderLogs();
        }
    }
}
