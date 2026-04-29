# Metal Learning Demo (1-15 全知识点版)

本项目是一个可切换主题的 Metal 学习 Demo。目标是用一个工程把 Metal 的核心概念、工程化技巧和高级渲染路径串起来学习。

你可以在运行时切换 1-15 主题，每个主题对应一个知识点。

## 一图看懂渲染总流程

```text
CVDisplayLink
   |
   v
Renderer.render()
   |
   +--> Scene Pass (MSAA x4 + Depth)
   |       输出: sceneResolveTexture
   |
   +--> Compute: Edge / Bloom / Particles / Upscale (按主题启用)
   |
   +--> Post Pass (MSAA x4)
           采样: scene + edge + bloom + particles + history
           resolve -> drawable.texture
```

## 技术章节：本轮改动与优化总结

### 1. 交互与教学能力增强

- 新增实时参数面板：显示 CPU 帧时、GPU 帧时、显存估算、当前主题参数。
- 新增说明页：每个主题提供原理、实现、常见坑、性能建议。
- 新增错误示例开关：可直接观察“错误配置为什么会慢/会错”。
- 新增单帧 GPU Capture：按 `C` 可导出 `/tmp/MetalDemo_frame.gputrace`。

### 2. 渲染路径可视化

- HUD 现在会显示当前主题实际使用的渲染路径。
- HUD 进一步拆分为：
  - `Scene Path`
  - `Post Path`
  - `Upscale Path`
- 同时显示是否发生 fallback，例如：
  - `ICB pipeline unsupported`
  - `MetalFX unavailable`
- 这样可以区分“主题名称”和“当前机器上真实执行的路径”。

### 3. 性能优化点

- Bloom 改为半分辨率处理，显著降低显存和带宽开销。
- HUD 刷新限频到约 5fps，避免每帧大量 AppKit 字符串更新。
- 用 `os_unfair_lock` 替换高频指标路径上的 `@synchronized`。
- 静态几何 buffer 改为 `Private`，通过 staging buffer 上传。
- history blit 条件收紧，避免无意义的全屏 copy。
- 避免 deferred-like 主题重复执行同一轮 edge compute。

### 4. 稳定性修复点

- 场景 4（ICB）从“初始化失败直接导致应用无法启动”改为“不可用时自动回退 direct draw”。
- ICB 专用 fragment 现在完全不依赖 fragment 资源，使其更符合 ICB 兼容约束。
- 场景 4 已升级为 `3 个对象 / 3 条 ICB 命令` 的多命令示例，而不再只是单 draw demo。
- MetalFX 路径不可用时自动回退到 compute upscale。
- DisplayLink 已迁移到更现代的 macOS 路径，避免旧接口弃用问题。
- `CFBundleIdentifier` 和 `LSMinimumSystemVersion` 构建 warning 已通过 plist/CMake 对齐清理。

### 5. 当前项目的工程化结论

- 这是一个“单工程、多主题、可交互、可观测、可 profile、可降级”的 Metal 教学 Demo。
- 每个主题不只展示概念，还尽量暴露真实工程问题：性能、兼容性、fallback、调试与可视化。
- 目前最有价值的主题包括：
  - 4：ICB 与 fallback
  - 5：Parallel Encoder
  - 8：PBR
  - 14：MetalFX / compute upscale 对比
  - 15：GPU Capture 与 Profiling

## 主题切换方式

- 菜单: Demo -> 1..15
- 键盘:
  - 2..9: 单键立即切换
  - 1: 支持短等待后输入第二位，可切换 10..15
  - Enter: 立即提交
  - Esc: 清空输入缓冲

说明: 已优化切换速度，单数字主题不再等待计时器。

## 渲染后端切换与跨平台

本项目现在支持三种运行时渲染选项：

- Metal：保留原有 1-15 教学主题与高级路径。
- OpenGL 三角形：轻量路径，保留当前三角形主题实现。
- OpenGL 立方体：以立方体为主几何，提供与 Metal 一致的 1-15 主题学习入口。

macOS 运行时切换方式：

