# MetalCMakeDemo 学习对话记录

- 时间：2026-04-21
- 项目：`/Users/mtl/Learn/my-demo/MetalCMakeDemo`

---

## 第 1 轮

**用户：**

给我详细讲解这个项目，以及metal的使用，你就当我是metal小白，我想要通过这个项目学习metal相关的知识，讲解越详细越好

**助手：**

当然可以。我先说结论：

**这个项目非常适合拿来学 Metal 入门到进阶。**  
因为它不是那种“只画一个三角形”的极简 Demo，而是一个**完整的 macOS Metal 应用骨架**，把这些东西都串起来了：

- AppKit 窗口
- `CAMetalLayer`
- 渲染管线
- 计算管线
- 深度缓冲
- MSAA
- 纹理与采样器
- Argument Buffer
- Function Constants
- ICB
- Parallel Encoder
- Bloom / Temporal / Particles
- MetalFX 风格上采样
- GPU Capture / Profiling
- fallback 与工程化兼容处理

而且我已经看过你这个项目的源码，也确认它能成功构建。核心代码主要在这几个文件里：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/CMakeLists.txt`
- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/main.mm`
- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/AppDelegate.mm`
- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.h`
- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm`
- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/shaders/triangle.metal`

### 项目本质

它本质上是一个 **macOS 原生窗口程序**，窗口里放了一个 `CAMetalLayer`，然后每一帧让 GPU 做下面这些事：

1. 先画一个 3D 场景（这里是立方体/多个实例）
2. 把结果放到中间纹理里
3. 再用 compute shader 做一些图像处理
   - 边缘检测
   - bloom
   - 粒子叠加
   - 降采样 / 上采样
4. 最后再做一次全屏后处理，把结果输出到屏幕

你可以把它想成一个小型的“渲染引擎教学版”。

### Metal 世界观摘要

- `MTLDevice`：GPU 设备入口
- `CAMetalLayer`：和窗口系统对接的显示层
- `drawable`：当前帧真正显示到屏幕的纹理
- `MTLCommandQueue`：命令队列
- `MTLCommandBuffer`：一帧 GPU 工作说明书
- `Encoder`：往 command buffer 写 render / compute / blit 命令
- `Pipeline State`：GPU 的固定生产线配置
- `Shader`：运行在 GPU 上的小程序
- `MTLBuffer`：一维数据块，放顶点、索引、uniform 等
- `MTLTexture`：图像资源，放颜色、法线、中间结果等
- `Sampler`：决定怎么采样纹理

### 项目结构摘要

- `main.mm`：程序入口
- `AppDelegate.mm`：窗口、MetalView、菜单、HUD、DisplayLink
- `Renderer.mm`：GPU 资源初始化、每帧渲染、后处理
- `triangle.metal`：顶点/片元/计算 shader

### 项目关键学习点摘要

1. 资源与中间纹理如何管理
2. scene pass -> compute pass -> post pass 的链路
3. Function Constants 如何生成 shader 变体
4. Argument Buffer 如何打包资源
5. ICB / Parallel Encoder 的思路
6. Bloom / Temporal / Particles / Upscale 等后处理思路
7. Profiling / GPU Capture / fallback 工程化实践

### 15 个主题摘要

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

### 学习建议摘要

建议先理解：

1. `AppDelegate` 如何驱动每帧渲染
2. `Renderer.initWithLayer:` 如何初始化 Metal
3. `Renderer.render` 如何组织一帧
4. `scene_vertex / scene_fragment / post_fragment` 的基本工作方式
5. 再逐步看 bloom、particles、upscale、ICB、parallel encoding 等高级路径

最后我给出的可选继续方向是：

- 按源码顺序逐行讲解 `Renderer.mm` 的 `initWithLayer:` 和 `render()`
- 专门开一节 Metal 零基础入门课，把 Device / CommandBuffer / Pipeline / Shader / Texture / MSAA / Depth 用图解方式讲清楚

---

## 第 2 轮

**用户：**

按源码顺序，逐行讲解 /Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm 的 initWithLayer: 和 render()
专门开一节“Metal 零基础入门课”，把 Device / CommandBuffer / Pipeline / Shader / Texture / MSAA / Depth 用图解方式讲清楚
都需要

