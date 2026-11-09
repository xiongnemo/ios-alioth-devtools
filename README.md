# iOS alioth devtools

给 Redmi K40（alioth）上的 iOS 16.5 移植（[hakios-alioth](https://github.com/xiongnemo/hakios-alioth)）用的开发工具，
全部由 GitHub Actions 在 macOS 机器上从源码编出来：每次推送都编一遍，产物挂在那次运行的 Artifacts 里；
打 `v<n>` 标签时再发到 Releases。

## debugserver

LLVM 的 `lldb/tools/debugserver`（默认 `llvmorg-19.1.7`），编成 iOS 14+ 的 arm64 程序，ad-hoc 签名，
带 `debugserver/entitlements.plist` 里的权限。没有用 LLVM 的 CMake，`debugserver/build.sh` 直接一个个编译。

- 这是 LLVM 的 “debugserver-nonui”：能附加到正在跑的进程（`--attach=<pid>`、`--waitfor=<进程名>`），能直接启动普通程序；
  不会去叫 SpringBoard / FrontBoard 启动 App（那要用苹果的私有头文件）。调 App 的启动过程就先 `--waitfor`，再打开 App。
- 公开的 iPhoneOS SDK 缺几个 debugserver 要包含的头文件（`mach/mach_vm.h` 只有一行 `#error`，`sys/ptrace.h`、
  `libproc.h`、`sys/proc_info.h`、`bsm/audit_session.h` 和 MIG 用的 `mach/mach_exc.defs` 干脆没有），而它们背后的函数
  iOS 的 libSystem 里都有。编译时用运行机器上 macOS SDK 里的同名文件顶上；这些文件不进本仓库，也不进产物。
- 用法（以 root 跑）：

  ```
  debugserver 0.0.0.0:7777 --attach=<pid>
  debugserver 0.0.0.0:7777 --waitfor=<进程名>
  ```

- 电脑上用 LLVM 19 的 lldb（比如 Debian 的 `lldb-19`）。先把手机那个 iOS 版本的 dyld 共享缓存拆成一个个库，
  当 sysroot 给 lldb：

  ```
  ipsw dyld extract dyld_shared_cache_arm64 --all -o ~/ios-sysroot/16.5-20F66      # 一次就行，约 3 GB
  lldb-19
  (lldb) platform select remote-ios --sysroot ~/ios-sysroot/16.5-20F66
  (lldb) gdb-remote <手机地址>:7777
  ```

  不给 sysroot 的话，lldb 会通过网络从进程内存里一个个读系统库，几分钟都连不完。
- 在 K40 移植（iOS 16.5 20F66）上实测过：附加到 App、列线程、带符号的回溯、读寄存器、`expr (int)getpid()`、
  detach，都正常。移植的内核不给可写又可执行的内存页（debugserver 会让内核记一行 CODE SIGNING），lldb 自己绕过去了。
- 许可：LLVM 的 Apache-2.0 WITH LLVM-exception，包里带 `LICENSE.TXT`。

## Metal 测试着色器

`metal/*.metal` 用 Xcode 的 Metal 编译器编成 `.metallib`（`-std=metal3.0`，最低 iOS 16），另外出一份 `.ll`，
也就是文本形式的 AIR，给翻译 AIR 的那一层对照着看。苹果的编译器本身不在产物里，只有我们自己着色器的编译结果。

`alioth-tests.metal` 每个函数只测一件事，结果在 CPU 上很好算：

- 绘制：`v_fullscreen`（只靠顶点序号的全屏三角形）、`v_colored`（buffer 0 里的位置和颜色）、`f_color`（插值颜色）、
  `f_solid`（buffer 0 里的一个颜色）、`f_texture`（纹理 0 + 采样器 0）
- 裁剪距离：`v_clip1`（全屏三角形加一个 `[[clip_distance]]`，就是 x：左半边被裁掉）、`v_clip2`（两个，x 和 y：只剩右上四分之一）
- 计算：`k_iota`（d[i] = 3i + 1）、`k_add`（c = a + b）、`k_gradient`（往任意格式的纹理写渐变，测写入时的格式转换）、
  `k_reduce`（threadgroup 内存 + barrier + 原子加）、`k_constants`（function constant 0 / 1）
- `k_gradient` 不对时一件件拆开看（v2 起）：`k_sizes` / `k_sizes_rw` / `k_sizes_ro`（只写、读写、只读三种纹理上
  get_width / get_height 的结果）、`k_gradient_n`（尺寸从 buffer 0 来，不查纹理）、`k_gradient16`（half 写入）、
  `k_store_uint`（整数写进 RGBA8Uint）

## Flutter Check

`flutter/` 是一个 Flutter App（`com.anzupop.com.ios.fluttercheck`），用来看 Flutter 自己的渲染器在设备上画得对不对。
Flutter 在 iPhone 上只剩 Impeller 走 Metal 这一条路（没有 OpenGL 后端，拿不到 Metal 设备时引擎直接停掉 App），
所以它也是一个现成的、真实的 Metal 用户。打开就自己跑，结果显示在屏幕上，也写进 App 的 `Documents/fluttercheck.log`
（一行一项：`PASS`/`FAIL`、名字、细节，最后一行 `done`）：

- `frames`：一个一直在动的画面跑 5 秒，用 Flutter 自己的 FrameTiming 算每秒帧数和光栅化时间
- `tree`：屏幕上的控件树读回来（`RenderRepaintBoundary.toImage`）：条纹，右半边盖着 `BackdropFilter` 模糊
- `shapes`、`layers`：矩形、圆、裁剪路径、线性渐变、半透明图层，画进离屏图片再逐点比对
- `shader`：App 自己的片段着色器（`shaders/quarters.frag`，构建时由 impellerc 编译），四个象限四种颜色，看方向对不对
- `blur`：高斯模糊的边缘是不是由暗到亮
- `image`：像素做的小图放大画出来，再经过 PNG 编码、解码读回
- `text`：中英文文字（系统字体）画出来，有深色笔画和抗锯齿的边

`flutter.yml` 在 macOS 机器上用 Flutter stable 编（`flutter create` 生成 iOS 工程外壳，再换上这里的 Dart 代码和着色器），
ad-hoc 签名，打成 `FlutterCheck.ipa` 挂在运行的 Artifacts 里。只改 `flutter/` 的推送不会再编 debugserver。

## 在自己的 Mac 上编

```
bash debugserver/build.sh      # build/debugserver/
bash metal/build.sh            # build/metal/
bash flutter/build.sh          # build/flutter/（要 PATH 里有 flutter）
```

要 Xcode（Xcode 26 起 Metal 编译器要另外下载，`metal/build.sh` 会自己调 `xcodebuild -downloadComponent MetalToolchain`）。

## 许可

本仓库的脚本和着色器：MIT（见 `LICENSE`）。编出来的 debugserver 是 LLVM 的代码，按 LLVM 的许可。