- 菜单：`Renderer -> Metal 渲染 (M) / OpenGL 三角形渲染 (O) / OpenGL 立方体渲染 (P)`
- 键盘：`M` 切到 Metal，`O` 切到 OpenGL 三角形，`P` 切到 OpenGL 立方体
- 面板：HUD 顶部分段按钮可直接切换

说明：

- OpenGL 模式已支持与 Metal 对应的 1-15 主题实现（以 OpenGL 方式近似表达相同知识点）。
- OpenGL 主题也支持参数面板与错误示例开关，便于跨后端对照学习。
- 切回 Metal 后会继续沿用你当前预选的主题与参数。

### 非 macOS 构建说明

在 `APPLE=OFF` 场景下，CMake 会构建 `src/OpenGLCrossPlatformMain.cpp`（GLFW + OpenGL）。

依赖：

- OpenGL
- glfw3

示例：

```bash
cmake -S . -B build
cmake --build build
```

## 15 个主题总览

1. Resource And Memory Modes
2. Argument Buffer Binding
3. Function Constants
4. Indirect Command Buffer
5. Parallel Render Encoding
6. Deferred Style Composition
7. Shadowing Techniques
8. PBR Shading
9. HDR Bloom And Temporal
10. Compute Particles
11. Advanced Texture Sampling
12. Synchronization And Scheduling
13. Ray Tracing Fallback
14. MetalFX Style Upscaling
15. Profiling And Debug Markers

---

## 1) Resource And Memory Modes

核心知识:
- 资源生命周期与 CPU/GPU 访问模型
- 纹理重建时机（窗口尺寸变化）

本项目实现:
- 依据 drawable 尺寸动态重建 scene/depth/post 中间纹理
- 使用专门的 ensureRenderTargetsForDrawable 统一管理

观察点:
- 窗口缩放后图像不会错位
- 无黑边、无深度尺寸不匹配问题

---

## 2) Argument Buffer Binding

核心知识:
- 把材质资源作为一个“参数块”绑定到 shader
- 减少离散资源绑定逻辑

本项目实现:
- scene_fragment 保留 argument buffer 参数结构
- CPU 侧通过 argumentEncoder 写入材质纹理并绑定到 buffer index 2
- 为兼容稳定性，shader 路径保留了兼容回退开关（可持续迭代为纯 AB 路径）

观察点:
- 切换到主题 2 时渲染路径稳定，材质仍正常

---

## 3) Function Constants

核心知识:
- 编译期常量决定 shader 变体
- 同一 shader 源码生成多条 pipeline

本项目实现:
- scene_fragment 提供 function constants:
  - kUsePBR
  - kUseShadow
  - kUseArgumentBuffer
- 初始化时创建多个 pipeline 变体:
  - base
  - PBR
  - shadow
  - argument-buffer

观察点:
- 主题 3 会展示不同变体的效果切换

---

## 4) Indirect Command Buffer (ICB)

核心知识:
- 把 draw 命令录制到间接命令缓冲
- 渲染阶段执行 executeCommandsInBuffer

本项目实现:
- 初始化阶段预录制 drawIndexed 到 ICB
- 运行时由 render encoder 执行 ICB
- 为稳定性采用“预录制 + 执行”兼容路径

观察点:
- 主题 4 切换稳定，不再卡住

---

## 5) Parallel Render Encoding

核心知识:
- 利用 parallel render encoder 并行编码 draw 命令
- 降低 CPU 编码阶段瓶颈

本项目实现:
- 主题 5 走 parallelRenderCommandEncoder 路径
- 子 encoder 完成 scene draw 再汇总提交

观察点:
- 主题 5 旋转速度更快，编码路径不同

---

## 6) Deferred Style Composition

核心知识:
- 延迟风格的“先生成中间结果，再组合”思想

本项目实现:
- scene 结果经过 compute 边缘信息，再进入 post 合成
- 虽非完整 GBuffer deferred，但体现了 deferred-like 多阶段组合思路

观察点:
- 主题 6 的边缘与合成权重更明显

---

## 7) Shadowing Techniques

