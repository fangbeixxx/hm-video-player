# 鸿蒙平板视频播放器

HarmonyOS 平板原生视频播放器，使用 ArkTS + ArkUI 开发，集成 IjkPlayer / AVPlayer 双引擎。

## 功能特性

### 本地播放
- 📁 本地视频自动扫描
- 🎬 播放控制（播放/暂停、进度拖拽、快进快退 ±10s）
- ⏩ 变速播放（0.5x / 0.75x / 1.0x / 1.25x / 1.5x / 2.0x）
- ✋ 手势控制（左侧滑动调亮度、右侧滑动调音量、水平滑动快进快退）
- 🔉 静音切换、音量调节
- 📝 播放历史记录（自动保存/恢复进度）
- ⭐ 视频收藏

### 在线播放
- 🌐 在线影视源播放（支持 CatVod / T3 / AppleCMS / 简易 JSON API）
- 📺 IPTV 直播源（M3U / M3U8 / TXT 格式）
- 📥 视频下载管理
- 🔍 在线视频搜索
- 🏷️ 分类筛选、多源切换

### 播放增强
- 💬 弹幕功能（支持开关、发送预置弹幕、Bilibili XML 解析）
- 📝 外挂字幕（SRT / ASS / SSA / VTT，支持编码自动检测）
- ⏱️ 字幕延迟调节
- 🎯 清晰度切换（Auto / 多档清晰度）
- 🖼️ 画中画（PiP，系统级 `supportPiPMode`）

### 双引擎支持
- **IjkPlayer**（FFmpeg）：全格式软解，支持内挂字幕
- **AVPlayer**（系统）：MP4/M4V/MOV 等格式硬解，低功耗
- 播放失败自动降级：AVPlayer → IjkPlayer

### 国际化
- 🌍 中 / English 应用内切换
- 🔤 跟随系统语言自动适配

### 平板适配
- 📱 横竖屏自适应（Auto / 横屏 / 竖屏）
- 🪟 分屏 / 小窗 / 全屏多窗口模式
- ⌨️ 键盘快捷键支持

## 项目结构

```
entry/src/main/ets/
├── entryability/
│   └── EntryAbility.ets              # 应用入口
├── pages/
│   ├── Index.ets                     # 首页（本地视频/最近播放/收藏）
│   ├── PlayerPage.ets                # 播放页
│   ├── SearchPage.ets                # 搜索页
│   ├── SettingsPage.ets              # 设置页
│   └── OnlinePage.ets                # 在线视频页
├── components/
│   ├── ControlPanel.ets              # 播放控制面板（手势/菜单/进度）
│   ├── VideoPlayerView.ets           # 播放器视图（双引擎）
│   ├── VideoCard.ets                 # 本地视频卡片
│   ├── OnlineMediaCard.ets           # 在线视频/频道卡片
│   ├── DanmakuLayer.ets              # 弹幕渲染层（Canvas）
│   └── ErrorDialog.ets               # 错误弹窗/Toast
├── service/
│   ├── VideoPlayerManager.ets        # AVPlayer 封装
│   ├── MediaScanner.ets              # 媒体扫描（photoAccessHelper + 文件系统）
│   ├── PlayHistoryService.ets        # 播放历史持久化
│   ├── SettingsService.ets           # 设置持久化（含语言偏好）
│   ├── SourceManager.ets             # 在线源管理（增删改查+缓存）
│   ├── DownloadManager.ets           # 视频下载管理
│   └── PiPManager.ets                # 画中画状态管理
├── model/
│   ├── VideoItem.ets                 # 本地视频/播放记录/播放列表
│   ├── OnlineMedia.ets               # 在线视频/IPTV/API 响应模型
│   └── DanmakuItem.ets               # 弹幕数据模型
├── utils/
│   ├── TimeUtils.ets                 # 时间格式化/相对时间
│   ├── FileUtils.ets                 # 文件大小/格式工具
│   ├── DanmakuEngine.ets             # 弹幕引擎（对象池/碰撞检测）
│   ├── SourceParser.ets              # 在线源解析（M3U/JSON API）
│   └── LocalizationManager.ets       # 中英文切换引擎
├── common/
│   ├── Constants.ets                 # 全局常量
│   ├── Enums.ets                     # 枚举（播放状态/速度/语言等）
│   └── PlayerError.ets               # 错误码/错误信息
└── native/
    └── FFmpegNative.ets              # FFmpeg NAPI 桥接
```

## 开发环境

- DevEco Studio 5.0+
- HarmonyOS SDK API 12+（compileSdk 6.1.0）
- 目标设备：HarmonyOS 平板（tablet）
- 依赖：`@ohos/ijkplayer`（IjkPlayer NAPI）

## 设置项一览

| 分类 | 设置项 | 说明 |
|------|--------|------|
| 播放 | 自动播放下一集 | 播放列表自动切换 |
| 播放 | 硬件加速 | MP4 等格式优先用 AVPlayer 硬解 |
| 播放 | 后台播放 | 退到后台继续音频播放 |
| 播放 | 默认速度 | 0.5x - 2.0x |
| 显示 | 屏幕方向 | 自动 / 横屏 / 竖屏 |
| 显示 | **语言** | System / 中文 / English |
| 显示 | 显示字幕 | 内挂+外挂字幕开关 |
| 网络 | 仅 Wi-Fi | 移动数据下不播放在线视频 |

## 使用方法

1. 用 DevEco Studio 打开项目
2. 连接鸿蒙平板或启动模拟器
3. 点击 Run 运行

> **签名配置**：首次运行需在 `File → Project Structure → Signing Configs` 中配置签名证书。

## 更新日志

### v1.1.0（当前）
- ✅ 在线视频播放（影视源 + IPTV 直播）
- ✅ 视频下载管理
- ✅ 外挂字幕加载（SRT/ASS/SSA/VTT）
- ✅ 弹幕功能（Canvas 渲染 + 碰撞检测）
- ✅ 清晰度切换
- ✅ 画中画（PiP）
- ✅ 中英文切换（应用内）
- ✅ 双引擎自动降级（AVPlayer → IjkPlayer）
- ✅ 错误弹窗（含错误码/重试）
- ✅ 手势控制（亮度/音量/进度）

### v1.0.0
- 本地视频扫描与播放
- 播放控制（播放/暂停、进度、快进快退）
- 变速播放
- 播放历史记录
- 视频搜索
- 基础设置页面
- 平板适配
