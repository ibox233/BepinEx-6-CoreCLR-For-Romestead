# Romestead BepInEx 0.4.2

-- English --

Added game log forwarding
- Supported game logs, Riptide network logs, exception details, and error dialog text now appear in the BepInEx console and `BepInEx/LogOutput.log`.
- Added `[Logging.Game] Enabled` in `BepInEx.cfg`, enabled by default.
- Original game logging, dialogs, and exception handling are preserved.
- Unavailable or changed logging methods are skipped so optional log forwarding does not stop plugin loading.

Added loader build information
- Startup logs now show the Romestead loader version, UTC build date, and source commit.

Errors occurring before the log bridge starts are not captured. The upstream baseline remains BepInEx be.783.

-- Chinese --

新增游戏日志转发
- 将已支持的游戏日志、Riptide 网络日志、异常详情和错误弹窗文本输出到 BepInEx 控制台及 `BepInEx/LogOutput.log`。
- 在 `BepInEx.cfg` 中新增 `[Logging.Game] Enabled`，默认开启。
- 保留游戏原有日志、弹窗和异常处理行为。
- 日志方法缺失或签名变化时跳过对应入口，避免可选的日志转发阻止插件加载。

新增加载器构建信息
- 启动日志显示 Romestead 加载器版本、UTC 构建日期和源代码 commit。

日志桥启动之前发生的错误无法捕获。上游基线仍为 BepInEx be.783。