**助手：**

下面给出的是上一次回答的整理版摘要，原回答非常长，这里保留核心结构与重点，便于存档。

# 第一部分：Metal 零基础入门课摘要

## 1. Metal 最核心链路

```text
App/CPU -> MTLDevice -> MTLCommandQueue -> MTLCommandBuffer
          -> Render/Compute Encoder -> Pipeline State -> Shader
          -> Buffer/Texture -> Drawable -> 屏幕
```

## 2. 核心对象解释

- `MTLDevice`：GPU 入口，所有 GPU 资源都从这里创建
- `MTLCommandQueue`：命令投递通道
- `MTLCommandBuffer`：一帧 GPU 工作清单
- `MTLRenderCommandEncoder`：记录 draw 命令
- `MTLComputeCommandEncoder`：记录 compute 命令
- `MTLBlitCommandEncoder`：记录拷贝/搬运命令
- `Shader`：跑在 GPU 上的小程序
- `Pipeline State`：shader + 像素格式 + 深度格式 + 采样数等固定配置
- `MTLBuffer`：线性内存，常放顶点、索引、uniform
- `MTLTexture`：图像资源，常放颜色图、中间结果、深度图
- `CAMetalLayer`：和 macOS 窗口系统对接，提供 drawable
- `Drawable`：当前帧最终显示到屏幕的纹理

## 3. Depth 概念

- 深度缓冲用于决定前后遮挡
- 更近的像素通过深度测试，远的被挡住
- 本项目使用 `Depth32Float` 和 `MTLCompareFunctionLess`

## 4. MSAA 概念

- 锯齿来自像素栅格化时的边缘离散化
- MSAA 在单个像素内做多次采样
- 本项目 scene pass 和 post pass 都采用 4x MSAA
- 渲染到多采样纹理后，再 resolve 到普通纹理

## 5. 一帧流程

```text
nextDrawable
  -> scene pass
  -> compute passes
  -> post pass
  -> presentDrawable
  -> commit
```

---

# 第二部分：`initWithLayer:` 逐段讲解摘要

文件：`/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm`

## 1. 基础初始化

- 保存传入的 `CAMetalLayer`
- 调用 `MTLCreateSystemDefaultDevice()` 获取 GPU 设备
- 若无设备则初始化失败

## 2. 配置 layer

- `layer.device = _device`
- `pixelFormat = BGRA8Unorm`
- 设置 `drawableSize`
- `framebufferOnly = YES`

## 3. 初始化状态缓存与 in-flight semaphore

- 创建 `_inFlightSemaphore`
- 设置默认主题、默认参数、HUD 统计缓存

## 4. 创建 command queue

- `_commandQueue = [_device newCommandQueue]`

## 5. 加载默认 Metal library

- 优先 `newDefaultLibrary`
- 失败时从 `default.metallib` 显式加载

## 6. 获取 shader 函数

- `scene_vertex`
- `scene_fragment_icb`
- `post_vertex`
- `post_fragment`
- `edge_detect_kernel`
- `bright_extract_kernel`
- `blur_kernel`
- `particle_overlay_kernel`
- `downsample_half_kernel`
- `upscale_linear_kernel`

## 7. 用 Function Constants 生成 4 个 `scene_fragment` 变体

- base
- PBR
- shadow
- argument-buffer

## 8. 创建 render pipeline state

- 普通 scene pipeline
- ICB pipeline
- PBR pipeline
- Shadow pipeline
- Argument Buffer pipeline
- Post pipeline

## 9. 创建 compute pipeline state

- edge
- bright extract
- blur
- particle
- downsample
- upscale

## 10. 创建 argument buffer 相关资源

- `newArgumentEncoderWithBufferIndex:2`
- 创建 `_materialArgumentBuffer`

## 11. 创建 depth state 与 sampler

- `depthCompareFunction = Less`
- `depthWriteEnabled = YES`
- 普通线性 sampler
- `maxAnisotropy = 8` 的各向异性 sampler

## 12. 可选特性初始化

- `newSharedEvent`
- `supportsRaytracing`
- 创建 `MTLIndirectCommandBuffer`

