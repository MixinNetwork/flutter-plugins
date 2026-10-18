# desktop_webview_window Windows 测试交接

> 历史交接记录：以下内容针对 0.3.x 的 Windows 实现，部分 API 和导航流程已被替换。
> 当前用法和测试入口见[主 README](../README.md) 与 [example README](../example/README.md)。

更新时间：2026-10-12

## 当前状态

PR [#508](https://github.com/MixinNetwork/flutter-plugins/pull/508) 已合并。原作者的实现、后续三个修复、回归测试和 Windows CI 已一起进入 `main`。

- 合并提交：[`ecbe6d54c2d85adc9fba03309d11d172b3c527c8`](https://github.com/MixinNetwork/flutter-plugins/commit/ecbe6d54c2d85adc9fba03309d11d172b3c527c8)。
- [合并后的 Windows CI](https://github.com/MixinNetwork/flutter-plugins/actions/runs/38214976383) 已通过。
- 已[评论感谢作者](https://github.com/MixinNetwork/flutter-plugins/pull/508#issuecomment-6119315269)。
- 未准备 pub.dev 发布，没有更新包版本或发布 changelog。
- PR #439 未合并，不在此次验证范围内。

本次剩余工作是：在真实 Windows 环境中，用实际应用确认窗口显示、跳转和真实媒体权限行为。

## 实现与修复

| 内容 | 当前行为 |
| --- | --- |
| 导航等待 | Dart 允许跳转后，等待对应的取消导航完成，再重新导航，避免导航被一起取消而白屏。 |
| 新导航覆盖旧请求 | 新的导航或停止操作会使旧等待项失效。旧请求的迟到结果不能再把页面带回旧地址。 |
| 隐藏启动 | `CreateConfiguration(openHidden: true)` 创建时不显示窗口。调用显示接口后再展示。 |
| 最大化恢复 | `bringToForeground(maximized: true)` 同时恢复窗口和 WebView 可见性，避免窗口出现但网页仍隐藏。 |
| 媒体拒绝 | `CreateConfiguration(denyCameraAndMicrophone: true)` 拒绝该窗口的摄像头和麦克风请求，拒绝结果不写入共享 profile。 |

两个新配置项都默认为 `false`。只有开启 `denyCameraAndMicrophone` 时，才要求 WebView2 Runtime **111.0.1661.34 或以上**；旧运行时开启此选项会导致窗口创建失败。

预期显示流程：

```text
创建隐藏窗口 -> 后台加载网页 -> 显示/最大化 -> 网页可见且能交互
                                   |
                                再次隐藏
                                   |
                              再次显示/最大化
                                   |
                              网页恢复可见
```

## 已有验证

- 本地 4 个现有 Dart/Flutter 测试通过。
- Dart 静态分析通过。
- Windows 原生插件和 example 编译通过。
- 合并后的 Windows CI 中，3 个集成测试全部通过：
  1. 新的显式导航替代旧的 URL 审批请求，最终停留在新地址。
  2. 隐藏启动后最大化显示、再次隐藏后最大化显示，网页均恢复可见。
  3. 摄像头和麦克风请求被拒绝后，用同一 profile 创建普通窗口，其权限仍为 `prompt`。

导航和可见性测试已在未修复版本上复现失败，再在修复版本上通过。

集成测试使用 localhost 页面、临时 profile 和虚拟媒体设备。它验证了权限策略，但不代表真实摄像头、麦克风以及业务网站已经完成验证。

## Windows 上准备环境

1. 准备支持 Windows 桌面构建的 Flutter SDK，以及 Visual Studio 的 C++ 桌面开发工具链。仓库要求 Dart SDK 3.11 或以上。
2. 确保安装 WebView2 Runtime。媒体拒绝选项需要上述最低运行时版本。
3. 在普通 PowerShell 中操作，避免管理员模式。需要检查工具链时执行 `flutter doctor -v`。
4. 拉取 `main`，确认包含合并提交：

```powershell
git switch main
git pull --ff-only
git merge-base --is-ancestor ecbe6d54c2d85adc9fba03309d11d172b3c527c8 HEAD
```

最后一条命令的退出码应为 `0`。如果 checkout 有未提交修改，先妥善保存，不要强制覆盖。

如果在业务应用中测试，确认依赖指向这份本地插件代码，而不是旧的 pub.dev 版本。例如，在业务应用的 `pubspec.yaml` 中临时设置：

```yaml
dependency_overrides:
  desktop_webview_window:
    path: C:/path/to/flutter-plugins/packages/desktop_webview_window
```

把路径替换为实际目录，然后在业务应用运行 `flutter pub get`。

## 先运行现成测试

以下命令从 `flutter-plugins` 仓库根目录开始：

```powershell
dart pub get

cd packages/desktop_webview_window
flutter test --no-pub

cd example
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = '--use-fake-device-for-media-stream'
try {
  flutter test integration_test/windows_webview_test.dart -d windows --timeout 5m
} finally {
  Remove-Item Env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS -ErrorAction SilentlyContinue
}
```

预期：4 个现有测试和 3 个 Windows 集成测试全部通过。

测试入口：`packages/desktop_webview_window/example/integration_test/windows_webview_test.dart`。

虚拟媒体参数仅用于测试。真实设备测试前应清除该环境变量。提权的 WebView2 进程会忽略这类环境变量；仓库 CI 已针对临时 Windows runner 使用机器级配置，手工运行时使用普通 PowerShell 即可。

## 再进行实际应用验收

先用 Debug 测试，再用 Release 重复核心流程。业务应用可使用 `flutter run -d windows` 和 `flutter run -d windows --release` 启动。

| 场景 | 操作 | 通过标准 |
| --- | --- | --- |
| 普通导航 | 打开网页、点击链接、执行登录或支付跳转。分别覆盖默认拦截和 `triggerOnUrlRequestEvent: false`。 | 不白屏，不丢失跳转，不意外回到旧地址。 |
| 业务导航拦截 | 回调允许一个地址、拒绝另一个地址。 | 允许的地址正常打开；拒绝的地址不进入。 |
| 隐藏启动 | 使用 `openHidden: true`，页面准备好后调用 `setWebviewWindowVisibility(true)`。 | 加载期间不出现空白窗口；显示后有内容且能点击、滚动。 |
| 隐藏后最大化 | 隐藏窗口，再调用 `bringToForeground(maximized: true)`，重复几次。 | 窗口和网页一起恢复，不出现空白内容区。 |
| 真实媒体拒绝 | 使用 `denyCameraAndMicrophone: true`，分别请求摄像头、麦克风。 | 请求被拒绝，不弹出访问提示，设备不启动。 |
| 普通窗口权限 | 关闭拒绝媒体的窗口。使用相同 `userDataFolderWindows` 和相同网站 origin，创建 `denyCameraAndMicrophone: false` 的窗口，再请求媒体权限。 | 不继承前一窗口的拒绝。没有其他既有限制时，可以正常授权使用设备。 |
| 窗口基本操作 | 拖动、缩放、最大化、还原、关闭，再打开窗口。 | 不崩溃，无异常留白，交互正常。 |
| 标题栏 | 保留标题栏初始化 hook 时检查控件；如业务应用省略 hook，也检查网页填满可用内容区。 | 标题栏控件按预期工作，省略 hook 时没有多余的标题栏占位。 |

真实媒体测试应满足：

- 页面使用 HTTPS 或 localhost。
- 机器有可用的摄像头和麦克风，Windows 系统允许应用访问。
- 页面没有通过 `Permissions-Policy` 自行禁止请求，否则请求可能根本没有进入插件的权限处理。
- 用干净的测试 profile，避免已有的网站拒绝设置影响结论。验证“不串权限”时，两个窗口必须共用该 profile 和同一个 origin。

如果返回 `NotFoundError`，表示没有找到设备，不能据此证明权限拒绝逻辑有效。

## 发现异常时交接的信息

保留以下信息即可，不必先增加测试框架或做大范围重构：

- 当前 Git commit、Flutter 版本、Windows 版本、WebView2 Runtime 版本。
- Debug 或 Release，以及应用是否以管理员身份运行。
- 使用的配置项、导航是否触发 URL 回调、是否共用 profile。
- 最短复现步骤、预期结果、实际结果。
- 对应测试的完整失败输出；显示问题附截图或短录屏。
- 媒体问题记录是权限拒绝、找不到设备，还是授权后无法采集。

导航问题优先记录“请求顺序、回调结果、最终地址”。显示问题优先区分“外层窗口未显示”和“窗口已显示但网页仍空白”。

## 完成标准

- 自动测试通过。
- Debug 和 Release 中，隐藏启动、隐藏后最大化、常用业务跳转均正常。
- 真实设备上，拒绝窗口不启动摄像头或麦克风；普通窗口不继承该拒绝。
- 没有新增的窗口关闭崩溃或标题栏布局回归。

确认这些结果后，另行决定是否准备包发布；此次交接不包含发布操作。
