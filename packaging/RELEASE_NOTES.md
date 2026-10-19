# Romestead BepInEx 0.4.1

-- English --

Synced selected BepInEx be.783 core fixes
- Removed a duplicate byte TOML type converter registration.
- Config enumeration now uses a snapshot under lock to avoid concurrent modification errors.
- String hashing now uses the full UTF-8 byte length for non-ASCII text.

The 0.4.2 game logging additions have been withdrawn from the loader. Game log forwarding is available separately as the optional GameLogBridge plugin.

-- Chinese --

同步 BepInEx be.783 的相关核心修复
- 移除重复注册的 byte TOML 类型转换器。
- 配置枚举使用锁内快照，避免并发修改错误。
- 非 ASCII 字符串哈希使用完整 UTF-8 字节长度。

已从加载器撤回 0.4.2 的游戏日志相关改动。游戏日志转发以独立可选插件 GameLogBridge 提供。