## 13. 准备立方体 mesh

- 24 个顶点，36 个索引
- 使用 staging buffer -> private buffer 上传静态几何
- `_instanceBuffer` 用于 3 个对象的实例数据

## 14. 预录制 ICB 命令

- 在 ICB 中预录 3 条 `drawIndexedPrimitives`
- 每条命令 `baseInstance = commandIndex`
- 对应 3 个实例对象

## 15. 创建 3 份 uniform buffer

- 对应 `kMaxFramesInFlight = 3`

## 16. 创建程序生成纹理

- `createAlbedoTexture`
- `createNormalTexture`
- 生成 mipmaps

## 17. 用 argument encoder 把纹理写入 argument buffer

- albedo -> slot 0
- normal -> slot 1

## 18. 初始化完成

- `_historyValid = NO`
- 初始化 `_metricsLock`

---

# 第三部分：`render()` 逐段讲解摘要

文件：`/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm`

## 1. 帧开始

- 建立 autoreleasepool
- 记录 CPU 帧开始时间
- `dispatch_semaphore_wait` 控制最多 3 帧在飞

## 2. 可选 GPU Capture

- 如果用户请求抓帧，则启动 `.gputrace`

## 3. 错误示例：强制资源抖动

- 主题 1 且错误示例打开时，故意将 `_sceneResolveTexture = nil`

## 4. 获取 drawable

- `id<CAMetalDrawable> drawable = [_metalLayer nextDrawable]`

## 5. 确保 render targets

- `ensureRenderTargetsForDrawable:drawable`
- 确保 scene/depth/post 等中间纹理存在且尺寸匹配

## 6. 创建 command buffer 与完成回调

- 每帧新建一个 command buffer
- 完成回调中：
  - 停止 GPU Capture
  - 计算 GPU 帧时
  - 更新 HUD 统计
  - `signal` semaphore

## 7. 选择当前 uniform buffer

- `uniformIndex = _frameIndex % kMaxFramesInFlight`

## 8. 根据当前主题选择路径和参数

- `useICB`
- `useParallel`
- `useDeferredLike`
- `usePBR`
- `useBloom`
- `useParticles`
- `useAnisoSampler`
- `useUpscale`
- `useProfiling`
- `useSyncScheduling`

并根据主题设置：

- `timeScale`
- `edgeStrength`
- `sceneMix`
- `exposureBias`
- `bloomStrength`
- `particleStrength`
- `temporalBlend`
- `sceneClear`

## 9. 错误示例模式

- 某些主题会故意增大 bloom、temporal、edge 或 compute 压力

## 10. 结合 HUD 用户调节倍率

- `_userTimeScaleGain`
- `_userEdgeGain`
- `_userExposureGain`

## 11. 更新 HUD 路径摘要

- Scene Path
- Post Path
- Upscale Path
- Fallback Summary

## 12. 写 uniform 数据

- 计算 `projection`
- 计算 `view`
- 计算 `model`
- 计算 `MVP`
- 写入 `Uniforms`

## 13. 写 instance 数据

- 更新 3 个实例的变换矩阵和 tint

## 14. Scene Pass

### 普通路径

- 创建 `scenePass`
- 颜色写入 `_sceneMSAATexture`
- resolve 到 `_sceneResolveTexture`
- 深度写入 `_sceneDepthTexture`
- 绑定 pipeline / depth / buffer / texture / sampler
- 发起 `drawIndexedPrimitives`

### ICB 路径

- 绑定外部继承资源
- `executeCommandsInBuffer:_indirectCommandBuffer`

### Parallel 路径

- `MTLParallelRenderCommandEncoder`
- 拆成两个子 encoder 并行编码

## 15. Compute Passes

### Edge

- `_sceneResolveTexture -> _edgeTexture`

### Deferred-like

- 主题 6 单独先跑一次 edge compute

### Bloom

- bright extract（半分辨率）
- blur horizontal
- blur vertical
- 错误示例下再多 blur 一轮

### Particles

- 写入 `_particleTexture`

### Upscale