核心知识:
- 阴影会引入额外空间关系与可见性计算
- 常见做法有 shadow map / CSM / ray traced shadow

本项目实现:
- function constants 阴影变体路径
- 通过片元阶段阴影因子调制演示阴影概念

观察点:
- 主题 7 明暗层次比默认主题更强

---

## 8) PBR Shading

核心知识:
- Cook-Torrance BRDF
- roughness/metallic/Fresnel/GGX

本项目实现:
- function constants PBR 变体
- scene_fragment 中实现基础 PBR 计算链路

观察点:
- 主题 8 的高光与材质能量分布更真实

---

## 9) HDR Bloom And Temporal

核心知识:
- HDR 到 LDR 的 tone mapping
- Bloom 亮部提取 + 模糊
- Temporal 混合抑制抖动

本项目实现:
- bright_extract_kernel -> blur_kernel(H/V)
- post 端进行曝光映射和 history 混合
- 参数已调到偏稳健，避免背景偏色

观察点:
- 主题 9 有柔和发光感，不应出现整屏异常色偏

---

## 10) Compute Particles

核心知识:
- Compute 用于生成/更新粒子场
- 与 post 合成形成 GPU 驱动特效

本项目实现:
- particle_overlay_kernel 每帧生成粒子叠加纹理
- post 中按强度融合到最终图像

观察点:
- 主题 10 可看到动态粒子叠加

---

## 11) Advanced Texture Sampling

核心知识:
- mipmap 链
- 各向异性采样

本项目实现:
- 程序化纹理启用 mipmap 并在初始化生成
- 主题 11 使用 maxAnisotropy sampler

观察点:
- 主题 11 在斜角观察时纹理更稳定

---

## 12) Synchronization And Scheduling

核心知识:
- CPU/GPU 帧同步
- in-flight 控制与事件信号

本项目实现:
- 全局使用 in-flight semaphore
- 主题 12 使用 shared event signal 钩子
- 移除主线程阻塞等待，避免卡住

观察点:
- 主题 12 切换后不会卡死，帧节奏稳定

---

## 13) Ray Tracing Fallback

核心知识:
- 设备能力探测 + 兼容回退

本项目实现:
- 检查 device supportsRaytracing
- 根据能力切换效果参数，保持统一可运行

观察点:
- 不同设备上主题 13 可能显示不同强度风格

---

## 14) MetalFX Style Upscaling

核心知识:
- 低分辨率渲染 + 上采样输出

本项目实现:
- downsample_half_kernel
- upscale_linear_kernel
- post 使用上采样结果作为输入

观察点:
- 主题 14 画面风格略有不同，体现上采样链路

---

## 15) Profiling And Debug Markers

核心知识:
- 通过 debug group 给 GPU Capture 建立可读的阶段标记

本项目实现:
- scene 和 frame commit 阶段加 debug group
- 方便在 Xcode GPU Frame Capture 中定位阶段耗时

观察点:
- 主题 15 在 GPU 调试工具中更易分析

---

## 关键文件说明

- src/Renderer.h
  - 主题枚举和切换接口

- src/Renderer.mm
  - 所有主题的核心实现
  - 多 pipeline + 多 compute + post 合成

- shaders/triangle.metal
  - 场景着色器
  - 后处理着色器
  - compute 内核集合（edge/bloom/particles/downsample/upscale）

- src/AppDelegate.mm
  - CVDisplayLink 主循环
  - 菜单与数字切换
  - 切换速度优化逻辑

- CMakeLists.txt
  - macOS Metal 相关框架链接

## 构建与运行

```bash
cmake -S . -B build -G Xcode
cmake --build build --config Debug
open build/Debug/MetalCMakeDemo.app
```

## 性能建议

- 先在主题 1/5/11/12 下观察基础性能
- 再切到 9/10/14 对比 compute/post 开销
- 用 Xcode GPU Capture 分析主题 15 的标记分段

## 已验证结论

- 工程可构建并运行
- 主题切换可用（菜单 + 数字）
- 数字切换延迟已优化
- 你反馈过的问题点（2、4、9、10、12）已逐轮修复并回归
