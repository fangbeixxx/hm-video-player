# HarmonyOS Video Player Build Notes

本文记录这次把项目从无法构建推进到 `assembleHap` 成功的经验，重点是 Windows 构建环境、WSL 重编 FFmpeg、Native/ArkTS 分层排错，以及当前 SDK 的兼容性坑。

## 1. 最终构建命令

在 Windows PowerShell 中运行：

```powershell
$env:Path='C:\Program Files\Huawei\DevEco Studio\tools\node;' + $env:Path
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio\sdk'

& 'C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' --mode module -p product=default assembleHap --no-daemon --stacktrace
```

成功时应看到：

```text
Finished :entry:default@CompileArkTS
Finished :entry:default@PackageHap
BUILD SUCCESSFUL
```

HAP 输出路径：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

当前产物是 unsigned，因为根目录 `build-profile.json5` 还没有配置签名。

## 2. WSL 重编 FFmpeg

WSL 中安装/解压了 Linux 版 command-line tools，并安装 OpenHarmony SDK native/toolchains：

```text
command-line tools: /home/pp/ohos-cli/harmonyos-2.0.0.2/command-line-tools
OpenHarmony SDK:    /home/pp/ohos-sdk
Native NDK:         /home/pp/ohos-sdk/openharmony/9/native
```

WSL 默认 Java 11 不够用，实际使用 Java 17：

```bash
export JAVA_HOME="$HOME/ide/android-studio/jbr"
export PATH="$JAVA_HOME/bin:$PATH"
```

安装 OpenHarmony SDK 包：

```bash
CLT="$HOME/ohos-cli/harmonyos-2.0.0.2/command-line-tools"
SDK="$HOME/ohos-sdk"
"$CLT/bin/sdkmgr" install --sdk-directory="$SDK" --accept-license --no-ssl-verify OpenHarmony/native:9 OpenHarmony/toolchains:9
```

重编 FFmpeg：

```bash
cd /mnt/d/DevEcoStudioProjects/harmonyos-video-player
export OHOS_NDK="$HOME/ohos-sdk/openharmony/9/native"
export PATH="$OHOS_NDK/llvm/bin:$PATH"
bash scripts/build_ffmpeg.sh arm64-v8a
```

脚本中的关键修复：

```text
--disable-asm
clang --target=aarch64-linux-ohos
clang++ --target=aarch64-linux-ohos
```

`--disable-asm` 很关键，可以避开 FFmpeg NEON 汇编对象在 OpenHarmony 交叉编译工具链下的问题，例如 `tx_float_neon.o`。

重编后的库位置：

```text
entry/src/main/cpp/libs/ffmpeg/lib/arm64-v8a
```

## 3. Native 层经验

当 FFmpeg 静态库重编完成后，CMake/Ninja 已经可以通过。后续错误集中在 ArkTS 编译层，不应继续在 FFmpeg 或 C++ 链路上绕圈。

实际 native 输出名是：

```text
libharmonyos-video-player.so
```

ArkTS 侧要按这个名字导入：

```ts
import nativeModule from 'libharmonyos-video-player.so';
```

C++ NAPI 注册名也要和该模块名保持一致。

## 4. ArkTS 严格模式经验

ArkTS 不能完全按普通 TypeScript 写。以下写法会触发严格模式错误：

```text
Record<>
Omit<>
any / unknown
globalThis
requireNapi
@ts-ignore
Object.assign
import 放在文件中间
对象字面量使用数字 key
自定义组件后面链式挂回调
```

错误示例：

```ts
VideoCard({ video: video }).onClicked((v: VideoItem) => this.goToPlayer(v))
```

推荐写法：

```ts
VideoCard({
  video: video,
  onClicked: (v: VideoItem) => this.goToPlayer(v)
})
```

遇到 `Record`、数字 key map、类型扩展等问题时，优先改成显式 interface/class、`switch`、普通数组或普通方法。

## 5. 当前 SDK API 差异

这次遇到的不兼容点：

```text
photoAccessHelper 不能从 @kit.CoreFileKit 导入
VideoOptions 没有 surfaceId
SheetSize.AUTO 不存在
Circle 没有 fillColor，要用 fill
media.BufferingInfoType.BUFFERING_LOADING 不存在
自定义 PlaybackSpeed 不能直接 cast 成 media.PlaybackSpeed
List.divider({ color }) 缺少 strokeWidth
```

对应处理：

```text
后续恢复媒体扫描时使用 @ohos.file.photoAccessHelper
ArkUI Video 使用 Video({ src })
SheetSize.AUTO 改为 SheetSize.MEDIUM 等已有枚举
Circle().fillColor(...) 改为 Circle().fill(...)
缓冲状态先使用 BUFFERING_START 判断
PlaybackSpeed 用 switch 映射到 media.PlaybackSpeed
List.divider 使用 { color, strokeWidth }
```

## 6. 资源经验

所有 `$r('app.media.xxx')` 引用都必须有实际资源文件。缺图标会直接导致 ArkTS 编译失败。

这次补齐了播放器控制、搜索、设置、返回、占位图等 SVG，占位资源目录：

```text
entry/src/main/resources/base/media
```

## 7. 当前取舍和后续事项

为了先完成构建，`MediaScanner` 暂时降级为编译安全的空扫描实现。后续要恢复本地视频列表，需要基于当前 SDK 的 `@ohos.file.photoAccessHelper` 重新接入，并使用 ArkTS 友好的显式类型。

当前仍有一些 warning，例如 deprecated router API、函数可能抛异常、NAPI d.ts 未验证等，但不影响 `assembleHap`。