- 先 downsample 到 `_halfResTexture`
- 若可用则走 `MTLFXSpatialScaler`
- 否则走 `upscale_linear_kernel`
- 结果输出到 `_upscaledTexture`

## 16. Post Pass

- 输入：scene / edge / bloom / particle / history
- 输出：`_postMSAATexture`
- resolve 到 `drawable.texture`
- 画全屏三角形：
  - `drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3`

## 17. History 拷贝

- 当 temporal 或 upscale 需要历史帧时：
- 将 `sceneForPost` 拷贝到 `_historyTexture`

## 18. 同步/调试标签

- 可选 signal shared event
- profiling 模式下 push/pop debug group

## 19. 更新统计并提交

- 记录 CPU 帧时、显存估算
- `presentDrawable:drawable`
- `commit`

---

## 第 3 轮

**用户：**

 [postEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; 为啥绘制只用了vertexCount:3，
另外，在项目根目录新建一个md文件夹， 把当前对话及之前的对话保存成md文件存到md文件夹

**助手：**

### 关于 `vertexCount:3`，原因是：这里画的是“全屏三角形”，不是普通模型

这句代码：

```objc
[postEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
```

表示：

- primitive type 是 `Triangle`
- 从 `vertexStart = 0` 开始
- 一共取 `3` 个顶点
- 所以最终只画 **1 个三角形**

你可能会本能地想：

> “全屏后处理不是应该画一个矩形吗？为什么只画一个三角形？”

这是因为这里用的是 **Full-Screen Triangle（全屏三角形）** 技巧。

---

### 1. 对应的顶点不是从 vertex buffer 里来的，而是 shader 里直接生成的

在 shader 文件 `/Users/mtl/Learn/my-demo/MetalCMakeDemo/shaders/triangle.metal` 里，`post_vertex` 是这样写的：

```metal
vertex PostVertexOut post_vertex(uint vertexID [[vertex_id]])
{
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0)
    };

    float2 pos = positions[vertexID];
    PostVertexOut out;
    out.position = float4(pos, 0.0, 1.0);
    out.uv = pos * 0.5 + 0.5;
    return out;
}
```

这里 `vertex_id` 会依次取：

- 0
- 1
- 2

所以刚好对应 3 个顶点。

---

### 2. 这 3 个点组成了一个“覆盖整个屏幕的大三角形”

3 个点分别是：

- `(-1, -1)`：左下
- `(3, -1)`：右侧外面很远
- `(-1, 3)`：上方外面很远

在裁剪空间里，这个三角形虽然有两个顶点跑到了屏幕外面，但它会覆盖整个屏幕区域。

你可以粗略理解成：

```text
裁剪空间大致范围：x,y 都在 [-1, 1]

这个三角形顶点：
A = (-1, -1)
B = ( 3, -1)
C = (-1,  3)

它虽然很“大”，但中间那块刚好把整个屏幕盖住了。
```

---

### 3. 为什么不用“两个三角形拼一个矩形”？

当然也能这么画：

- 4 个顶点
- 2 个三角形
- 拼成一个 full-screen quad

但全屏三角形通常更好，原因有几个：

#### 原因 A：更简单
只要 3 个顶点，不用顶点 buffer，不用 index buffer。

#### 原因 B：避免对角线接缝问题
如果你用两个三角形拼矩形，中间会有一条对角线。虽然多数时候看不出来，但在某些后处理里会出现：

- 插值差异
- 导数不连续
- 边界接缝

全屏三角形没有这条内部拼接边。

#### 原因 C：是现代图形 API 中非常常见的做法
很多后处理 pass 都这么干：

- tone mapping
- bloom composite
- FXAA/TAA
- SSAO composite
- copy pass
- debug view

---

### 4. 为什么这里不需要设置 vertex buffer？

因为 `post_vertex` 完全依赖 `vertex_id` 自己生成顶点位置：

- 不读 `[[buffer(0)]]`
- 不需要 mesh 数据
- 不需要 CPU 上传顶点数组

所以 CPU 侧只需要一句：

```objc
[postEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
```

就够了。

---

### 5. 这句代码在 post pass 中的真实含义

它的意思不是：

> “画一个普通三角形模型。”

而是：

> “启动一次覆盖全屏的后处理，把 scene / edge / bloom / particles / history 这些纹理全部采样一遍，并输出到当前 render target。”

也就是说，**真正重要的不是几何形状本身，而是 fragment shader 会对屏幕上的每个像素执行一次后处理逻辑。**

---

### 6. 你可以这样记

#### 普通 3D 模型绘制
- 需要 vertex buffer
- 需要 index buffer
- `vertexCount`/`indexCount` 对应模型几何

#### 全屏后处理绘制
- 常用 full-screen triangle
- 不需要真实模型
- `vertexCount:3` 只是在触发一次全屏 rasterization

---

### 7. 一句话总结

`vertexCount:3` 不是因为这个 post pass 只处理“三个点”，而是因为它采用了 **全屏三角形** 技巧：

- vertex shader 用 `vertex_id` 生成 3 个裁剪空间顶点
- 这 3 个顶点组成一个覆盖整个屏幕的大三角形
- fragment shader 因此会对整个屏幕每个像素执行后处理

---

### 8. 额外补一句：如果你愿意继续学，这里是一个非常好的切入点

你下一步非常适合继续问我：

- “post_vertex 里那 3 个坐标为什么刚好能覆盖全屏？”
- “clip space / NDC / viewport 到底是什么关系？”
- “为什么 `uv = pos * 0.5 + 0.5` 这么写？”

这三个问题一旦搞懂，你对后处理 pass 的理解会直接上一个台阶。

另外，我已经按你的要求在项目根目录创建了 `md` 文件夹，并把当前和之前的对话整理保存到这个文件里：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/md/2026-04-21_metal_learning_dialogue.md`


---

## 第 4 轮

**用户：**

为什么 (-1,-1) / (3,-1) / (-1,3) 恰好能覆盖全屏
uv = pos * 0.5 + 0.5 为什么这么写
clip space / NDC / viewport 三者关系
讲解 ，并且同步更新md文档

**助手：**

下面把这 3 个问题连起来讲，因为它们其实是同一条链：

- 顶点坐标先在 **clip space** 里定义
- 做透视除法后得到 **NDC**
- NDC 再通过 viewport 映射到屏幕像素
- 同时把 `[-1,1]` 范围映射到 `[0,1]`，就得到常用的纹理 `uv`

### 一、为什么 `(-1,-1) / (3,-1) / (-1,3)` 能覆盖全屏

后处理 pass 里常用的是 **full-screen triangle**，即“全屏三角形”。

这 3 个点在裁剪空间里是：

- A = `(-1, -1)`
- B = `( 3, -1)`
- C = `(-1,  3)`

标准屏幕区域对应的 NDC 正方形范围是：

- x ∈ `[-1, 1]`
- y ∈ `[-1, 1]`

也就是说，屏幕就是这个方框：

```text
(-1, 1)           (1, 1)
   +---------------+
   |               |
   |    屏幕区域    |
   |               |
   +---------------+
(-1,-1)           (1,-1)
```

而全屏三角形是：

```text
C(-1,3)
   *
   |\
   | \
   |  \
   |   \
   |    \
   |     \
   *------* B(3,-1)
A(-1,-1)
```

这个三角形非常大，它不只覆盖屏幕，还故意伸到屏幕右边和上边外面。

为什么这样就能盖满屏幕？

因为屏幕左下角、右下角、左上角都在这个三角形内部或边界上，而三角形的斜边正好从左上外侧跨到右下外侧，所以整个 `[-1,1] x [-1,1]` 的方框都落在三角形覆盖范围内。

你也可以把它理解成：

- 传统 full-screen quad：用 2 个三角形拼一个矩形
- full-screen triangle：直接用 1 个足够大的三角形把这个矩形整个罩住

### 二、为什么不用 `(-1,-1) / (1,-1) / (-1,1)`

因为那只会覆盖屏幕左下角的一半。

全屏三角形的关键不是“顶点在屏幕四角”，而是“这个三角形的面积必须覆盖整个屏幕矩形”。

所以才把另外两个点推到屏幕外：

- 一个推到右边外面：`(3,-1)`
- 一个推到上边外面：`(-1,3)`

这样 rasterization 时，整个屏幕都会被这个三角形扫到。

### 三、为什么 `uv = pos * 0.5 + 0.5`

先看 `pos` 的范围。

在 `post_vertex` 里，`pos` 是裁剪空间 / NDC 风格的二维坐标，中心思想是：

- 左边是 `x = -1`
- 右边是 `x = 1`
- 下边是 `y = -1`
- 上边是 `y = 1`

而纹理坐标 `uv` 一般想要的是：

- 左边是 `u = 0`
- 右边是 `u = 1`
- 下边是 `v = 0`
- 上边是 `v = 1`

这本质上就是把区间：

- `[-1, 1]`

线性映射到：

- `[0, 1]`

最标准的线性变换就是：

```text
uv = pos * 0.5 + 0.5
```

因为：

- 当 `pos = -1` 时：`uv = -1 * 0.5 + 0.5 = 0`
- 当 `pos = 0` 时：`uv = 0 * 0.5 + 0.5 = 0.5`
- 当 `pos = 1` 时：`uv = 1 * 0.5 + 0.5 = 1`

所以这是一个非常经典的坐标归一化公式。

### 四、为什么顶点里会出现 `3`，算出来的 uv 不会超过 1 吗？

会，确实会超过。

例如：

- `pos.x = 3`
- 则 `uv.x = 3 * 0.5 + 0.5 = 2.0`

这不是 bug。

因为 rasterization 真正关心的是**屏幕内的片元**。虽然三角形顶点在屏幕外，但屏幕内部实际生成的 fragment，其插值后的 `uv` 会恰好覆盖所需范围。

换句话说：

- 顶点可以在屏幕外
- 最终只会对屏幕内那块区域做插值和着色
- 屏幕内那部分插值结果正好对应你想要的 `uv`

这正是 full-screen triangle 技巧成立的原因之一。

### 五、clip space / NDC / viewport 到底是什么关系

这是图形学坐标系统最重要的一条链。

#### 1. Clip Space（裁剪空间）

顶点着色器最终输出的是：

```metal
float4 position [[position]];
```

这个 `position` 首先处在 **clip space** 概念里。

它是齐次坐标，通常写成：

```text
(x, y, z, w)
```

在你的 post pass 里：

```metal
out.position = float4(pos, 0.0, 1.0);
```

所以这里：

- `x = pos.x`
- `y = pos.y`
- `z = 0`
- `w = 1`

因为 `w = 1`，所以这时候 clip space 和后面的 NDC 会非常直观。

#### 2. NDC（Normalized Device Coordinates，标准化设备坐标）

GPU 会对 clip space 做一步叫 **透视除法** 的操作：

```text
ndc = (x/w, y/w, z/w)
```

如果 `w = 1`，那就是：

```text
ndc = (x, y, z)
```

NDC 的典型范围是：

- x ∈ `[-1, 1]`
- y ∈ `[-1, 1]`
- z 在 API 约定范围内

在 2D 后处理里，你主要关心的是 x 和 y。

#### 3. Viewport（视口变换）

NDC 还不是屏幕像素坐标。  
接下来 GPU 会把 NDC 映射到屏幕上的实际像素矩形，这一步就是 **viewport transform**。

例如一个 800x600 的窗口，大致可以理解成：

- `x = -1` -> 屏幕最左边
- `x = 1` -> 屏幕最右边
- `y = -1` -> 屏幕最下边
- `y = 1` -> 屏幕最上边

于是 NDC 的正方形就被拉伸/映射成真正的屏幕矩形。

### 六、把三者串成一张图

```text
Vertex Shader 输出
clip space: (x, y, z, w)
        |
        | 透视除法 (x/w, y/w, z/w)
        v
NDC: [-1,1] 范围
        |
        | viewport transform
        v
屏幕像素坐标
```

而 `uv = pos * 0.5 + 0.5` 则是另一条平行的小映射：

```text
NDC/屏幕风格坐标: [-1,1]
        |
        | 线性映射 *0.5 + 0.5
        v
纹理坐标 UV: [0,1]
```

### 七、为什么这三件事放在一起就容易懂了

因为它们本质上都在回答“同一个点在不同坐标系里怎么表示”：

1. `(-1,-1)/(3,-1)/(-1,3)` 是为了在 **clip/NDC 空间** 构造一个足够大的三角形
2. `uv = pos * 0.5 + 0.5` 是为了把 **NDC 风格坐标** 映射成 **纹理坐标**
3. clip space -> NDC -> viewport，是为了说明这个三角形最终怎么变成屏幕上的像素覆盖

### 八、你可以这样记忆

#### 对 3D 模型
- 顶点来自 vertex buffer
- 顶点经过 MVP 变换
- 输出到 clip space
- 经过 NDC 和 viewport，最后落到屏幕上

#### 对全屏后处理
- 顶点常常直接在 shader 里生成
- 直接构造一个覆盖全屏的大三角形
- fragment shader 对屏幕每个像素执行采样与合成

### 九、最简总结

#### 为什么那 3 个点能覆盖全屏？
因为它们构成了一个故意超出屏幕边界的大三角形，而屏幕对应的 `[-1,1] x [-1,1]` 区域完整落在这个三角形内部。

#### 为什么 `uv = pos * 0.5 + 0.5`？
因为它是在把 `[-1,1]` 线性映射到 `[0,1]`，从而把屏幕/裁剪空间风格坐标转成纹理采样坐标。

#### clip space / NDC / viewport 关系？
- vertex shader 输出 clip space
- GPU 做透视除法得到 NDC
- GPU 再把 NDC 映射到 viewport，也就是真正的屏幕像素区域


---

## 第 5 轮

**用户：**

为什么 full-screen triangle 不会在屏幕边缘出错插值
post pass 里的 uv 插值过程到底是怎么发生的
另外 出现的是一个立方体，为啥最后绘制只画了三角形 ，需要同步md文档

**助手：**

### 一、为什么 full-screen triangle 不会在屏幕边缘出错插值

核心原因有 3 个：

1. GPU 会先对超出视口的三角形做裁剪（clip），只保留屏幕内真正可见的部分。
2. rasterizer 只会为屏幕内被覆盖到的 fragment 生成插值结果。
3. 这个 post pass 只用 **一个** 大三角形，没有“两三角形拼矩形”的中间对角线，所以反而更不容易出现接缝问题。

也就是说，虽然顶点 `(-1,-1) / (3,-1) / (-1,3)` 有两个点在屏幕外，但 GPU 不会傻乎乎地把屏幕外那部分也拿来显示；它会把三角形裁剪到视口，然后只对屏幕内那块区域做 rasterization 和插值。

### 二、为什么不会“边缘 UV 错”

因为 `uv` 是跟着顶点一起输出的 varying，GPU 会在 rasterization 阶段对它做插值。

在这个 post pass 中，vertex shader 输出：

- A = `(-1,-1)` -> `uv=(0,0)`
- B = `( 3,-1)` -> `uv=(2,0)`
- C = `(-1, 3)` -> `uv=(0,2)`

虽然 B/C 的 UV 超过了 1，但这没关系，因为真正屏幕内的点，其插值后 UV 会落在你需要的范围。

例如：

- 屏幕右下角 `(1,-1)` 位于边 AB 上，刚好会插值到 `uv=(1,0)`
- 屏幕左上角 `(-1,1)` 位于边 AC 上，刚好会插值到 `uv=(0,1)`
- 屏幕右上角 `(1,1)` 位于边 BC 上，刚好会插值到 `uv=(1,1)`

所以**屏幕四个角对应的 UV 恰好是标准纹理四角**，整个屏幕内部也就自然得到正确的 `[0,1]` 采样范围。

### 三、post pass 里的 UV 插值过程是怎么发生的

#### 1. Vertex shader 先为每个顶点输出一个 UV

`post_vertex` 中：

```metal
out.position = float4(pos, 0.0, 1.0);
out.uv = pos * 0.5 + 0.5;
```

所以每个顶点除了位置，还带着自己的 UV。

#### 2. Rasterizer 生成 fragment

当三角形覆盖到屏幕之后，GPU 会对屏幕中的每个像素中心判断：

- 这个像素是否落在三角形内部？
- 如果在，就生成一个 fragment

#### 3. GPU 用重心坐标做插值

对于三角形内部任意一个 fragment，GPU 会算出它相对于 3 个顶点的权重：

- `α`
- `β`
- `γ`

满足：

```text
α + β + γ = 1
```

然后用这 3 个权重去插值顶点属性。

如果是 `uv`，可以写成：

```text
uv = α * uv0 + β * uv1 + γ * uv2
```

这就是“varying 插值”。

#### 4. 这里是 perspective-correct interpolation，但因为 w=1，结果等同线性插值

正常图形管线默认会做**透视正确插值**。  
但在这个 post pass 里：

```metal
out.position = float4(pos, 0.0, 1.0);
```

所有顶点的 `w` 都是 1，所以透视修正不会改变结果。于是你可以把这里的 UV 插值近似理解成：

> 在屏幕空间上做平滑的线性插值。

所以 full-screen triangle 的 post pass UV 是非常稳定、非常干净的。

### 四、为什么 full-screen triangle 比 full-screen quad 更不容易出问题

如果你用两个三角形拼一个矩形：

- 左上半个三角形插值一次
- 右下半个三角形再插值一次

它们虽然理论上能拼成同一个矩形，但中间那条对角线会带来潜在问题：

- 导数不连续
- 插值边界不完全一致
- 某些后处理在对角线附近会出现轻微接缝

而 full-screen triangle：

- 整个屏幕只属于 **一个** 三角形
- 所有 fragment 都来自同一套顶点与同一套插值规则
- 没有内部拼接边

所以它通常更稳定。

### 五、既然画面里是一个立方体，为啥最后只画了一个三角形？

这个问题特别关键。答案是：

> **因为“立方体”是在 scene pass 里画出来的，而“最后那个三角形”是 post pass 的全屏合成三角形。**

也就是说，这一帧其实不是只有一次绘制，而是至少两次主要绘制：

#### 第 1 次：Scene Pass

这里真正画立方体：

```objc
[sceneEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                          indexCount:_indexCount
                           indexType:MTLIndexTypeUInt16
                         indexBuffer:_indexBuffer
                   indexBufferOffset:0];
```

这一步：

- 读取 `_vertexBuffer`
- 读取 `_indexBuffer`
- 做顶点变换、光照、纹理采样
- 把“立方体图像”写进 `_sceneMSAATexture`
- resolve 到 `_sceneResolveTexture`

#### 第 2 次：Post Pass

这里并不再画立方体模型，而是画一个 full-screen triangle：

```objc
[postEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
```

这一步做的是：

- 对屏幕每个像素执行 `post_fragment`
- 采样之前 scene pass 得到的 `_sceneResolveTexture`
- 再叠加 edge / bloom / particles / history
- 最终输出到 `drawable.texture`

所以你屏幕上看到“立方体”，不是因为 post pass 又画了一次立方体，
而是因为 post pass 采样了**已经包含立方体图像的 sceneTexture**。

### 六、你可以把它理解成“先拍照，再滤镜”

这是个非常好懂的类比：

#### Scene Pass
像是先把 3D 立方体“拍成一张照片” -> 存到 `_sceneResolveTexture`

#### Post Pass
像是把这张照片拿来做滤镜处理：

- 边缘增强
- bloom
- 粒子叠加
- temporal 混合

最后显示到屏幕上。

所以最后那个三角形，本质上只是“滤镜处理载体”，不是最终画面内容本身。

### 七、最简总结

#### 为什么 full-screen triangle 不会在边缘出错？
因为 GPU 会先裁剪，再只对屏幕内 fragment 做插值；而且整个屏幕只属于一个三角形，没有拼接缝。

#### UV 插值怎么发生？
vertex shader 给 3 个顶点各自输出 UV，rasterizer 对三角形内部每个 fragment 用重心坐标做插值；本例中因为 `w=1`，可以近似理解为屏幕空间线性插值。

#### 为什么看到的是立方体，但最后 draw 只画三角形？
因为立方体是在 **scene pass** 里画的；最后那个三角形只是 **post pass** 的全屏合成几何体，用来把 scene 结果采样并显示到屏幕。

