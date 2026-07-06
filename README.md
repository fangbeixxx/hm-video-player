# 鸿蒙平板视频播放器

HarmonyOS 平板原生视频播放器，使用 ArkTS + ArkUI 开发。

## 功能特性

- 📁 本地视频扫描与播放
- 🎬 播放控制（播放/暂停、进度拖拽、快进快退）
- ⏩ 变速播放（0.5x - 2.0x）
- 📝 播放历史记录（自动保存进度）
- 🔍 视频搜索
- ⚙️ 设置页面（硬件加速、自动连播、屏幕方向等）
- 📱 平板大屏适配（横竖屏自适应、分屏/小窗支持）
- ⌨️ 键盘快捷键支持

## 项目结构

```
entry/src/main/ets/
├── entryability/EntryAbility.ets   # 应用入口
├── pages/
│   ├── Index.ets                   # 首页（视频列表）
│   ├── PlayerPage.ets             # 播放页
│   ├── SearchPage.ets             # 搜索页
│   └── SettingsPage.ets           # 设置页
├── components/
│   ├── ControlPanel.ets           # 播放控制面板
│   ├── VideoCard.ets              # 视频卡片组件
│   └── VideoPlayerView.ets        # 播放器视图
├── service/
│   ├── VideoPlayerManager.ets     # AVPlayer 封装
│   ├── MediaScanner.ets           # 媒体扫描
│   └── PlayHistoryService.ets     # 历史记录
├── model/
│   └── VideoItem.ets              # 数据模型
├── utils/
│   ├── TimeUtils.ets              # 时间工具
│   └── FileUtils.ets              # 文件工具
└── common/
    ├── Constants.ets               # 常量定义
    └── Enums.ets                   # 枚举定义
```

## 开发环境

- DevEco Studio 5.0+
- HarmonyOS SDK API 12+
- 目标设备：HarmonyOS 平板

## 使用方法

1. 用 DevEco Studio 打开项目
2. 连接鸿蒙平板或启动模拟器
3. 点击 Run 运行

## 待开发

- [✔] 在线视频播放（M3U8/HTTP 流）
- [ ] 字幕加载（SRT/ASS）
- [ ] 弹幕功能
- [ ] 视频下载
- [ ] 清晰度切换
- [✔] 手势控制（滑动调音量/亮度/进度）
- [ ] 画中画（PiP）
