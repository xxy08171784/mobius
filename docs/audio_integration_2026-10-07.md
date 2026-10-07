# 0.4.1 音频接入与编辑入口

来源为团队提供的 `D:\Desktop\音频`，共 26 个文件。桌面原文件不改动；游戏使用 `assets/audio/` 内的便携版本，运行和打包都不依赖桌面路径。

## 已接入的位置

| 原文件 / 内容 | 游戏中的触发位置 |
| --- | --- |
| Mu--Open | 主菜单、选角、菜单内图鉴与设置；循环 |
| Mu--Main scene | 路线地图、部署、商店、事件、休息；循环 |
| Mu--Fight | 正式战斗，包括恢复战斗存档；循环 |
| Mu--Win | 每场新战斗胜利时播放一次，战利品停留时播完转路线音乐；最终通关也播放一次 |
| Mu--Lose | 战败结算播放一次，替换战斗音乐 |
| button1 / UI button | 普通按钮与卡牌选择 / 出牌确认及结束回合按钮；暂停菜单同样有效 |
| Map Open / Map Close | 进入路线地图 / 选择节点离开地图 |
| Card_draw | 初始发牌、下一回合补牌、技能抽牌；同批多张牌合并发声 |
| Card_use_fly | 成功提交单牌或组合后播放一次；拖动预览、无效释放、取消二次选牌不播放 |
| Card_level_up | 休息点成功升级；“留一手”成功升级抽来的战斗副本 |
| Defend(shield up) | 结算实际获得护盾时，玩家和敌人均适用 |
| be attacked(player) | 玩家实际损失生命时；全部被盾吸收时不会误播受伤音 |
| Fist_punch | 普通拳击与默认近身攻击命中 |
| Sword1 | 飞刀、饮血剑、重影刀、刺透命中 |
| Sword2（heavy） | 索命刀、砍爆命中 |
| 技能/Sword | 冲刺斩、旋风斩、妖刀命中，按确认用于剑类技能 |
| Grass_walk / Stone_walk | 玩家逐格移动落地时；第一章默认草地，后两章默认石地；减少动画模式只播一次 |
| Water_walk | 已接到显式水地形的脚步接口；当前棋盘装饰水渍没有地形语义，不会当成实际水地形 |
| Reward | 选取奖励卡、收下宝箱、成功购买卡牌；放弃奖励或购买失败不播放奖励音 |
| 篝火 MP3 | 休息点及升级选择页的低音量环境循环，离开休息点即停止 |

`技能/Sword.wav` 与 `Sword2（heavy）.wav` 的原文件 SHA-256 相同，当前声音相同；保留独立绑定，后续可分别替换。

按已确认的意见，`Dice`、`Water_appear`、`Posion trap` 登记为预留资源，当前不会自动触发。未增加骰子、水面生成或毒陷阱机制。

## 音量、循环和触发边界

- 背景音乐与胜负短曲均走 Music 总线；动作、按钮和篝火走 SFX 总线；设置中的总音量、音乐、音效分别控制。
- 场景切换采用短淡出/淡入，同一场景重建和商店刷新不重启音乐。胜负曲不循环，快速返回菜单会取消尚未执行的音乐切换。
- 读档只恢复该场景的背景音乐，不重新播放历史攻击、升级、发牌或胜利音。预演只算规则，不播放动作音。
- 音效池 12 声部，同一音效最多同时 2 声部，75 毫秒内重复请求合并。群体攻击与快速补牌不会逐目标无限叠音。
- 暂停时音乐继续，暂停菜单按钮可发声。退出游戏先停止音频，屏蔽后续按钮和动作回调，并留出约 0.35 秒供混音线程及主线程回收播放实例。
- 音效不消费战斗随机数，不修改卡牌、生命、牌序或存档。伤害事件只新增 `payload.card_uid` 表现元数据，用于组合中区分拳击与剑声。

## 编辑与对外接口

在 Godot 右侧 **Mobius 工作台 → 音频** 打开 `content/audio/default_audio.tres`，可直接拖入替换音轨、调整各项音量，以及编辑 `card_attack_cues` 的卡牌 ID → 音效键映射。

| 入口 | 用途 |
| --- | --- |
| `content/audio/default_audio.tres` | 全部音频槽位，Inspector 分类为音乐、界面与环境、战斗、混音、预留 |
| `core/audio/audio_catalog.gd` | 槽位类型、默认混音值和卡牌音色映射 |
| `AudioService.enter_scene(key)` | 切换音乐与环境音；key 为 menu/route/deployment/battle/rest/shop/event/treasure/reward/victory/defeat |
| `AudioService.play_cue(key)` | 按已登记音效键播放，包含防叠音控制 |
| `AudioService.play_jingle(key, afterwards)` | 单次音乐短曲及播完后要切回的音乐 |
| `AudioService.set_campfire(enabled)` | 控制篝火循环 |
| `AudioService.shutdown()` / `quit_game()` | 停止并回收播放实例 / 安全退出 |
| 按钮 metadata `audio_cue` | 普通按钮自动播 click；设为 confirm 可改确认音，设为空字符串可静音 |
| `presentation/battle/battle_audio_feedback.gd` | 已接受命令、伤害、护盾、抽牌、升级与脚步的表现映射 |
| `CellState.terrain_key` | water / terrain.water / shallow_water 选水声，grass / terrain.grass 选草声，其余显式地形选石声 |
| `AudioService.cue_started` / `music_started` | 调试与测试信号，不参与规则结算 |

## 文件转换与验证

`tools/import_audio.py` 可重复从原始文件生成游戏资源。原始音乐包含浮点 WAV，部分音效采样率高达 192 kHz：游戏版统一为 48 kHz，短音效使用 16 位 WAV，音乐与环境使用 MP3。仅调整固定增益并重采样，不压缩动态、不截断声音。预留峰值余量后再由游戏内混音控制响度。26 个游戏文件约 10.21 MiB；来源路径、哈希、每个文件增益与输出哈希在 `assets/audio/sources.json`。

```powershell
python tools/import_audio.py --source 'D:\Desktop\音频' --ffmpeg '<本机 FFmpeg 路径>'
```

音频目录在新的无缓存项目中检查过首次导入；AudioCatalog 在运行时加载，避免首次导入前解析音轨失败。

`tests/audio_smoke.tscn` 检查全部资源长度、音乐实际播放与循环、胜利后回到路线、快速切场景、读档不重播胜利、篝火离场停止、设置总线、暂停按钮、卡牌预演静音、成功攻击/护盾/临时升级、实际移动脚步与补牌。另在内部 SFX 总线录制一段 WAV，确认解码和混音输出存在有效波形；不访问麦克风。自动测试使用 Dummy 音频驱动，避免反复运行时向系统扬声器播放音效。

`tools/verify_project.py` 已纳入音频测试；`tools/verify_export.py` 从实际发布 PCK 检查音频资源、战斗音乐和成功拖牌后的音效。真人试听仍用于确认音乐风格、响度偏好和循环接缝是否满意。

本轮试玩包：`builds/playtest/Mobius-0.4.1-Audio-Windows-x64.zip`。完整解压，一起保留 EXE 与 PCK。
