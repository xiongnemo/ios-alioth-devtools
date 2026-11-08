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

  电脑上：`lldb`，然后 `process connect connect://<手机地址>:7777`。
- 许可：LLVM 的 Apache-2.0 WITH LLVM-exception，包里带 `LICENSE.TXT`。

## Metal 测试着色器

`metal/*.metal` 用 Xcode 的 Metal 编译器编成 `.metallib`（`-std=metal3.0`，最低 iOS 16），另外出一份 `.ll`，
也就是文本形式的 AIR，给翻译 AIR 的那一层对照着看。苹果的编译器本身不在产物里，只有我们自己着色器的编译结果。

`alioth-tests.metal` 每个函数只测一件事，结果在 CPU 上很好算：

- 绘制：`v_fullscreen`（只靠顶点序号的全屏三角形）、`v_colored`（buffer 0 里的位置和颜色）、`f_color`（插值颜色）、
  `f_solid`（buffer 0 里的一个颜色）、`f_texture`（纹理 0 + 采样器 0）
- 计算：`k_iota`（d[i] = 3i + 1）、`k_add`（c = a + b）、`k_gradient`（往任意格式的纹理写渐变，测写入时的格式转换）、
  `k_reduce`（threadgroup 内存 + barrier + 原子加）、`k_constants`（function constant 0 / 1）

## 在自己的 Mac 上编

```
bash debugserver/build.sh      # build/debugserver/
bash metal/build.sh            # build/metal/
```

要 Xcode（Xcode 26 起 Metal 编译器要另外下载，`metal/build.sh` 会自己调 `xcodebuild -downloadComponent MetalToolchain`）。

## 许可

本仓库的脚本和着色器：MIT（见 `LICENSE`）。编出来的 debugserver 是 LLVM 的代码，按 LLVM 的许可。
