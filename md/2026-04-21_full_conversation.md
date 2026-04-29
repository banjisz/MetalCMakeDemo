# MetalCMakeDemo 完整对话记录

- 日期：2026-04-21
- 项目目录：`/Users/mtl/Learn/my-demo/MetalCMakeDemo`
- 说明：本文件保存本线程截至当前轮次的**完整用户/助手对话**（不含工具调用与隐藏系统消息）。

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

# 一、先用一句人话解释：这个项目到底在干嘛？

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

# 二、先建立 Metal 世界观

你说你是 Metal 小白，那我先不急着讲代码，先把 Metal 最核心的几个对象讲明白。

## 1. `MTLDevice` 是什么？

它代表“这台机器上的 GPU 设备”。

```objc
_device = MTLCreateSystemDefaultDevice();
```

你可以理解成：

- CPU 世界里，程序跑在 CPU 上
- GPU 世界里，所有绘制/计算都要通过 `MTLDevice` 创建资源和管线

几乎所有 Metal 对象都得从它这里造出来：

- `MTLCommandQueue`
- `MTLBuffer`
- `MTLTexture`
- `MTLRenderPipelineState`
- `MTLComputePipelineState`

## 2. `CAMetalLayer` 是什么？

这是“屏幕显示层”。

这个项目里，`MetalView` 的 backing layer 就是 `CAMetalLayer`：

```objc
- (CALayer *)makeBackingLayer
{
    return [CAMetalLayer layer];
}
```

它的作用是：

- 提供一个可显示到屏幕的 drawable
- 每帧你从它那里拿一个 `nextDrawable`
- 你把结果渲染到这个 drawable 的 texture 上
- 最后 present，它就显示出来了

你可以把它理解成“屏幕交换链的入口”。

## 3. `drawable` 是什么？

`drawable` 就是“当前这一帧可显示的目标”。

```objc
id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
```

它内部最重要的就是：

```objc
drawable.texture
```

这个 texture 最终会被显示到屏幕上。

## 4. `MTLCommandQueue` 是什么？

它是“命令队列”。

```objc
_commandQueue = [_device newCommandQueue];
```

你每一帧都要从它创建一个 `MTLCommandBuffer`。

## 5. `MTLCommandBuffer` 是什么？

它是“一帧 GPU 工作说明书”。

你可以把它理解成：

> CPU 不直接让 GPU 干活，而是先把“这帧要做什么”写进 command buffer，最后提交给 GPU。

这个项目每帧都这么做：

```objc
id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
```

然后往里面塞：

- render pass
- compute pass
- blit pass
- present drawable

最后：

```objc
[commandBuffer commit];
```

## 6. Encoder 是什么？

`CommandBuffer` 像一个大箱子，里面能装不同类型的命令。  
而 Encoder 就是“往箱子里写某类命令的工具”。

主要有三类：

### render encoder
画三角形、画模型、执行 rasterization

### compute encoder
跑 compute shader，做通用并行计算

### blit encoder
做拷贝、生成 mipmap、纹理/缓冲搬运

这个项目三种都用了。

## 7. Pipeline State 是什么？

这是很多初学者最容易迷糊的点。

你可以把 pipeline state 理解成：

> GPU 的“工作配方”或“固定配置好的生产线”

比如 render pipeline state 决定：

- 用哪个 vertex shader
- 用哪个 fragment shader
- 颜色格式是什么
- 深度格式是什么
- MSAA 采样数是多少

这个项目里创建了很多条 pipeline：

- 普通 scene pipeline
- ICB pipeline
- PBR pipeline
- shadow pipeline
- argument-buffer pipeline
- post pipeline

## 8. Shader 是什么？

Shader 是跑在 GPU 上的小程序。

这个项目都在：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/shaders/triangle.metal`

里面分几种：

### vertex shader
处理顶点

### fragment shader
处理像素/片元

### compute kernel
做通用计算

## 9. Buffer 和 Texture 的区别

### `MTLBuffer`
一维线性内存，常放：

- 顶点数据
- 索引数据
- uniform 数据
- instance 数据

### `MTLTexture`
二维/三维图像数据，常放：

- 颜色纹理
- 深度纹理
- 中间渲染结果
- bloom 纹理
- 粒子 overlay
- history

## 10. Sampler 是什么？

采样器决定“怎么读纹理”。

比如：

- nearest / linear
- repeat / clamp
- anisotropic filtering

这个项目有两个 sampler：

- 普通 sampler
- 各向异性 sampler（主题 11）

# 三、这个项目的整体结构

## 1. 入口：`main.mm`

文件：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/main.mm`

非常简单：

```objc
NSApplication *app = [NSApplication sharedApplication];
AppDelegate *delegate = [[AppDelegate alloc] init];
[app setDelegate:delegate];
[app run];
```

意思就是：

- 启动 macOS App
- 把控制权交给 `AppDelegate`

## 2. App 层：`AppDelegate.mm`

文件：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/AppDelegate.mm`

这个文件做的事主要是：

- 创建窗口
- 创建 `MetalView`
- 确保 backing layer 是 `CAMetalLayer`
- 创建 `Renderer`
- 安装菜单
- 安装 HUD 面板
- 安装说明页
- 启动 `CADisplayLink`
- 每帧调用 `[_renderer render]`

### 这是 App 层，不是渲染核心层

初学者很容易分不清：

- `AppDelegate`：负责窗口/UI/交互/菜单/显示循环
- `Renderer`：负责 Metal 资源初始化和每帧渲染

这个项目分层其实做得挺清楚。

## 3. 真正的渲染核心：`Renderer.mm`

文件：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm`

这个文件是项目的心脏。

里面主要干三件大事：

### A. 初始化 GPU 资源
在 `initWithLayer:` 里完成

### B. 根据 drawable 大小创建/重建中间纹理
在 `ensureRenderTargetsForDrawable:` 里完成

### C. 每帧编码并提交 GPU 命令
在 `render` 里完成

## 4. Shader 文件：`triangle.metal`

别被名字骗了。

虽然叫 `triangle.metal`，但这里面其实包含：

- scene vertex shader
- scene fragment shader
- ICB fragment shader
- post vertex shader
- post fragment shader
- edge detect compute
- bright extract compute
- blur compute
- particle compute
- downsample compute
- upscale compute

这已经不是“triangle”了，而是“一个小型 shader 集合”。

# 四、CMake 是怎么把这个项目组织起来的？

文件：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/CMakeLists.txt`

核心点：

```cmake
project(MetalCMakeDemo LANGUAGES C CXX OBJC OBJCXX)
```

这里非常关键。因为项目用了：

- C / C++
- Objective-C
- Objective-C++

`.mm` 文件是 Objective-C++，因为它同时混用了：

- Cocoa/AppKit 的 Objective-C 对象
- `simd` / C++ 风格类型

## 链接的框架

```cmake
find_library(COCOA_FRAMEWORK Cocoa REQUIRED)
find_library(METAL_FRAMEWORK Metal REQUIRED)
find_library(METALFX_FRAMEWORK MetalFX REQUIRED)
find_library(QUARTZCORE_FRAMEWORK QuartzCore REQUIRED)
find_library(FOUNDATION_FRAMEWORK Foundation REQUIRED)
```

分别用于：

- Cocoa：窗口与 UI
- Metal：GPU API
- MetalFX：上采样器
- QuartzCore：`CAMetalLayer`
- Foundation：基础框架

## `.metal` 文件怎么处理的？

```cmake
set(METAL_SHADER
    shaders/triangle.metal
)
...
add_executable(${APP_NAME} MACOSX_BUNDLE
    ...
    ${METAL_SHADER}
)
```

然后构建时，Xcode 会帮你：

- 编译 `.metal` -> `.air`
- 再 link 成 `default.metallib`

所以运行时这段代码才能工作：

```objc
id<MTLLibrary> library = [_device newDefaultLibrary];
```

意思是：从 app bundle 里加载默认 shader 库。

# 五、程序启动后发生了什么？

## 第一步：创建窗口和 `CAMetalLayer`

在 `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/AppDelegate.mm` 里：

```objc
_window = [[NSWindow alloc] initWithContentRect:frame ...];
_metalView = [[MetalView alloc] initWithFrame:frame];
[_metalView setWantsLayer:YES];
[_window setContentView:_metalView];
```

然后取 layer：

```objc
CAMetalLayer *metalLayer = (CAMetalLayer *)_metalView.layer;
```

设置：

```objc
metalLayer.contentsScale = [_window backingScaleFactor];
metalLayer.drawableSize = CGSizeMake(...);
```

### 为什么要 `contentsScale` 和 `drawableSize`？

因为 macOS 可能是 Retina 屏。

比如窗口逻辑大小是 800x600，但实际像素可能是 1600x1200。  
Metal 画的是**像素级别**，所以要设置正确的 drawable 尺寸。

## 第二步：创建 `Renderer`

```objc
_renderer = [[Renderer alloc] initWithLayer:metalLayer];
```

从这里开始，Metal 的设备、命令队列、shader、pipeline、buffer、texture 都在 `Renderer` 里初始化。

## 第三步：启动 `CADisplayLink`

```objc
_displayLink = [screen displayLinkWithTarget:self
                                    selector:@selector(handleDisplayLink:)];
```

每次屏幕刷新时，就会调用：

```objc
[self drawFrame];
```

然后：

```objc
[_renderer render];
```

这就进入每帧渲染循环了。

# 六、`Renderer` 初始化过程，详细拆开讲

下面这部分是学习 Metal 最重要的一部分。

## 1. 创建设备和命令队列

```objc
_device = MTLCreateSystemDefaultDevice();
_commandQueue = [_device newCommandQueue];
```

这是标准开局。

## 2. 配置 `CAMetalLayer`

```objc
_metalLayer.device = _device;
_metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
_metalLayer.framebufferOnly = YES;
```

### 这里有个很重要的初学者知识点：

`framebufferOnly = YES` 表示 drawable texture 主要用作 framebuffer，不能随便拿来 shader read/write。

这会提升性能，但也意味着：

> 你不能直接把 drawable 当成一个又画又采样的万能纹理。

所以这个项目采用了非常典型、也非常正确的做法：

- 先渲染到中间纹理 `_sceneResolveTexture`
- 后续 compute / post 都采样这个中间纹理
- 最后 post pass 输出到 `drawable.texture`

这是很标准的工程写法。

## 3. 创建 in-flight semaphore

```objc
_inFlightSemaphore = dispatch_semaphore_create(kMaxFramesInFlight);
```

这里：

```objc
static const NSUInteger kMaxFramesInFlight = 3;
```

意思是最多允许 3 帧在飞。

### 这是干嘛的？

防止 CPU 录命令太快，把 GPU 压爆。

典型问题是：

- CPU 第 1、2、3、4、5 帧疯狂提交
- GPU 还没做完前几帧
- 你却又开始重用同一块 uniform buffer
- 结果数据被覆盖，画面错乱

所以它这里用 3 份 uniform buffer：

```objc
id<MTLBuffer> _uniformBuffers[kMaxFramesInFlight];
```

每帧轮着用。

这就是经典的 **ring buffer / triple buffering** 思路。

## 4. 加载 shader library

```objc
id<MTLLibrary> library = [_device newDefaultLibrary];
```

如果拿不到，就尝试从 bundle 里的 `default.metallib` 加载。

这非常实用，也体现了项目的工程兼容性。

## 5. 从 library 里取函数

```objc
id<MTLFunction> sceneVertex = [library newFunctionWithName:@"scene_vertex"];
id<MTLFunction> sceneFragmentICB = [library newFunctionWithName:@"scene_fragment_icb"];
id<MTLFunction> postVertex = [library newFunctionWithName:@"post_vertex"];
id<MTLFunction> postFragment = [library newFunctionWithName:@"post_fragment"];
...
```

这就把 `.metal` 文件里的函数取出来了。

## 6. Function Constants：生成多个 shader 变体

这个项目非常适合学 **Function Constants**。

shader 中定义了：

```metal
constant bool kUsePBR [[function_constant(0)]];
constant bool kUseShadow [[function_constant(1)]];
constant bool kUseArgumentBuffer [[function_constant(2)]];
```

CPU 侧通过：

```objc
MTLFunctionConstantValues *constants = [[MTLFunctionConstantValues alloc] init];
[constants setConstantValue:&usePBR type:MTLDataTypeBool atIndex:0];
...
id<MTLFunction> fragment = [library newFunctionWithName:@"scene_fragment"
                                         constantValues:constants
                                                  error:&localError];
```

生成不同版本的 fragment shader：

- base
- PBR
- shadow
- argument-buffer

### 这是什么思路？

不是在 shader 里写一堆 `if` 运行时判断，  
而是**在编译期就裁掉不需要的逻辑**。

优点：

- 更快
- 更干净
- 更接近真实项目里 shader variant 管理

## 7. 创建 render pipeline states

### Scene pipeline

```objc
scenePipelineDescriptor.vertexFunction = sceneVertex;
scenePipelineDescriptor.fragmentFunction = sceneFragmentBase;
scenePipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
scenePipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
scenePipelineDescriptor.rasterSampleCount = kSampleCount;
```

这里：

```objc
static const NSUInteger kSampleCount = 4;
```

说明 scene pass 开了 **4x MSAA**。

然后又创建：

- `_scenePipelineState`
- `_sceneICBPipelineState`
- `_scenePBRPipelineState`
- `_sceneShadowPipelineState`
- `_sceneArgumentBufferPipelineState`

### Post pipeline

post pass 也有自己的 pipeline：

```objc
_postPipelineState
```

它负责把 scene + edge + bloom + particles + history 混合后输出到屏幕。

## 8. 创建 compute pipeline states

```objc
_edgeComputePipelineState
_brightExtractPipelineState
_blurPipelineState
_particlePipelineState
_downsamplePipelineState
_upscalePipelineState
```

这表示项目不仅会“画东西”，还会“算东西”。

这是 Metal 很重要的一点：

> Metal 不只是图形 API，它也是通用 GPU 计算 API。

## 9. 创建 argument buffer 相关对象

```objc
_materialArgumentEncoder = [sceneFragmentArg newArgumentEncoderWithBufferIndex:2];
_materialArgumentBuffer = [_device newBufferWithLength:_materialArgumentEncoder.encodedLength
                                               options:MTLResourceStorageModeShared];
```

然后把纹理写进去：

```objc
[_materialArgumentEncoder setArgumentBuffer:_materialArgumentBuffer offset:0];
[_materialArgumentEncoder setTexture:_albedoTexture atIndex:0];
[_materialArgumentEncoder setTexture:_normalTexture atIndex:1];
```

这就是 Argument Buffer 的核心：

> 把多个资源打包进一个“参数块”里，一次性传给 shader。

## 10. 创建深度状态

```objc
depthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
depthDescriptor.depthWriteEnabled = YES;
_depthState = [_device newDepthStencilStateWithDescriptor:depthDescriptor];
```

因为它画的是 3D 立方体，必须有深度测试。

否则前后的面会乱穿。

## 11. 创建 sampler 和 anisotropic sampler

普通 sampler：

```objc
samplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
samplerDescriptor.sAddressMode = MTLSamplerAddressModeRepeat;
samplerDescriptor.tAddressMode = MTLSamplerAddressModeRepeat;
```

各向异性 sampler：

```objc
anisoSamplerDescriptor.maxAnisotropy = 8;
```

这是主题 11 的重点。

## 12. 创建 shared event

```objc
if ([_device respondsToSelector:@selector(newSharedEvent)])
{
    _sharedEvent = [_device newSharedEvent];
}
```

用于同步/调度演示。

## 13. 检查是否支持 ray tracing

```objc
_supportsRayTracing = [_device supportsRaytracing];
```

这里很重要：

### 主题 13 不是完整的光追实现
它是一个 **能力探测 + fallback 演示**

也就是说它想教你的是：

- 高级特性不要硬上
- 先探测能力
- 不支持就降级

这其实很工程化。

## 14. 创建 ICB

```objc
MTLIndirectCommandBufferDescriptor *icbDescriptor = [[MTLIndirectCommandBufferDescriptor alloc] init];
icbDescriptor.commandTypes = MTLIndirectCommandTypeDrawIndexed;
icbDescriptor.inheritPipelineState = YES;
icbDescriptor.inheritBuffers = YES;
...
_indirectCommandBuffer = [_device newIndirectCommandBufferWithDescriptor:icbDescriptor
                                                         maxCommandCount:3
                                                                 options:0];
```

然后预录制 3 条命令：

```objc
for (NSUInteger commandIndex = 0; commandIndex < 3; ++commandIndex)
{
    id<MTLIndirectRenderCommand> prebuiltICBCommand = [_indirectCommandBuffer indirectRenderCommandAtIndex:commandIndex];
    [prebuiltICBCommand drawIndexedPrimitives:...
                                 instanceCount:1
                                   baseInstance:commandIndex];
}
```

### 这段非常值得学

它不是录 3 个不同 mesh，而是：

- 同一个 cube mesh
- 录 3 条 draw 命令
- 用 `baseInstance = commandIndex`
- vertex shader 里根据 `instanceID` 去取不同 transform/tint

所以最终你看到是 3 个对象。

## 15. 创建顶点/索引/实例 buffer

项目里定义了一个立方体：

- 24 个顶点
- 36 个索引

### 为什么不是 8 个顶点？

因为每个面有自己的：

- normal
- uv

所以不能简单复用 8 个角点。

这是 3D 初学者经常忽略的点。

## 16. Shared staging -> Private GPU buffer

这个项目很棒的一点是，它没有偷懒一直用 Shared buffer。

而是：

```objc
id<MTLBuffer> vertexStaging = [_device newBufferWithBytes:... options:MTLResourceStorageModeShared];
_vertexBuffer = [_device newBufferWithLength:... options:MTLResourceStorageModePrivate];
```

然后通过 blit 拷贝：

```objc
[setupBlit copyFromBuffer:vertexStaging ... toBuffer:_vertexBuffer ...];
```

### 这说明什么？

说明作者在教你一个真实工程策略：

- CPU 上传时用 Shared staging
- 真正静态几何数据放 Private
- GPU 读取更高效

## 17. 创建 3 份 uniform buffer

```objc
for (NSUInteger i = 0; i < kMaxFramesInFlight; ++i)
{
    _uniformBuffers[i] = [_device newBufferWithLength:sizeof(Uniforms)
                                               options:MTLResourceStorageModeShared];
}
```

这是非常标准的动态数据做法。

## 18. 创建程序生成纹理

### Albedo texture
`createAlbedoTexture`

生成棋盘+渐变纹理。

### Normal texture
`createNormalTexture`

生成法线贴图风格纹理。

然后生成 mipmaps：

```objc
[setupBlit generateMipmapsForTexture:_albedoTexture];
[setupBlit generateMipmapsForTexture:_normalTexture];
```

这又给主题 11 打了基础。

# 七、Render Target 是怎么设计的？

这个项目最适合你学“为什么要有这么多中间纹理”。

函数：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm`
- `ensureRenderTargetsForDrawable:`

它在窗口尺寸变化时重建以下资源。

## 1. `_sceneMSAATexture`

- 格式：`BGRA8Unorm`
- 类型：2D multisample
- sample count = 4
- 用途：scene pass 的 MSAA 颜色目标

### 它的意义
真正绘制 3D 场景时先写这里，减少锯齿。

## 2. `_sceneResolveTexture`

- 非 MSAA
- 用途：scene resolve 后的单采样结果
- 后续 compute / post 都读它

### 为什么需要它？
因为 compute shader 和普通采样通常都要读单采样纹理，不会直接读 MSAA texture。

## 3. `_sceneDepthTexture`

- 格式：`Depth32Float`
- multisample
- 用于深度测试

## 4. `_edgeTexture`

- 用于存边缘检测结果

## 5. `_postMSAATexture`

post pass 也用了 4x MSAA。

最后 resolve 到：

```objc
drawable.texture
```

## 6. `_bloomTextureA` / `_bloomTextureB`

- 半分辨率
- `RGBA16Float`

用来做：

- 亮部提取
- 高斯模糊 ping-pong

### 为什么半分辨率？
便宜很多。

这是非常典型的 bloom 优化。

## 7. `_particleTexture`

粒子 overlay 结果。

## 8. `_historyTexture`

历史帧结果，用于 temporal blending。

## 9. `_halfResTexture`

用于先把 scene 降采样到半分辨率。

## 10. `_upscaledTexture`

把半分辨率结果再上采样回全分辨率。

## 11. `_spatialScaler`

如果系统支持，就创建：

```objc
id<MTLFXSpatialScaler> _spatialScaler
```

用于主题 14。

## 12. 为什么这些纹理都在 resize 时重建？

因为 `drawableSize` 变了，中间纹理尺寸也必须匹配。

否则容易出现：

- 拉伸
- 黑边
- resolve 尺寸不匹配
- 深度附件尺寸不一致

主题 1 其实就在教这个。

# 八、每一帧 `render()` 到底做了什么？

这是全项目最关键的学习部分。

我按执行顺序给你完整讲。

## 1. 等待 in-flight slot

```objc
dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);
```

目的：

- 限制最多 3 帧在飞
- 避免 CPU 覆盖 GPU 正在使用的数据

## 2. 如果请求了 GPU Capture，就开始抓一帧

```objc
if (_captureNextFrame)
{
    ...
    capturing = [mgr startCaptureWithDescriptor:desc error:&captureErr];
}
```

按 `C` 可以抓一帧，输出到：

- `/tmp/MetalDemo_frame.gputrace`

这对学习 GPU profiling 很有帮助。

## 3. 如果主题 1 且开启错误示例，故意破坏资源复用

```objc
if (_errorExampleEnabled && _demoTopic == MetalDemoTopicResourceMemory)
{
    _sceneResolveTexture = nil;
}
```

这样下一步 `ensureRenderTargetsForDrawable:` 就会强制重建纹理。

它是在故意制造错误路径给你观察。

## 4. 从 layer 拿 drawable

```objc
id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
```

如果拿不到就直接返回。

## 5. 确保中间纹理存在且尺寸匹配

```objc
[self ensureRenderTargetsForDrawable:drawable];
```

## 6. 创建 command buffer

```objc
id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
```

## 7. 给 command buffer 加完成回调

```objc
[commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
    ...
    self->_lastGPUFrameTimeMs = gpuFrameMs;
    dispatch_semaphore_signal(semaphore);
}];
```

这里做两件事：

- 记录 GPU 帧时
- 释放 semaphore slot

非常经典。

## 8. 选择当前 uniform buffer

```objc
NSUInteger uniformIndex = _frameIndex % kMaxFramesInFlight;
_frameIndex++;
```

这就是 3 份 buffer 轮换使用。

## 9. 根据不同主题设置参数和路径开关

这里定义了很多布尔开关：

```objc
BOOL useArgumentShader = ...
BOOL useICB = ...
BOOL useParallel = ...
BOOL useDeferredLike = ...
BOOL useShadow = ...
BOOL usePBR = ...
BOOL useBloom = ...
BOOL useParticles = ...
BOOL useAnisoSampler = ...
BOOL useSyncScheduling = ...
BOOL useRayTraceMode = ...
BOOL useUpscale = ...
BOOL useProfiling = ...
```

这是整个 Demo 的核心教学方法：

> 同一个项目，不断切换不同路径。

这样你不会学成“15 个互相割裂的小 demo”。

## 10. 处理 function constants 主题

```objc
if (_demoTopic == MetalDemoTopicFunctionConstants)
{
    usePBR = fmodf(elapsed, 4.0f) > 2.0f;
    useShadow = !usePBR;
    edgeStrength = 0.25f;
}
```

即主题 3 会在不同变体间切换。

## 11. 按主题设置视觉参数

比如：

### 主题 8：PBR
```objc
exposureBias = 1.25f;
```

### 主题 9：Bloom
```objc
bloomStrength = 0.08f;
```

### 主题 10：Particles
```objc
particleStrength = 0.45f;
```

### 主题 14：Upscale
```objc
sceneMix = 0.82f;
temporalBlend = _historyValid ? 0.6f : 0.0f;
```

## 12. 如果开启错误示例，再故意把参数调坏

比如主题 9：

```objc
bloomStrength = 0.7f;
temporalBlend = _historyValid ? 0.92f : 0.0f;
```

这会导致典型错误：

- bloom 太强
- temporal 拖影

这个设计很适合学习，因为你能同时看到：

- 正确做法
- 错误做法

## 13. 乘上用户在 HUD 面板调的倍率

```objc
timeScale = fmaxf(0.1f, timeScale * _userTimeScaleGain);
edgeStrength = fmaxf(0.0f, edgeStrength * _userEdgeGain);
exposureBias = fmaxf(0.1f, exposureBias * _userExposureGain);
```

所以这个 Demo 不是纯展示，还能交互调参。

## 14. 更新当前实际渲染路径说明

比如：

- `ICB ExecuteCommands (3 cmds / 3 objs)`
- `Parallel Encoder`
- `Argument Buffer Shader`
- `MetalFX Spatial Scaler`
- `Compute Bilinear`
- `Yes: MetalFX unavailable`

这块很工程化，因为它告诉你：

> “你选了某个主题” 和 “机器上实际走了哪条路径” 不一定一样。

这就是 fallback 思维。

## 15. 填 uniform 数据

这里会计算：

- projection
- view
- model
- MVP
- light direction
- time
- exposure
- bloom strength
- topic
- featureFlags

### 相机矩阵
```objc
matrix_float4x4 projection = matrix_perspective(...);
matrix_float4x4 view = matrix_translation(0.0f, 0.0f, -5.2f);
```

### 模型旋转
```objc
matrix_float4x4 rotationY = matrix_rotation(...);
matrix_float4x4 rotationX = matrix_rotation(...);
matrix_float4x4 model = matrix_multiply(rotationY, rotationX);
```

然后写进：

```objc
Uniforms *uniforms = (Uniforms *)_uniformBuffers[uniformIndex].contents;
```

这就是 CPU -> GPU 传 per-frame 参数的标准方式。

## 16. 更新 3 个实例的数据

```objc
InstanceData *instances = (InstanceData *)_instanceBuffer.contents;
```

给 3 个物体分别设置：

- 不同的 x 偏移
- 不同的旋转相位
- 不同的 tint

这就是主题 4 ICB 的 3 个对象来源。

# 九、Scene Pass：真正画 3D 物体

## 1. 先选用哪条 scene pipeline

```objc
id<MTLRenderPipelineState> selectedScenePipeline = _scenePipelineState;
if (useICB) ...
else if (useArgumentShader) ...
else if (usePBR) ...
else if (useShadow) ...
```

这里体现了 Metal 的一个重要思路：

> 不同 shader 组合通常对应不同 pipeline state。

不是一个 pipeline 包打天下。

## 2. 配置 scene pass descriptor

```objc
scenePass.colorAttachments[0].texture = _sceneMSAATexture;
scenePass.colorAttachments[0].resolveTexture = _sceneResolveTexture;
scenePass.colorAttachments[0].loadAction = MTLLoadActionClear;
scenePass.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
scenePass.depthAttachment.texture = _sceneDepthTexture;
```

### 这个很关键

因为 scene color 是 MSAA 纹理，所以 store action 用的是：

```objc
MTLStoreActionMultisampleResolve
```

这意味着：

- 先多采样渲染
- pass 结束时 resolve 到 `_sceneResolveTexture`

于是后续 compute 就能读 `_sceneResolveTexture`。

## 3. 主题 5：Parallel Render Encoding

如果 `useParallel`：

```objc
id<MTLParallelRenderCommandEncoder> parallelEncoder =
    [commandBuffer parallelRenderCommandEncoderWithDescriptor:scenePass];
```

然后拿两个子 encoder：

```objc
id<MTLRenderCommandEncoder> enc1 = [parallelEncoder renderCommandEncoder];
id<MTLRenderCommandEncoder> enc2 = [parallelEncoder renderCommandEncoder];
```

分别在两个 GCD 任务里编码。

### 这是什么概念？

普通情况是：

- 一个线程编码所有 draw call

Parallel Encoder 允许：

- 多线程同时编码
- 最后归并到同一个 render pass

### 这个 Demo 怎么做的？

它把立方体索引分成两半：

- 前半给 enc1
- 后半给 enc2

这是教学用法。  
真实项目一般会按：

- 对象批次
- 材质分组
- 可见性分区

来拆分。

## 4. 普通 Scene Pass 路径

如果不是 parallel，就用普通 render encoder：

```objc
id<MTLRenderCommandEncoder> sceneEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:scenePass];
```

设置：

- pipeline
- depth state
- cull mode
- winding
- vertex buffers
- fragment buffers
- textures
- sampler

然后 draw。

## 5. ICB 路径

如果主题 4 且支持 ICB：

```objc
[sceneEncoder executeCommandsInBuffer:_indirectCommandBuffer withRange:NSMakeRange(0, 3)];
```

### 初学者怎么理解 ICB？

正常模式下，每帧 CPU 都在 encoder 里一条条写 draw call。  
ICB 模式下，你可以先把 draw 命令录到间接命令缓冲里，然后正式渲染时直接执行它。

这更接近“命令列表复用”的思路。

## 6. 为什么 ICB 用了一个特殊 fragment shader？

shader 里有：

```metal
fragment float4 scene_fragment_icb(SceneVertexOut in [[stage_in]])
```

这个版本**故意不依赖 fragment 资源**，没有：

- fragment buffer
- texture
- sampler

这样更保守，兼容性更高。

这也是工程化处理，不是为了炫技。

# 十、Compute Pass：后处理和图像计算

这个项目 compute 部分很适合学习，因为非常具体。

## 1. Edge Detect

先对 scene resolve 结果做边缘检测：

```objc
[computeEncoder setComputePipelineState:_edgeComputePipelineState];
[computeEncoder setTexture:_sceneResolveTexture atIndex:0];
[computeEncoder setTexture:_edgeTexture atIndex:1];
```

shader 是：

```metal
kernel void edge_detect_kernel(...)
```

内部用了类似 Sobel 的 3x3 邻域梯度：

- 采样 9 个点
- 算 `gx` / `gy`
- 边缘强度写入 `edgeTexture`

### 这有什么教学意义？

它让你明白：

- compute shader 非常适合图像处理
- 纹理可以作为读写资源
- `thread_position_in_grid` 就像每个像素的并行线程坐标

## 2. Deferred-like 路径

主题 6 会先单独跑一次 edge compute，再进入 post。

这不是完整 deferred shading，  
而是“**先做中间结果，再统一合成**”的 deferred-like 思路。

### 注意
它**没有 GBuffer**，所以不是正宗 deferred renderer。

这是一个教学简化版。

## 3. Bloom

Bloom 包含三步：

### A. bright extract
从 scene 中提取亮部：

```metal
kernel void bright_extract_kernel(...)
```

而且它顺便做了**2x2 box 下采样**，输出到半分辨率纹理。

### B. blur horizontal
### C. blur vertical

两个方向分开做高斯模糊，这是非常经典的 separable blur。

### 为什么要分两次模糊？
因为比直接二维高斯便宜很多。

## 4. Particle Overlay

```metal
kernel void particle_overlay_kernel(...)
```

它直接在每个像素位置遍历一组“虚拟粒子中心”，累加颜色。

这不是实体粒子模拟，而是**屏幕空间粒子 overlay 演示**。

适合教学，因为逻辑简单、效果直观。

## 5. Downsample / Upscale

主题 14 先做：

```metal
kernel void downsample_half_kernel(...)
```

把 scene 降到半分辨率。

然后：

- 有 `MetalFX` 就用 `_spatialScaler`
- 没有就用 `upscale_linear_kernel`

### 这是什么思路？
低分辨率渲染 -> 高分辨率显示

本质是“用分辨率换性能”。

# 十一、Post Pass：把所有结果合成到屏幕

post pass 用了一个非常经典的技巧：

## 全屏三角形

shader：

```metal
vertex PostVertexOut post_vertex(uint vertexID [[vertex_id]])
```

只生成 3 个顶点：

```metal
float2 positions[3] = {
    float2(-1.0, -1.0),
    float2(3.0, -1.0),
    float2(-1.0, 3.0)
};
```

### 为什么不是全屏四边形？
因为全屏三角形更简单，避免对角线拼接问题，也更常见于现代图形 API。

## post_fragment 做了什么？

```metal
fragment float4 post_fragment(...)
```

它会读取：

- `sceneTexture`
- `edgeTexture`
- `bloomTexture`
- `particleTexture`
- `historyTexture`

然后做：

1. scene color
2. 加 edge tint
3. 加 bloom
4. 加 particles
5. tone mapping
6. temporal blending
7. 输出最终颜色

### tone mapping 公式
```metal
float3 tonemapped = 1.0 - exp(-hdr * params.exposure);
```

这是一个非常常见、简单的曝光映射形式。

## temporal blending 是什么？

```metal
float3 temporal = mix(tonemapped, history, params.temporalBlend);
```

它会把当前帧和历史帧混合。

好处：

- 平滑闪烁
- 提升稳定性

坏处：

- 参数不对会拖影

这正是主题 9 和 14 里让你观察的东西。

# 十二、History Blit：为什么要 copy 历史帧？

post pass 后，如果需要 temporal 或 upscale，就把结果拷到 `_historyTexture`：

```objc
id<MTLBlitCommandEncoder> historyBlit = [commandBuffer blitCommandEncoder];
[historyBlit copyFromTexture:sceneForPost ... toTexture:_historyTexture ...];
```

### 为什么不用 shader 写？
因为这里本质是一次纯拷贝，blit 更合适。

# 十三、present 和 commit

最后：

```objc
[commandBuffer presentDrawable:drawable];
[commandBuffer commit];
```

这两句要牢牢记住：

- `presentDrawable`：告诉系统“这帧做好了，拿去显示”
- `commit`：把 command buffer 真正提交给 GPU

没有 `commit`，前面全白写。

# 十四、Shader 逐个讲解

下面我把 shader 按初学者视角讲透。

## 1. `scene_vertex`

```metal
vertex SceneVertexOut scene_vertex(...)
```

输入：

- 顶点数组 `vertices`
- 每帧 uniform `uniforms`
- 实例数组 `instances`
- `vertexID`
- `instanceID`

输出：

- 裁剪空间位置 `position`
- 世界坐标 `worldPosition`
- 世界法线 `worldNormal`
- 顶点颜色
- uv

### 为什么要输出这些？
因为 fragment shader 后面要用：

- 世界位置算光照
- 世界法线算明暗
- uv 采样纹理

## 2. 为什么主题 4 特判了 `demoTopic == 4`？

```metal
if (uniforms.demoTopic == 4u)
{
    InstanceData instance = instances[instanceID];
    ...
}
```

因为 ICB 路径是 3 条命令 / 3 个对象，它需要根据 `instanceID` 取不同变换。

这就是“同一个 mesh，画成多个对象”的方式。

## 3. `scene_fragment`

这是主 fragment shader。

先采样：

- albedo
- normal

### Argument Buffer 模式
如果 `kUseArgumentBuffer` 为真：

```metal
albedoSample = materialArgs.albedo.sample(...)
```

否则走普通纹理绑定：

```metal
albedoSample = albedoTexture.sample(...)
```

### 这正好教会你：
同样的 shader 功能，可以有两种资源绑定方式。

## 4. 法线贴图的处理

这段很值得学：

```metal
float3 Ngeo = normalize(in.worldNormal);
float3 upRef = abs(Ngeo.y) < 0.99 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
float3 T = normalize(cross(upRef, Ngeo));
float3 B = normalize(cross(Ngeo, T));
float3 Nmap = normalize(T * normalSample.x + B * normalSample.y + Ngeo * normalSample.z);
```

因为立方体面是轴对齐的，这里直接根据几何法线构造一个简化切线空间。

### 严格来说
真实项目常常会直接提供 tangent / bitangent。  
这里是教学简化版。

## 5. 非 PBR 路径

非 PBR 时它用的是传统风格：

- ambient
- diffuse
- specular

```metal
float3 ambient = ...
float3 diffuse = ...
float3 spec = ...
```

这是最适合新手理解的光照模型。

## 6. PBR 路径

如果 `kUsePBR` 为真，就走 Cook-Torrance 风格 BRDF：

- Fresnel
- GGX 分布
- Geometry 项
- metallic / roughness

里面能看到这些典型名词：

- `F0`
- `D`
- `G`
- `specBRDF`
- `kS`
- `kD`

### 初学者怎么理解？
不用一上来背公式。你先记住：

- `roughness` 决定表面粗糙程度
- `metallic` 决定它像金属还是非金属
- `Fresnel` 表示掠射角反射更强
- PBR 比传统高光更稳定、更统一

## 7. fake shadow

无论非 PBR 还是 PBR，只要 `kUseShadow` 为真，就会：

```metal
float fakeShadow = smoothstep(0.0, 1.0, in.worldPosition.y * 0.5 + 0.5);
shadow = mix(...);
```

这不是真正 shadow map，只是一个基于世界坐标 y 的阴影因子演示。

### 所以主题 7 教的是“阴影概念”
不是完整阴影系统。

这点你要分清。

## 8. `scene_fragment_icb`

这是 ICB 兼容版 fragment。

它故意只用：

- `in.worldNormal`
- `in.worldPosition`
- `in.color`

不读任何外部纹理资源。

这样更容易在 ICB pipeline 下稳定工作。

## 9. `post_vertex`

生成全屏三角形。

这在图形开发中非常常见，建议你记住。

## 10. `post_fragment`

这是后处理合成核心。

它综合了：

- scene
- edge
- bloom
- particle
- history
- vignette
- exposure
- temporal

你可以把它理解成：

> “最终调色台”

## 11. `edge_detect_kernel`

这是最标准的 compute 图像处理教学例子之一。

重点看：

- `thread_position_in_grid`
- 越界判断
- 邻域采样
- Sobel 梯度
- 写出纹理

学会这一个 kernel，你对 compute shader 的基本工作模式就有感觉了。

## 12. `bright_extract_kernel`

这个 kernel 很适合学“一个 pass 同时做两件事”：

- 提亮部
- 做 2x downsample

很实用。

## 13. `blur_kernel`

这个 kernel 教你 separable blur。

注意它传了一个 `horizontal` 参数：

- 1：横向
- 0：纵向

同一个 kernel，重复利用。

## 14. `particle_overlay_kernel`

它没有维护传统粒子数组，而是直接公式化生成一些动态亮点。

这是教学取巧，但很适合新手。

因为你不用先学：

- 粒子生命周期
- SSBO/Buffer 更新
- GPU 粒子模拟

就能先感受到“compute 生成屏幕效果”。

## 15. `downsample_half_kernel` / `upscale_linear_kernel`

这是主题 14 的基础。

- downsample：4 邻域平均
- upscale：双线性插值

如果你以后学 TAAU、FSR、DLSS、MetalFX，会发现思路都从这里起步。

# 十五、15 个主题到底各教你什么？

我按“概念 + 本项目实际实现 + 你该怎么看”来讲。

## 主题 1：Resource And Memory Modes

### 教什么
- 资源何时创建
- 什么时候该重建
- Shared / Private 的思路

### 本项目怎么做
- 中间纹理按 drawable 尺寸重建
- 静态几何用 staging -> private
- 动态 uniform 用 shared

### 你要学会
> Metal 里资源管理不是“能跑就行”，而是“什么时候建、建在哪、是否复用”。

## 主题 2：Argument Buffer Binding

### 教什么
- 资源打包绑定
- 减少离散 `setTexture`

### 本项目怎么做
- 创建 `MTLArgumentEncoder`
- 把 albedo / normal 写进 argument buffer
- shader 变体里通过 `materialArgs` 读取

### 你要学会
> Argument Buffer 是“资源描述块”，很适合材质系统。

## 主题 3：Function Constants

### 教什么
- 编译期 shader 变体
- 少走运行时分支

### 本项目怎么做
- `kUsePBR`
- `kUseShadow`
- `kUseArgumentBuffer`

### 你要学会
> 低频功能开关适合做 function constants，高频参数适合放 uniform。

## 主题 4：Indirect Command Buffer

### 教什么
- 间接绘制命令
- 命令预录制与执行

### 本项目怎么做
- 创建 `_indirectCommandBuffer`
- 预录制 3 条 drawIndexed 命令
- render 时 `executeCommandsInBuffer`

### 你要学会
> ICB 更像“命令缓存/命令列表复用”，不是每帧都必须直接编码 draw call。

## 主题 5：Parallel Render Encoding

### 教什么
- 多线程编码渲染命令

### 本项目怎么做
- `parallelRenderCommandEncoder`
- 2 个子 encoder 并行编码

### 你要学会
> Parallel Encoder 优化的是 CPU 编码阶段，不是 GPU 执行本身。

## 主题 6：Deferred Style Composition

### 教什么
- 多阶段中间结果再合成

### 本项目怎么做
- 先 scene
- 再 edge compute
- 再 post 合成

### 你要学会
> deferred 的核心思想不是“必须 GBuffer”，而是“阶段化中间结果”。

## 主题 7：Shadowing Techniques

### 教什么
- 阴影是可见性问题

### 本项目怎么做
- 用 fake shadow 因子演示阴影影响

### 你要学会
> 这个主题是概念引导，不是完整 shadow map 实现。

## 主题 8：PBR Shading

### 教什么
- 金属度/粗糙度
- Cook-Torrance BRDF

### 本项目怎么做
- PBR 变体 fragment shader

### 你要学会
> PBR 是现代材质基础，但这里是简化教学版，不是工业级材质系统。

## 主题 9：HDR Bloom And Temporal

### 教什么
- 亮部提取
- 模糊
- 时域混合
- tone mapping

### 本项目怎么做
- bright extract
- blur H/V
- post 中 exposure + temporal

### 你要学会
> 这更像“HDR/Bloom/TAA 思路演示”，不是完整高动态范围渲染器。

## 主题 10：Compute Particles

### 教什么
- compute 生成视觉效果

### 本项目怎么做
- 屏幕空间粒子 overlay

### 你要学会
> compute shader 不只做物理，也能直接做图像层效果。

## 主题 11：Advanced Texture Sampling

### 教什么
- mipmap
- anisotropic filtering

### 本项目怎么做
- 启动时生成 mipmap
- 切换 anisotropic sampler

### 你要学会
> 纹理“采样方式”本身就是画质重要来源。

## 主题 12：Synchronization And Scheduling

### 教什么
- CPU/GPU 帧同步
- 在飞帧数控制

### 本项目怎么做
- semaphore
- completed handler
- shared event signal

### 你要学会
> GPU 编程里，同步比绘制本身还容易出问题。

## 主题 13：Ray Tracing Fallback

### 教什么
- 能力探测
- 特性降级

### 本项目怎么做
- `supportsRaytracing`
- 不同参数和 fallback 提示

### 你要学会
> 真正的工程能力不是“支持新特性”，而是“新特性不支持时也能跑”。

## 主题 14：MetalFX Style Upscaling

### 教什么
- 低分辨率渲染 + 上采样

### 本项目怎么做
- downsample
- MetalFX Spatial Scaler 或 compute bilinear fallback
- temporal blend

### 你要学会
> 这不是完整的 MetalFX 超分系统，但很适合你理解“上采样链路”长什么样。

## 主题 15：Profiling And Debug Markers

### 教什么
- 调试分组
- GPU Capture
- 性能定位

### 本项目怎么做
- `pushDebugGroup`
- 按 `C` 单帧捕获
- 统计 CPU/GPU frame time

### 你要学会
> 图形程序优化不是靠猜，是靠 profile。

# 十六、这个项目有哪些“非常值得新手学”的工程点？

我挑几个最值钱的。

## 1. 资源按尺寸重建，不是每帧乱建
这是图形程序最基础的工程习惯。

## 2. static 和 dynamic 资源分开处理
- 静态 mesh：Private
- 动态 uniform：Shared

这很对。

## 3. 先渲染到中间纹理，再做后处理
比直接对 drawable 硬搞靠谱得多。

## 4. 每个高级特性都有 fallback
特别是：

- ICB fallback
- MetalFX fallback
- ray tracing capability fallback

这非常真实。

## 5. 有 HUD、有说明页、有错误示例
这说明项目不是只追求“代码能跑”，而是在做“教学体验”。

# 十七、你应该按什么顺序学这个项目？

如果你是 Metal 小白，我建议你不要 1~15 顺着死看，而是按下面顺序学。

## 第一阶段：先建立渲染基本骨架
先看：

1. `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/main.mm`
2. `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/AppDelegate.mm`
3. `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm` 里的 `initWithLayer:`
4. `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm` 里的 `render`
5. `/Users/mtl/Learn/my-demo/MetalCMakeDemo/shaders/triangle.metal` 的
   - `scene_vertex`
   - `scene_fragment`
   - `post_vertex`
   - `post_fragment`

### 这一阶段你要弄明白的只有 5 件事
- layer 是什么
- drawable 是什么
- command buffer 是什么
- render pass 是什么
- shader 怎么接收数据

## 第二阶段：理解资源和数据流
重点看：

- `createAlbedoTexture`
- `createNormalTexture`
- `ensureRenderTargetsForDrawable:`
- uniform / instance buffer 的写法

### 目标
搞懂：
- buffer 放什么
- texture 放什么
- 为什么有这么多中间纹理

## 第三阶段：学图形 + compute 混合管线
重点看：

- `edge_detect_kernel`
- `bright_extract_kernel`
- `blur_kernel`
- `particle_overlay_kernel`
- `post_fragment`

### 目标
理解：
> Metal 不只是画三角形，它还可以把图像处理串进一帧里。

## 第四阶段：学“高级但实用”的主题
按这个顺序看：

1. 主题 3 Function Constants
2. 主题 2 Argument Buffer
3. 主题 5 Parallel Encoding
4. 主题 4 ICB
5. 主题 14 MetalFX Like
6. 主题 15 Profiling

# 十八、如果你拿这个项目学 Metal，我建议你这样做实验

这部分很重要。  
只看代码，吸收会慢。你最好一边改一边学。

## 实验 1：先把 edge effect 关掉
在 `render()` 里把：

```objc
edgeStrength = 0.9f;
```

改小或设成 0。

观察：

- 后处理前后差异
- `edgeTexture` 对最终图像影响

## 实验 2：把 PBR 和非 PBR 切换对比
对比主题 8 和默认主题。

观察：

- 高光形状
- 明暗过渡
- 材质真实感

## 实验 3：故意关掉 mipmap
注释掉：

```objc
[setupBlit generateMipmapsForTexture:_albedoTexture];
[setupBlit generateMipmapsForTexture:_normalTexture];
```

再看主题 11。

你会更容易体会 mipmap 的价值。

## 实验 4：把 `framebufferOnly` 改成 `NO`
然后试着思考：

- 为什么默认设成 `YES`
- 什么情况下必须设 `NO`

这是理解 drawable 用途的很好方式。

## 实验 5：只保留 scene pass
先临时删掉：

- edge compute
- bloom
- particles
- post composite 的额外项

只留下最简单路径。

这样你能看懂“最基础的 Metal 一帧”长什么样。

## 实验 6：在 shader 里直接输出法线颜色
把 fragment 改成：

```metal
return float4(normalize(in.worldNormal) * 0.5 + 0.5, 1.0);
```

你会快速建立：

- 世界法线
- 颜色可视化
- shader 调试

的直觉。

# 十九、你现在最需要记住的几个 Metal 核心概念

如果你看完只记住下面这些，也已经很值了。

## 1. Metal 一帧的基本套路

**拿 drawable -> 建 command buffer -> 编 render/compute/blit -> present -> commit**

## 2. Render Pipeline 不是“函数”，是“配置好的 GPU 生产线”

## 3. Shader 负责算，Pipeline 负责组织 Shader 怎么跑

## 4. Buffer 通常放结构化数据，Texture 通常放图像数据

## 5. 3D 场景离不开深度测试

## 6. 后处理通常不直接改 scene，而是读 scene texture 再全屏合成

## 7. Compute shader 特别适合图像处理与通用并行计算

## 8. 真正的项目一定要考虑：
- 资源复用
- resize
- fallback
- profile
- CPU/GPU 同步

# 二十、我对这个项目的总体评价

如果站在“拿它学 Metal”的角度，我会这样评价：

### 优点非常明显
- 结构清晰
- 主题丰富
- 不是纯炫技，是真的在教工程思维
- 既有图形，也有 compute
- 有 profiling / capture / fallback
- 对初学者很友好，因为有 HUD 和说明页

### 也要知道它不是“完整引擎”
有些主题是**概念演示版**，不是工业级完整实现，比如：
- 主题 6 不是完整 deferred renderer
- 主题 7 不是完整 shadow map
- 主题 13 不是完整 ray tracing
- 主题 14 不是完整 temporal super-resolution

但这恰恰是它适合学习的原因：  
**复杂度控制得刚刚好。**

# 二十一、给你的最佳学习路线总结

如果你问我：  
“我现在就想靠这个项目入门 Metal，最优路线是什么？”

我会建议你：

### 第 1 天
只看：
- `AppDelegate.mm`
- `Renderer.mm` 的初始化和 `render`
- shader 里的 `scene_vertex / scene_fragment / post_fragment`

目标：明白一帧怎么跑起来。

### 第 2 天
只看资源：
- buffer
- texture
- sampler
- render target
- resize 重建

目标：明白 GPU 数据住在哪里。

### 第 3 天
只看 compute：
- edge
- bloom
- particles
- downsample/upscale

目标：明白 Metal 不只是渲染 API。

### 第 4 天
看进阶主题：
- Function Constants
- Argument Buffer
- ICB
- Parallel Encoder

### 第 5 天
看工程部分：
- profiling
- capture
- fallback
- synchronization

如果你愿意，我下一步可以继续直接带你做两件事中的任意一个：

1. **按源码顺序，逐行讲解 `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm` 的 `initWithLayer:` 和 `render()`**
2. **专门开一节“Metal 零基础入门课”，把 Device / CommandBuffer / Pipeline / Shader / Texture / MSAA / Depth 用图解方式讲清楚**

如果你想，我也可以下一条直接给你画一个**“这个项目的一帧渲染流程图”**。

---

## 第 2 轮

**用户：**

按源码顺序，逐行讲解 /Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm 的 initWithLayer: 和 render()
专门开一节“Metal 零基础入门课”，把 Device / CommandBuffer / Pipeline / Shader / Texture / MSAA / Depth 用图解方式讲清楚
都需要

**助手：**

太好了，这两个部分其实正好能互相补上：

- **“Metal 零基础入门课”**：帮你建立世界观，不然你看源码会像看天书。
- **“按源码顺序讲 `initWithLayer:` 和 `render()`”**：帮你把世界观落到这个项目的具体实现上。

我下面就按这个顺序来：

1. **第一部分：Metal 零基础入门课**
2. **第二部分：逐行讲解 `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm` 里的 `initWithLayer:`**
3. **第三部分：逐行讲解 `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm` 里的 `render()`**
4. **第四部分：你现在最该怎么继续学**

# 第一部分：Metal 零基础入门课

我先用一句最朴素的话讲 Metal：

> **Metal 是 Apple 提供的 GPU 编程接口。**  
> 你可以用它让 GPU 去画图，也可以让 GPU 去做并行计算。

如果再通俗一点：

- **CPU** 擅长“组织、调度、逻辑判断”
- **GPU** 擅长“成千上万次相似的小计算并行执行”

在图形程序里，通常是：

- CPU 准备数据、配置渲染流程
- GPU 负责真正把图像算出来

## 1. 先建立最核心的脑图

你可以把 Metal 先想成这条链：

```mermaid
flowchart LR
    "App / CPU 代码" --> "MTLDevice"
    "MTLDevice" --> "MTLCommandQueue"
    "MTLCommandQueue" --> "MTLCommandBuffer"
    "MTLCommandBuffer" --> "Render Encoder"
    "MTLCommandBuffer" --> "Compute Encoder"
    "Render Encoder" --> "Render Pipeline State"
    "Compute Encoder" --> "Compute Pipeline State"
    "Render Pipeline State" --> "Shaders"
    "Compute Pipeline State" --> "Shaders"
    "Shaders" --> "Textures / Buffers"
    "Textures / Buffers" --> "Drawable Texture"
    "Drawable Texture" --> "屏幕"
```

你先不要怕这些名词。下面我逐个翻译成人话。

## 2. `MTLDevice`：GPU 的入口

### 它是什么
`MTLDevice` 代表当前可用的 Metal 设备，通常就是你这台机器上的 GPU。

在这个项目里：

```objc
_device = MTLCreateSystemDefaultDevice();
```

### 你怎么理解它
你可以把它当成：

> “Metal 世界的大门”

因为很多资源都得从它这里创建：

- `MTLCommandQueue`
- `MTLBuffer`
- `MTLTexture`
- `MTLRenderPipelineState`
- `MTLComputePipelineState`

### 类比
如果你写数据库程序：

- 先连数据库
- 再建表/查表

那在 Metal 里：

- 先拿到 `MTLDevice`
- 再创建一切 GPU 资源

## 3. `MTLCommandQueue`：命令投递通道

### 它是什么
命令队列。

```objc
_commandQueue = [_device newCommandQueue];
```

### 你怎么理解它
CPU 不会直接对 GPU 说：

> “你现在立刻给我画个立方体。”

而是说：

> “我先写一份命令清单，等下交给你。”

`MTLCommandQueue` 就是这个“投递通道”。

## 4. `MTLCommandBuffer`：一帧 GPU 工作清单

### 它是什么
每一帧通常都会创建一个 command buffer。

```objc
id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
```

### 你怎么理解它
它像一张“本帧施工单”：

- 先画场景
- 再做边缘检测
- 再做 bloom
- 再做 post process
- 最后显示到屏幕

GPU 不会在你写代码那一刻立刻执行；  
而是等你把命令都写进 command buffer，最后：

```objc
[commandBuffer commit];
```

才真正开始执行。

### 类比
像点外卖：

- 你先选菜（编码命令）
- 最后点击下单（commit）
- 厨房才开始做（GPU 执行）

## 5. Encoder：往 command buffer 里写不同类型命令的工具

CommandBuffer 是“总单子”，Encoder 是“分工的小本子”。

主要有三种：

### 5.1 `MTLRenderCommandEncoder`
用于**渲染命令**

比如：

- 设置渲染管线
- 设置顶点 buffer
- 设置纹理
- 发起 draw call

### 5.2 `MTLComputeCommandEncoder`
用于**计算命令**

比如：

- 跑边缘检测
- 跑高斯模糊
- 跑粒子 overlay
- 跑上采样

### 5.3 `MTLBlitCommandEncoder`
用于**拷贝和搬运**

比如：

- buffer -> buffer
- texture -> texture
- 生成 mipmaps

## 6. Shader：跑在 GPU 上的小程序

Shader 是你写给 GPU 的代码。

这个项目在：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/shaders/triangle.metal`

### 常见几种 shader

#### Vertex Shader
输入顶点数据，输出变换后的位置。

#### Fragment Shader
输入片元/像素相关数据，输出颜色。

#### Compute Kernel
输入任意资源，做通用并行计算。

## 7. Pipeline State：GPU 的“固定生产线配置”

这是新手最容易模糊的概念之一。

### 它是什么
Pipeline State 不是 shader 本身，而是：

> “shader + 目标格式 + 采样数 + 其它固定状态”  
> 组合成的一条完整 GPU 工作管线。

比如 render pipeline state 会固定：

- vertex shader 是谁
- fragment shader 是谁
- 颜色附件像素格式
- 深度格式
- MSAA sample count

### 为什么不直接“设置 shader 就行”
因为现代 GPU 很多状态是要**预编译、预组合**的。  
提前做成 pipeline state，运行时切换会更快、更稳定。

### 类比
shader 像厨师。  
pipeline state 像“厨房整套配置”：

- 这个灶台干煎还是油炸
- 用哪套工具
- 出餐盘是什么规格

不是只换一个厨师那么简单。

## 8. Buffer：一维数据块

### 它是什么
`MTLBuffer` 是线性内存。

### 常放什么
- 顶点数据
- 索引数据
- uniform 数据
- instance 数据

### 本项目里的例子
- `_vertexBuffer`
- `_indexBuffer`
- `_instanceBuffer`
- `_uniformBuffers[...]`
- `_materialArgumentBuffer`

## 9. Texture：二维/三维图像资源

### 它是什么
`MTLTexture` 是 GPU 上的图像资源。

### 常放什么
- 颜色纹理
- 法线纹理
- 深度纹理
- 中间渲染结果
- bloom 结果
- history 结果

### 本项目里的例子
- `_albedoTexture`
- `_normalTexture`
- `_sceneResolveTexture`
- `_edgeTexture`
- `_historyTexture`

## 10. Drawable：当前这一帧真正显示到屏幕的目标

这个项目里通过 `CAMetalLayer` 获取：

```objc
id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
```

它最关键的是：

```objc
drawable.texture
```

### 你怎么理解它
它就是：

> “这一帧屏幕最终要显示的那张纹理”

## 11. `CAMetalLayer`：把 GPU 输出接到窗口上的那层

这个项目里窗口上的视图背后挂了一个 `CAMetalLayer`。

### 它的作用
- 管理 drawable
- 和窗口/屏幕系统打交道
- 提供最终显示目标

### 你怎么理解它
它是 Metal 和 macOS 窗口系统之间的桥。

## 12. Render Pass：一次“画图阶段”

一次 render pass 通常意味着：

- 指定颜色附件
- 指定深度附件
- 指定 load/store 行为
- 编码 draw call
- 结束

本项目中有两个主要 render pass：

1. **scene pass**
2. **post pass**

## 13. Compute Pass：一次“GPU 并行计算阶段”

和 render pass 不同，compute pass 不关心三角形栅格化，而是关心：

- 每个线程处理哪个像素/数据
- 读什么 texture
- 写什么 texture

本项目里多个 compute pass 用来做：

- edge detect
- bright extract
- blur
- particles
- downsample/upscale

## 14. Depth：深度缓冲到底是什么？

这是 3D 初学者必须搞懂的。

### 问题
如果两个三角形在屏幕上重叠，谁在前面？

只靠绘制顺序不靠谱。  
我们需要知道“谁离相机更近”。

### 解决办法
GPU 为每个像素位置记录一个深度值，这就是 **depth buffer**。

### 简化理解
比如同一个屏幕像素位置：

- 物体 A 深度 = 0.3
- 物体 B 深度 = 0.7

那 A 更近，就显示 A。

### 图解

```text
摄像机
  |
  v

 [近]   物体A   z=0.3
 [远]   物体B   z=0.7

同一个屏幕像素位置上，A 赢，B 被挡住
```

### 本项目怎么用
创建了：

- `_sceneDepthTexture`
- `_depthState`

并设置：

```objc
depthCompareFunction = MTLCompareFunctionLess;
depthWriteEnabled = YES;
```

意思是：

- 新像素深度更小（更近）才通过
- 通过后写入深度缓冲

## 15. MSAA：抗锯齿是什么？

### 为什么会有锯齿
因为屏幕是像素格子，斜线/边缘会有台阶感。

### MSAA 的思路
一个像素不是只采样一次，而是采样多次。

比如 4x MSAA：

```text
一个像素内部不是 1 个采样点，而是 4 个采样点
```

如果三角形边缘只覆盖了其中一部分采样点，那最后 resolve 后颜色就会更平滑。

### 粗略图解

```text
无 MSAA:
+---+
|###|
|###|
+---+
边缘一刀切，锯齿明显

4x MSAA:
+---+
|##.|
|###|
+---+
部分覆盖 -> resolve 后过渡更平滑
```

### 本项目怎么用
scene pass 和 post pass 都用了：

```objc
static const NSUInteger kSampleCount = 4;
```

并且颜色附件：

- 先写 MSAA texture
- 最后 resolve 到单采样 texture

## 16. Resolve 是什么？

如果你用了 MSAA，最后要把多采样纹理“合并”成普通单采样纹理。  
这个过程就是 **resolve**。

### 本项目的例子
scene pass：

- `_sceneMSAATexture`：多采样颜色目标
- `_sceneResolveTexture`：resolve 后的普通纹理

post pass：

- `_postMSAATexture`
- `drawable.texture`

## 17. Sampler：决定“怎么读纹理”

采样纹理时，不只是“读哪个坐标”，还要决定：

- nearest 还是 linear
- 超出边界怎么处理
- 是否启用各向异性过滤

本项目有两个 sampler：

- `_samplerState`
- `_anisoSamplerState`

## 18. Mipmap：远处纹理为什么不闪

当纹理被缩小显示时，如果你还直接从原图采样，容易：

- 抖动
- 锯齿
- 摩尔纹

### 解决办法
提前生成多层更小的纹理版本，这就是 mipmap。

### 本项目做法
启动时：

```objc
[setupBlit generateMipmapsForTexture:_albedoTexture];
[setupBlit generateMipmapsForTexture:_normalTexture];
```

## 19. Argument Buffer：资源打包

正常情况下你可能会这样绑定：

- `setTexture(albedo, 0)`
- `setTexture(normal, 1)`

Argument Buffer 则可以把它们装进一个 buffer 里，shader 侧当成“资源结构体”读取。

### 好处
- 更适合材质系统
- 更适合批量资源管理
- 减少离散绑定逻辑

## 20. Function Constants：编译期开关

这和普通 if 不一样。

普通 if 是运行时判断。  
Function Constants 是**编译期生成多个 shader 版本**。

本项目里：

- PBR 版
- Shadow 版
- Argument Buffer 版
- Base 版

## 21. 一帧渲染流程图

你现在可以先记住这个项目的一帧是这样走的：

```mermaid
flowchart TD
    "CADisplayLink 触发一帧" --> "Renderer.render()"
    "Renderer.render()" --> "nextDrawable"
    "nextDrawable" --> "ensureRenderTargetsForDrawable"
    "ensureRenderTargetsForDrawable" --> "Scene Pass"
    "Scene Pass" --> "sceneResolveTexture"
    "sceneResolveTexture" --> "Edge Compute"
    "sceneResolveTexture" --> "Bloom Compute"
    "sceneResolveTexture" --> "Particles / Upscale"
    "Edge Compute" --> "Post Pass"
    "Bloom Compute" --> "Post Pass"
    "Particles / Upscale" --> "Post Pass"
    "Post Pass" --> "drawable.texture"
    "drawable.texture" --> "presentDrawable"
    "presentDrawable" --> "屏幕显示"
```

## 22. 你现在只要记住的最小核心公式

如果你现在觉得信息量太大，就只记这条：

> **Device 创建资源 → CommandBuffer 记录本帧工作 → Encoder 写命令 → Pipeline 决定 GPU 怎么跑 Shader → Shader 读写 Buffer/Texture → 结果写入 Drawable → Present**

这就是 Metal 的骨架。

# 第二部分：逐行讲解 `initWithLayer:`

文件：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm`

方法起始位置：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm:632`

我会按“代码块 + 每行解释”的方式讲。  
完全逐字逐行会非常机械，我会尽量做到**每一行或每几行都解释到位**。

## A. 方法入口与基础初始化

### 代码：632-643

```objc
- (instancetype)initWithLayer:(CAMetalLayer *)layer
{
    self = [super init];
    if (self)
    {
        _metalLayer = layer;
        _device = MTLCreateSystemDefaultDevice();
        if (!_device)
        {
            NSLog(@"No Metal device available.");
            return nil;
        }
```

### 解释

#### `- (instancetype)initWithLayer:(CAMetalLayer *)layer`
这是 `Renderer` 的初始化方法，外部会把一个已经创建好的 `CAMetalLayer` 传进来。

#### `self = [super init];`
先调用父类 `NSObject` 的初始化方法。

#### `if (self)`
确保父类初始化成功后再继续。

#### `_metalLayer = layer;`
把外面传进来的 layer 保存起来，后面每帧会从它获取 drawable。

#### `_device = MTLCreateSystemDefaultDevice();`
创建默认 Metal 设备，也就是获取当前系统上的 GPU 入口。

#### `if (!_device) ... return nil;`
如果机器不支持 Metal，那后面所有 GPU 资源都没法创建，所以直接初始化失败。

## B. 配置 `CAMetalLayer`

### 代码：645-649

```objc
_metalLayer.device = _device;
_metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
_metalLayer.drawableSize = CGSizeMake(_metalLayer.bounds.size.width * _metalLayer.contentsScale,
                                      _metalLayer.bounds.size.height * _metalLayer.contentsScale);
_metalLayer.framebufferOnly = YES;
```

### 解释

#### `_metalLayer.device = _device;`
告诉这个 `CAMetalLayer`：你以后分配 drawable 时，用这个 Metal 设备。

#### `_metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;`
设置最终显示纹理的像素格式。  
`BGRA8Unorm` 是很常见的屏幕输出格式：

- B、G、R、A 四个通道
- 每通道 8 位
- unorm 表示 0~255 映射到 0~1

#### `_metalLayer.drawableSize = ...`
设置实际 drawable 的像素大小。  
不是简单的 view 宽高，而是要乘 `contentsScale`，这样 Retina 屏下才清晰。

#### `_metalLayer.framebufferOnly = YES;`
告诉系统：这个 layer 提供的 drawable texture 主要用于 framebuffer 输出。  
优点通常是更高效。  
代价是不能把它当万能纹理随便采样/写入。

所以这个项目后面才会用**中间纹理**来做后处理，而不是直接读写 drawable。

## C. 初始化帧同步与运行时状态

### 代码：651-671

```objc
_inFlightSemaphore = dispatch_semaphore_create(kMaxFramesInFlight);
_frameIndex = 0;
_startTime = CFAbsoluteTimeGetCurrent();
_demoTopic = MetalDemoTopicResourceMemory;
_errorExampleEnabled = NO;
_userTimeScaleGain = 1.0f;
_userEdgeGain = 1.0f;
_userExposureGain = 1.0f;
_lastCPUFrameTimeMs = 0.0;
_lastGPUFrameTimeMs = -1.0;
_lastEstimatedMemoryMB = 0.0;
_lastTimeScale = 1.0f;
_lastEdgeStrength = 0.9f;
_lastExposure = 1.0f;
_lastBloomStrength = 0.0f;
_lastParticleStrength = 0.0f;
_lastTemporalBlend = 0.0f;
_lastScenePathSummary = @"Standard Direct";
_lastPostPathSummary = @"Post Composite";
_lastUpscalePathSummary = @"Off";
_lastRuntimeFallbackSummary = @"No";
```

### 解释

#### `_inFlightSemaphore = dispatch_semaphore_create(kMaxFramesInFlight);`
创建 in-flight semaphore。  
`kMaxFramesInFlight` 是 3，表示最多允许 3 帧同时在 GPU 上飞。

#### `_frameIndex = 0;`
当前是第 0 帧。

#### `_startTime = CFAbsoluteTimeGetCurrent();`
记录程序启动时间，后面动画旋转需要用到“已过去多少秒”。

#### `_demoTopic = MetalDemoTopicResourceMemory;`
默认主题是 1。

#### `_errorExampleEnabled = NO;`
默认不打开“错误示例”。

#### `_userTimeScaleGain / _userEdgeGain / _userExposureGain`
HUD 面板上用户调的三个倍率，默认都是 1。

#### `_lastCPUFrameTimeMs ... _lastRuntimeFallbackSummary`
这些是给 HUD 显示用的缓存值，不是渲染本身必须的，但对教学很重要。  
比如：

- 上一帧 CPU 花了多少 ms
- 上一帧 GPU 花了多少 ms
- 当前路径是不是 fallback

## D. 创建命令队列

### 代码：673-678

```objc
_commandQueue = [_device newCommandQueue];
if (!_commandQueue)
{
    NSLog(@"Failed to create command queue.");
    return nil;
}
```

### 解释

#### `newCommandQueue`
从 device 创建命令队列。

#### 判空
如果连 command queue 都创建不了，就没法创建 command buffer，也就没法渲染。

## E. 加载 shader library

### 代码：680-697

```objc
NSError *error = nil;
id<MTLLibrary> library = [_device newDefaultLibrary];
if (!library)
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *libraryPath = [mainBundle pathForResource:@"default" ofType:@"metallib"];
    if (libraryPath)
    {
        NSURL *libraryURL = [NSURL fileURLWithPath:libraryPath];
        library = [_device newLibraryWithURL:libraryURL error:&error];
    }
}

if (!library)
{
    NSLog(@"Failed to load Metal library: %@", error);
    return nil;
}
```

### 解释

#### `NSError *error = nil;`
后面很多 Metal 创建函数会把错误写进这里。

#### `[_device newDefaultLibrary]`
尝试加载默认 shader 库。  
通常这是最方便的路径。

#### `if (!library) ...`
如果默认方式没拿到，就手动从 app bundle 里找 `default.metallib`。

#### `newLibraryWithURL`
显式从文件路径加载 shader 库。

#### 最终判空
如果 library 还是拿不到，那说明 `.metal` 编译产物没有成功打包进应用，或者路径有问题。

## F. 取出各个 shader 函数

### 代码：699-715

```objc
id<MTLFunction> sceneVertex = [library newFunctionWithName:@"scene_vertex"];
id<MTLFunction> sceneFragmentICB = [library newFunctionWithName:@"scene_fragment_icb"];
id<MTLFunction> postVertex = [library newFunctionWithName:@"post_vertex"];
id<MTLFunction> postFragment = [library newFunctionWithName:@"post_fragment"];
id<MTLFunction> edgeKernel = [library newFunctionWithName:@"edge_detect_kernel"];
id<MTLFunction> brightKernel = [library newFunctionWithName:@"bright_extract_kernel"];
id<MTLFunction> blurKernel = [library newFunctionWithName:@"blur_kernel"];
id<MTLFunction> particleKernel = [library newFunctionWithName:@"particle_overlay_kernel"];
id<MTLFunction> downsampleKernel = [library newFunctionWithName:@"downsample_half_kernel"];
id<MTLFunction> upscaleKernel = [library newFunctionWithName:@"upscale_linear_kernel"];

if (!sceneVertex || !sceneFragmentICB || !postVertex || !postFragment || !edgeKernel || !brightKernel ||
    !blurKernel || !particleKernel || !downsampleKernel || !upscaleKernel)
{
    NSLog(@"Failed to load one or more Metal shader functions.");
    return nil;
}
```

### 解释

#### `newFunctionWithName:`
从 shader library 中按名字找到对应的 GPU 函数。

这里分两类：

- render shader：
  - `scene_vertex`
  - `scene_fragment_icb`
  - `post_vertex`
  - `post_fragment`
- compute kernel：
  - `edge_detect_kernel`
  - `bright_extract_kernel`
  - `blur_kernel`
  - `particle_overlay_kernel`
  - `downsample_half_kernel`
  - `upscale_linear_kernel`

#### 判空
任意一个函数名写错，或者 shader 没编进去，都可能导致这里失败。

## G. Function Constants：生成 `scene_fragment` 的多个变体

### 代码：717-740

```objc
id<MTLFunction> (^makeSceneFragment)(BOOL, BOOL, BOOL) = ^id<MTLFunction>(BOOL usePBR, BOOL useShadow, BOOL useArg) {
    MTLFunctionConstantValues *constants = [[MTLFunctionConstantValues alloc] init];
    [constants setConstantValue:&usePBR type:MTLDataTypeBool atIndex:0];
    [constants setConstantValue:&useShadow type:MTLDataTypeBool atIndex:1];
    [constants setConstantValue:&useArg type:MTLDataTypeBool atIndex:2];

    NSError *localError = nil;
    id<MTLFunction> fragment = [library newFunctionWithName:@"scene_fragment"
                                             constantValues:constants
                                                      error:&localError];
    if (!fragment)
    {
        NSLog(@"Failed to create scene fragment variant: %@", localError);
    }
    return fragment;
};

id<MTLFunction> sceneFragmentBase = makeSceneFragment(NO, NO, NO);
id<MTLFunction> sceneFragmentPBR = makeSceneFragment(YES, NO, NO);
id<MTLFunction> sceneFragmentShadow = makeSceneFragment(NO, YES, NO);
id<MTLFunction> sceneFragmentArg = makeSceneFragment(NO, NO, YES);
if (!sceneFragmentBase || !sceneFragmentPBR || !sceneFragmentShadow || !sceneFragmentArg)
{
    return nil;
}
```

### 解释

#### `makeSceneFragment`
这是一个 block，用来根据 3 个布尔值生成不同版本的 `scene_fragment`。

#### `MTLFunctionConstantValues`
这里就是 Metal 的 function constants 机制。

它把 shader 里的：

- `kUsePBR`
- `kUseShadow`
- `kUseArgumentBuffer`

在**编译时**固定下来。

#### `sceneFragmentBase`
普通版。

#### `sceneFragmentPBR`
PBR 版。

#### `sceneFragmentShadow`
阴影版。

#### `sceneFragmentArg`
Argument Buffer 版。

#### 为什么这么做
这样后面运行时只需要切 pipeline，而不是在 fragment shader 内部动态走大量分支。

## H. 创建 Scene Render Pipeline

### 代码：743-789

```objc
MTLRenderPipelineDescriptor *scenePipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
scenePipelineDescriptor.vertexFunction = sceneVertex;
scenePipelineDescriptor.fragmentFunction = sceneFragmentBase;
scenePipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
scenePipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
scenePipelineDescriptor.rasterSampleCount = kSampleCount;
```

### 解释

#### `MTLRenderPipelineDescriptor`
先创建描述对象，再用它创建真正的 pipeline state。

#### `vertexFunction = sceneVertex`
顶点阶段用 `scene_vertex`。

#### `fragmentFunction = sceneFragmentBase`
片元阶段先用普通版 `scene_fragment`。

#### `colorAttachments[0].pixelFormat = BGRA8Unorm`
场景 pass 的颜色格式。

#### `depthAttachmentPixelFormat = Depth32Float`
这个 render pipeline 会带深度测试。

#### `rasterSampleCount = kSampleCount`
这里 sample count 是 4，说明 pipeline 是为 4x MSAA 场景准备的。

## I. 创建 ICB 专用 Scene Pipeline

### 代码：750-758

```objc
MTLRenderPipelineDescriptor *sceneICBPipelineDescriptor = [scenePipelineDescriptor copy];
sceneICBPipelineDescriptor.fragmentFunction = sceneFragmentICB;
sceneICBPipelineDescriptor.supportIndirectCommandBuffers = YES;
_sceneICBPipelineState = [_device newRenderPipelineStateWithDescriptor:sceneICBPipelineDescriptor error:&error];
if (!_sceneICBPipelineState)
{
    NSLog(@"ICB scene pipeline unavailable, topic 4 will fall back to direct draw: %@", error);
    error = nil;
}
```

### 解释

#### `copy`
从普通 scene pipeline 描述复制一份出来。

#### `fragmentFunction = sceneFragmentICB`
把片元函数换成 ICB 兼容版。

#### `supportIndirectCommandBuffers = YES`
这是关键：告诉 Metal 这条 pipeline 要支持 ICB。

#### 如果失败不 return nil`
这里很值得学。  
ICB 是“高级功能”，失败不代表整个程序不能跑，所以这里只记录日志，后面 fallback 到 direct draw。

这体现了项目的工程思路：**高级特性失败 ≠ 应用整体失败**。

## J. 创建几条 Scene Pipeline State

### 代码：760-789

```objc
_scenePipelineState = ...
_scenePBRPipelineState = ...
_sceneShadowPipelineState = ...
_sceneArgumentBufferPipelineState = ...
```

### 解释

这几段都是同一种模式：

- 修改 descriptor 的 fragment function
- 调用 `newRenderPipelineStateWithDescriptor`
- 检查是否成功

### 你要理解的重点
**一个 shader 变体通常对应一条单独的 pipeline。**

在这个项目中：

- 普通渲染用 `_scenePipelineState`
- PBR 用 `_scenePBRPipelineState`
- 阴影版用 `_sceneShadowPipelineState`
- AB 版用 `_sceneArgumentBufferPipelineState`

## K. 创建 Post Pipeline

### 代码：791-802

```objc
MTLRenderPipelineDescriptor *postPipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
postPipelineDescriptor.vertexFunction = postVertex;
postPipelineDescriptor.fragmentFunction = postFragment;
postPipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
postPipelineDescriptor.rasterSampleCount = kSampleCount;

_postPipelineState = [_device newRenderPipelineStateWithDescriptor:postPipelineDescriptor error:&error];
if (!_postPipelineState)
{
    NSLog(@"Failed to create post pipeline state: %@", error);
    return nil;
}
```

### 解释

#### 这是后处理 pass 的 pipeline
它不需要深度测试，因为是全屏三角形，不画 3D 几何遮挡关系。

#### 仍然使用 4x MSAA
说明 post pass 也会先写到 MSAA 纹理再 resolve。

## L. 创建 Compute Pipeline State

### 代码：804-821

```objc
_edgeComputePipelineState = [_device newComputePipelineStateWithFunction:edgeKernel error:&error];
...
_brightExtractPipelineState = ...
_blurPipelineState = ...
_particlePipelineState = ...
_downsamplePipelineState = ...
_upscalePipelineState = ...
```

### 解释

每个 compute kernel 都要变成一个 compute pipeline state，后面 compute encoder 才能执行。

#### 为什么 edge 单独判空
因为先创建 edge 的代码写成了单独一段。

#### 后面几个一起检查
逻辑一样：任何一个失败都说明后处理链不完整，初始化失败。

## M. 创建 Argument Buffer 相关对象

### 代码：823-830

```objc
_materialArgumentEncoder = [sceneFragmentArg newArgumentEncoderWithBufferIndex:2];
_materialArgumentBuffer = [_device newBufferWithLength:_materialArgumentEncoder.encodedLength
                                               options:MTLResourceStorageModeShared];
if (!_materialArgumentEncoder || !_materialArgumentBuffer)
{
    NSLog(@"Failed to create argument buffer resources.");
    return nil;
}
```

### 解释

#### `newArgumentEncoderWithBufferIndex:2`
从 shader 函数中获取对应 argument buffer 的编码器。  
这里的 `2` 必须和 shader 里 `[[buffer(2)]]` 对上。

#### `encodedLength`
argument buffer 实际需要多大内存，不靠猜，直接问 encoder。

#### `MTLResourceStorageModeShared`
因为 CPU 要往里面写资源句柄/绑定信息，所以用 shared。

## N. 创建 Depth State

### 代码：832-840

```objc
MTLDepthStencilDescriptor *depthDescriptor = [[MTLDepthStencilDescriptor alloc] init];
depthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
depthDescriptor.depthWriteEnabled = YES;
_depthState = [_device newDepthStencilStateWithDescriptor:depthDescriptor];
if (!_depthState)
{
    NSLog(@"Failed to create depth state.");
    return nil;
}
```

### 解释

#### `depthCompareFunction = Less`
新片元深度更小才通过。

#### `depthWriteEnabled = YES`
通过后要把自己的深度写进去。

#### `_depthState`
渲染 3D 物体时会绑定这个状态。

## O. 创建普通 Sampler

### 代码：842-852

```objc
MTLSamplerDescriptor *samplerDescriptor = [[MTLSamplerDescriptor alloc] init];
samplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
samplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
samplerDescriptor.sAddressMode = MTLSamplerAddressModeRepeat;
samplerDescriptor.tAddressMode = MTLSamplerAddressModeRepeat;
_samplerState = [_device newSamplerStateWithDescriptor:samplerDescriptor];
if (!_samplerState)
{
    NSLog(@"Failed to create sampler state.");
    return nil;
}
```

### 解释

#### `minFilter / magFilter = Linear`
缩小时、放大时都用线性过滤，画面更平滑。

#### `sAddressMode / tAddressMode = Repeat`
UV 超出 0~1 时重复平铺。

#### `_samplerState`
这是默认采样器。

## P. 创建各向异性 Sampler

### 代码：854-865

```objc
MTLSamplerDescriptor *anisoSamplerDescriptor = [[MTLSamplerDescriptor alloc] init];
anisoSamplerDescriptor.minFilter = MTLSamplerMinMagFilterLinear;
anisoSamplerDescriptor.magFilter = MTLSamplerMinMagFilterLinear;
anisoSamplerDescriptor.sAddressMode = MTLSamplerAddressModeRepeat;
anisoSamplerDescriptor.tAddressMode = MTLSamplerAddressModeRepeat;
anisoSamplerDescriptor.maxAnisotropy = 8;
_anisoSamplerState = [_device newSamplerStateWithDescriptor:anisoSamplerDescriptor];
if (!_anisoSamplerState)
{
    NSLog(@"Failed to create anisotropic sampler state.");
    return nil;
}
```

### 解释

和普通 sampler 基本一致，只多了：

#### `maxAnisotropy = 8`
开启更高质量的斜角纹理采样。  
这是主题 11 的重点之一。

## Q. 创建 Shared Event / Ray Tracing 能力检测

### 代码：867-872

```objc
if ([_device respondsToSelector:@selector(newSharedEvent)])
{
    _sharedEvent = [_device newSharedEvent];
}

_supportsRayTracing = [_device supportsRaytracing];
```

### 解释

#### `newSharedEvent`
如果设备支持，就创建 shared event。  
主要用于同步/调度演示。

#### `supportsRaytracing`
查询是否支持光追相关能力。  
注意这里只是**能力探测**，不等于这个项目真的完整启用了硬件光追管线。

## R. 创建 Indirect Command Buffer

### 代码：874-886

```objc
MTLIndirectCommandBufferDescriptor *icbDescriptor = [[MTLIndirectCommandBufferDescriptor alloc] init];
icbDescriptor.commandTypes = MTLIndirectCommandTypeDrawIndexed;
icbDescriptor.inheritPipelineState = YES;
icbDescriptor.inheritBuffers = YES;
icbDescriptor.maxVertexBufferBindCount = 0;
icbDescriptor.maxFragmentBufferBindCount = 0;
_indirectCommandBuffer = [_device newIndirectCommandBufferWithDescriptor:icbDescriptor
                               maxCommandCount:3
                                       options:0];
if (!_indirectCommandBuffer)
{
    NSLog(@"Indirect command buffer unavailable, topic 4 will fall back to direct draw.");
}
```

### 解释

#### `MTLIndirectCommandTypeDrawIndexed`
这个 ICB 里记录的是 indexed draw 命令。

#### `inheritPipelineState = YES`
执行这些间接命令时，pipeline state 从外部 encoder 继承。

#### `inheritBuffers = YES`
buffer 绑定也从外部继承。

#### `maxVertexBufferBindCount = 0`
#### `maxFragmentBufferBindCount = 0`
因为这里选择继承 buffer，所以 ICB 自己不额外记录 buffer 绑定数。

#### `maxCommandCount:3`
这个 ICB 最多装 3 条命令。

#### 失败只记录日志
同样是 fallback 思路。

## S. 定义立方体顶点和索引数据

### 代码：888-927

这里是一大块顶点数组和索引数组。

### 解释重点

#### `cubeVertices`
定义了 24 个顶点，而不是 8 个角点。

为什么？因为立方体每个面有不同的：

- normal
- uv

所以不同面的同一个空间位置顶点，不能简单复用同一份顶点属性。

#### 每个顶点结构
来自文件顶部的 `Vertex`：

- `position`
- `normal`
- `color`
- `uv`

#### `cubeIndices`
每个面两个三角形，共 6 个面：

- 6 faces
- 每 face 2 triangles
- 每 triangle 3 indices
- 总共 36 个索引

## T. 创建 staging buffer 和 GPU 私有 buffer

### 代码：929-947

```objc
id<MTLBuffer> vertexStaging = [_device newBufferWithBytes:cubeVertices
                                                    length:sizeof(cubeVertices)
                                                   options:MTLResourceStorageModeShared];
id<MTLBuffer> indexStaging  = [_device newBufferWithBytes:cubeIndices
                                                   length:sizeof(cubeIndices)
                                                  options:MTLResourceStorageModeShared];
_vertexBuffer = [_device newBufferWithLength:sizeof(cubeVertices)
                                      options:MTLResourceStorageModePrivate];
_indexBuffer  = [_device newBufferWithLength:sizeof(cubeIndices)
                                      options:MTLResourceStorageModePrivate];
_instanceBuffer = [_device newBufferWithLength:sizeof(InstanceData) * 3
                                       options:MTLResourceStorageModeShared];
_indexCount = sizeof(cubeIndices) / sizeof(cubeIndices[0]);
if (!vertexStaging || !indexStaging || !_vertexBuffer || !_indexBuffer || !_instanceBuffer)
{
    NSLog(@"Failed to create mesh buffers.");
    return nil;
}
```

### 解释

#### `vertexStaging / indexStaging`
CPU 先把数据放到 shared staging buffer 里。  
因为 CPU 可以直接访问 shared。

#### `_vertexBuffer / _indexBuffer = Private`
真正渲染时要读的几何数据放 GPU 私有内存里，更适合 GPU 高速访问。

#### `_instanceBuffer = Shared`
实例变换每帧会更新，所以用 shared，CPU 直接写方便。

#### `_indexCount`
保存索引数量，后面 draw call 要用。

## U. 预录制 ICB 命令

### 代码：949-963

```objc
if (_indirectCommandBuffer)
{
    for (NSUInteger commandIndex = 0; commandIndex < 3; ++commandIndex)
    {
        id<MTLIndirectRenderCommand> prebuiltICBCommand = [_indirectCommandBuffer indirectRenderCommandAtIndex:commandIndex];
        [prebuiltICBCommand drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                         indexCount:_indexCount
                                          indexType:MTLIndexTypeUInt16
                                        indexBuffer:_indexBuffer
                                  indexBufferOffset:0
                                      instanceCount:1
                                         baseVertex:0
                                       baseInstance:commandIndex];
    }
}
```

### 解释

#### `if (_indirectCommandBuffer)`
只有 ICB 成功创建了，才去录命令。

#### `for commandIndex = 0..2`
预录制 3 条命令。

#### `indirectRenderCommandAtIndex:commandIndex`
取出 ICB 中第 `commandIndex` 条命令槽位。

#### `drawIndexedPrimitives`
把 drawIndexed 命令写进去。  
这里特别重要的是：

#### `instanceCount:1`
每条命令画 1 个实例。

#### `baseInstance:commandIndex`
这让 vertex shader 能通过实例 ID 区分“第几个物体”，进而从 `_instanceBuffer` 里读取不同的 model matrix / tint。

也就是说：

- 同一个立方体 mesh
- 用 3 条间接命令
- 画成 3 个对象

## V. 创建 3 份 uniform buffer

### 代码：965-974

```objc
for (NSUInteger i = 0; i < kMaxFramesInFlight; ++i)
{
    _uniformBuffers[i] = [_device newBufferWithLength:sizeof(Uniforms)
                                               options:MTLResourceStorageModeShared];
    if (!_uniformBuffers[i])
    {
        NSLog(@"Failed to create uniform buffer %lu.", (unsigned long)i);
        return nil;
    }
}
```

### 解释

#### 为什么是 3 份
因为 `kMaxFramesInFlight = 3`。  
每一帧轮流使用一份，避免 CPU 和 GPU 同时读写同一个 uniform buffer。

#### 为什么是 Shared
因为 CPU 每帧都要更新里面的矩阵和参数。

## W. 创建程序生成的材质纹理

### 代码：976-982

```objc
_albedoTexture = [self createAlbedoTexture];
_normalTexture = [self createNormalTexture];
if (!_albedoTexture || !_normalTexture)
{
    NSLog(@"Failed to create material textures.");
    return nil;
}
```

### 解释

这两个函数前面已经定义好了，会生成：

- 一个颜色纹理
- 一个法线纹理

这样这个 Demo 不依赖外部图片资源也能跑。

## X. 把纹理写入 Argument Buffer

### 代码：984-986

```objc
[_materialArgumentEncoder setArgumentBuffer:_materialArgumentBuffer offset:0];
[_materialArgumentEncoder setTexture:_albedoTexture atIndex:0];
[_materialArgumentEncoder setTexture:_normalTexture atIndex:1];
```

### 解释

#### `setArgumentBuffer`
先告诉 encoder：我要往哪块 buffer 里编码 argument buffer 内容。

#### `setTexture ... atIndex:0`
把 albedo 纹理写到 argument buffer 的 slot 0。

#### `setTexture ... atIndex:1`
把 normal 纹理写到 slot 1。

这就和 shader 中的：

```metal
struct MaterialArguments
{
    texture2d<float> albedo [[id(0)]];
    texture2d<float> normal [[id(1)]];
};
```

一一对应上了。

## Y. 用 blit 上传静态几何并生成 mipmap

### 代码：988-1001

```objc
id<MTLCommandBuffer> setupCommandBuffer = [_commandQueue commandBuffer];
id<MTLBlitCommandEncoder> setupBlit = [setupCommandBuffer blitCommandEncoder];
// Upload static geometry to Private GPU memory.
[setupBlit copyFromBuffer:vertexStaging sourceOffset:0
                toBuffer:_vertexBuffer destinationOffset:0
                    size:sizeof(cubeVertices)];
[setupBlit copyFromBuffer:indexStaging sourceOffset:0
                toBuffer:_indexBuffer  destinationOffset:0
                    size:sizeof(cubeIndices)];
[setupBlit generateMipmapsForTexture:_albedoTexture];
[setupBlit generateMipmapsForTexture:_normalTexture];
[setupBlit endEncoding];
[setupCommandBuffer commit];
[setupCommandBuffer waitUntilCompleted];
```

### 解释

#### `setupCommandBuffer`
初始化阶段专门开一个 command buffer。

#### `blitCommandEncoder`
这个 encoder 用来做“资源搬运”。

#### `copyFromBuffer -> toBuffer`
把 staging buffer 数据拷贝到 private GPU buffer 里。

#### `generateMipmapsForTexture`
自动生成所有 mip 层。

#### `endEncoding`
结束 blit 编码。

#### `commit`
提交给 GPU 执行。

#### `waitUntilCompleted`
这里初始化阶段必须等它做完。  
因为后面立刻就要用这些资源了。

## Z. 初始化最后的状态

### 代码：1003-1007

```objc
_historyValid = NO;
_metricsLock = OS_UNFAIR_LOCK_INIT;
}
return self;
}
```

### 解释

#### `_historyValid = NO`
历史帧纹理还没有有效内容，后面 temporal blending 时会判断。

#### `_metricsLock = OS_UNFAIR_LOCK_INIT`
初始化一个轻量锁，用于保护 HUD 统计数据。

#### `return self`
初始化成功，返回这个 `Renderer` 对象。

# 第三部分：逐行讲解 `render()`

文件：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm`

方法起始：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/src/Renderer.mm:1010`

这个方法是全项目最核心的一段代码。  
你可以把它当成：

> **“这一帧 GPU 到底干了什么”**

## A. 方法入口与帧级别生命周期

### 代码：1010-1015

```objc
- (void)render
{
    @autoreleasepool
    {
        CFAbsoluteTime cpuFrameStart = CFAbsoluteTimeGetCurrent();
        dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);
```

### 解释

#### `- (void)render`
每帧都会被调用一次。

#### `@autoreleasepool`
防止每帧产生的 autorelease 对象堆积太久。

#### `cpuFrameStart`
记录 CPU 这一帧开始时间，用来算 CPU 帧时。

#### `dispatch_semaphore_wait`
等待一个 in-flight slot。  
如果前面已经有 3 帧还没完成，CPU 会在这里等。

这一步非常重要，用来保证：

- 不会无限提交帧
- 不会过早重用 uniform buffer

## B. 可选的单帧 GPU Capture

### 代码：1017-1035

```objc
BOOL capturing = NO;
if (_captureNextFrame)
{
    _captureNextFrame = NO;
    MTLCaptureManager *mgr = [MTLCaptureManager sharedCaptureManager];
    MTLCaptureDescriptor *desc = [[MTLCaptureDescriptor alloc] init];
    desc.captureObject = _device;
    desc.destination   = MTLCaptureDestinationGPUTraceDocument;
    NSString *path     = [NSTemporaryDirectory()
                          stringByAppendingPathComponent:@"MetalDemo_frame.gputrace"];
    desc.outputURL = [NSURL fileURLWithPath:path];
    NSError *captureErr = nil;
    capturing = [mgr startCaptureWithDescriptor:desc error:&captureErr];
    if (capturing)
        NSLog(@"[Capture] GPU trace started → %@", path);
    else
        NSLog(@"[Capture] Failed: %@", captureErr.localizedDescription);
}
```

### 解释

#### `capturing = NO`
默认这帧不抓取。

#### `if (_captureNextFrame)`
如果用户之前按了 `C`，就抓当前这一帧。

#### `_captureNextFrame = NO`
消费掉这次请求，避免连续抓很多帧。

#### `MTLCaptureManager`
Metal 提供的 GPU Capture 管理器。

#### `desc.captureObject = _device`
抓取对象是整个 device 相关的 GPU 活动。

#### `destination = GPUTraceDocument`
输出为 `.gputrace` 文档，便于用 Xcode 分析。

#### `outputURL`
输出路径在临时目录。

#### `startCaptureWithDescriptor`
开始抓取。

这段代码体现了：  
这个 Demo 不只是“能画”，还支持性能分析教学。

## C. 资源错误示例：强制触发 render target 重建

### 代码：1037-1040

```objc
if (_errorExampleEnabled && _demoTopic == MetalDemoTopicResourceMemory)
{
    _sceneResolveTexture = nil;
}
```

### 解释

这是一种“故意制造错误”的演示方式。

#### 为什么设 `nil`
因为后面 `ensureRenderTargetsForDrawable:` 会检查 `_sceneResolveTexture` 是否存在。  
把它清掉，就会强制重建中间纹理。

#### 教学目的
让你观察“错误的资源管理策略”会带来什么问题：

- 不必要的重建
- 额外 CPU/GPU 开销
- 潜在卡顿

## D. 拿当前帧 drawable

### 代码：1042-1047

```objc
id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
if (!drawable)
{
    dispatch_semaphore_signal(_inFlightSemaphore);
    return;
}
```

### 解释

#### `nextDrawable`
从 `CAMetalLayer` 取当前帧可显示的目标。

#### 如果拿不到
说明当前时机没有可用 drawable。  
那这帧就不能继续干活了，所以：

- 释放 semaphore
- 直接返回

## E. 确保 render targets 已就绪

### 代码：1049-1054

```objc
[self ensureRenderTargetsForDrawable:drawable];
if (!_sceneMSAATexture || !_sceneResolveTexture || !_sceneDepthTexture || !_edgeTexture || !_postMSAATexture)
{
    dispatch_semaphore_signal(_inFlightSemaphore);
    return;
}
```

### 解释

#### `ensureRenderTargetsForDrawable:`
根据当前 drawable 尺寸，确保所有中间纹理都存在且尺寸匹配。

#### 判空
如果 scene / depth / edge / post 所需关键纹理没有建出来，那这一帧没法渲染，只能退出。

## F. 创建本帧 command buffer

### 代码：1056-1061

```objc
id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
if (!commandBuffer)
{
    dispatch_semaphore_signal(_inFlightSemaphore);
    return;
}
```

### 解释

每一帧都从命令队列里新建一个 command buffer。

如果这一步失败，本帧就没法向 GPU 发任何工作。

## G. 注册 command buffer 完成回调

### 代码：1063-1077

```objc
__block dispatch_semaphore_t semaphore = _inFlightSemaphore;
__block BOOL wasCapturing = capturing;
[commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull buffer) {
    if (wasCapturing)
        [[MTLCaptureManager sharedCaptureManager] stopCapture];
    double gpuFrameMs = -1.0;
    if (buffer.GPUEndTime > buffer.GPUStartTime)
    {
        gpuFrameMs = (buffer.GPUEndTime - buffer.GPUStartTime) * 1000.0;
    }
    os_unfair_lock_lock(&self->_metricsLock);
    self->_lastGPUFrameTimeMs = gpuFrameMs;
    os_unfair_lock_unlock(&self->_metricsLock);
    dispatch_semaphore_signal(semaphore);
}];
```

### 解释

#### `addCompletedHandler`
当 GPU 真正把这帧执行完时，会回调这里。

#### `if (wasCapturing) stopCapture`
如果这帧启动了 GPU Capture，这里结束抓取。

#### `buffer.GPUEndTime - buffer.GPUStartTime`
计算 GPU 实际执行这帧命令花了多少时间。

#### `os_unfair_lock`
加锁写 `_lastGPUFrameTimeMs`，防止 HUD 线程/主线程读取时竞争。

#### `dispatch_semaphore_signal`
这一步极关键。  
它表示：

> GPU 已经真正完成一帧，释放一个 in-flight slot

如果没有这句，你的 semaphore 会永远卡死。

## H. 选择当前帧的 uniform buffer 槽位

### 代码：1079-1080

```objc
NSUInteger uniformIndex = _frameIndex % kMaxFramesInFlight;
_frameIndex++;
```

### 解释

3 份 uniform buffer 轮流用：

- 第 0 帧用 0
- 第 1 帧用 1
- 第 2 帧用 2
- 第 3 帧再回到 0

这就是 ring buffer。

## I. 初始化这帧的默认参数

### 代码：1082-1090

```objc
float elapsed = (float)(CFAbsoluteTimeGetCurrent() - _startTime);
float timeScale = 1.0f;
float edgeStrength = 0.9f;
float sceneMix = 1.0f;
float exposureBias = 1.0f;
float bloomStrength = 0.0f;
float particleStrength = 0.0f;
float temporalBlend = 0.0f;
MTLClearColor sceneClear = MTLClearColorMake(0.04, 0.05, 0.08, 1.0);
```

### 解释

#### `elapsed`
程序运行了多少秒。  
动画、旋转、粒子都依赖它。

#### 其余参数
这些都是本帧的“视觉参数默认值”：

- `timeScale`：动画速度倍率
- `edgeStrength`：边缘特效强度
- `sceneMix`：场景混合权重
- `exposureBias`：曝光
- `bloomStrength`：bloom 强度
- `particleStrength`：粒子层强度
- `temporalBlend`：时域混合权重
- `sceneClear`：场景 pass 的清屏颜色

## J. 根据主题决定本帧启用哪些路径

### 代码：1092-1110

```objc
BOOL useArgumentBuffer = (_demoTopic == MetalDemoTopicArgumentBuffer);
// Keep argument buffer resources bound for learning, but use shader fallback for stability.
BOOL useArgumentShader = (_demoTopic == MetalDemoTopicArgumentBuffer);
// Topic 4 uses real ICB only when both the ICB pipeline and ICB buffer are available.
BOOL useICB = (_demoTopic == MetalDemoTopicIndirectCommandBuffer) &&
          (_sceneICBPipelineState != nil) &&
          (_indirectCommandBuffer != nil);
BOOL useParallel = (_demoTopic == MetalDemoTopicParallelEncoding);
BOOL useDeferredLike = (_demoTopic == MetalDemoTopicDeferredLike);
BOOL useShadow = (_demoTopic == MetalDemoTopicShadowing);
BOOL usePBR = (_demoTopic == MetalDemoTopicPBR);
BOOL useBloom = (_demoTopic == MetalDemoTopicHDRBloomTAA);
BOOL useParticles = (_demoTopic == MetalDemoTopicComputeParticles);
BOOL useAnisoSampler = (_demoTopic == MetalDemoTopicTextureAdvanced);
BOOL useSyncScheduling = (_demoTopic == MetalDemoTopicSyncAndScheduling);
BOOL useRayTraceMode = (_demoTopic == MetalDemoTopicRayTracing);
BOOL useUpscale = (_demoTopic == MetalDemoTopicMetalFXLike);
BOOL useProfiling = (_demoTopic == MetalDemoTopicProfiling);
uint32_t extraStressPasses = 0;
```

### 解释

#### 这一段本质上是在做“渲染路径路由”
根据当前主题，把一堆布尔开关打开或关闭。

#### `useArgumentBuffer`
表示当前是 AB 教学主题。

#### `useArgumentShader`
代码注释里明确说了：  
保留 argument buffer 路径做教学，但走更稳定的 shader 方案。

#### `useICB`
非常重要，这里不是只看主题是不是 4，  
还要看：

- ICB pipeline 创建成功没
- ICB buffer 创建成功没

也就是说：**主题 4 想走 ICB，但不保证一定能走到**。

#### `extraStressPasses`
这是错误示例/压力测试的额外 compute 次数。

## K. 主题 3：Function Constants 特殊逻辑

### 代码：1112-1117

```objc
if (_demoTopic == MetalDemoTopicFunctionConstants)
{
    usePBR = fmodf(elapsed, 4.0f) > 2.0f;
    useShadow = !usePBR;
    edgeStrength = 0.25f;
}
```

### 解释

#### `fmodf(elapsed, 4.0f) > 2.0f`
每 4 秒为一个周期，前后两半切换不同 shader 变体。

- 前半段：shadow
- 后半段：PBR

#### 教学目的
让你肉眼看到“同一份 shader 源码生成的不同 pipeline 变体”在运行时切换。

## L. 每个主题的默认视觉参数

### 代码：1119-1180

这是一整个 `switch (_demoTopic)`。

### 解释思路
每个 case 都是给当前主题设置更符合教学目标的参数。

举几个关键例子：

#### 主题 4 ICB
```objc
timeScale = 1.25f;
sceneClear = ...
```
让旋转更明显、配色更有区分度。

#### 主题 6 DeferredLike
```objc
edgeStrength = 1.2f;
sceneMix = 0.9f;
```
强调边缘和后处理合成效果。

#### 主题 8 PBR
```objc
exposureBias = 1.25f;
```
让 PBR 高光更容易看清。

#### 主题 9 HDRBloomTAA
```objc
bloomStrength = 0.08f;
temporalBlend = 0.0f;
```
默认突出 bloom，但 temporal 先关闭。

#### 主题 14 MetalFXLike
```objc
sceneMix = 0.82f;
exposureBias = 1.3f;
temporalBlend = _historyValid ? 0.6f : 0.0f;
```
如果有历史帧，就开启时域混合。

## M. 错误示例模式：故意把参数调坏

### 代码：1182-1240

这又是一个 `switch (_demoTopic)`，但只在 `_errorExampleEnabled` 时进入。

### 解释

它本质上做的是：

> “让当前主题出现典型错误行为”

比如：

#### 主题 2
```objc
sceneMix = 1.25f;
edgeStrength = 1.8f;
```
可能导致过曝/边缘过重。

#### 主题 9
```objc
bloomStrength = 0.7f;
temporalBlend = _historyValid ? 0.92f : 0.0f;
```
典型错误：
- bloom 太亮
- temporal 拖影严重

#### 主题 15
```objc
extraStressPasses = 4;
```
让 profiling 时更容易观察热点。

## N. 乘上用户调节倍率

### 代码：1242-1244

```objc
timeScale = fmaxf(0.1f, timeScale * _userTimeScaleGain);
edgeStrength = fmaxf(0.0f, edgeStrength * _userEdgeGain);
exposureBias = fmaxf(0.1f, exposureBias * _userExposureGain);
```

### 解释

HUD 面板允许用户再对这些参数做二次调整。

#### `fmaxf`
用于防止参数被调成无意义值，比如负曝光、负时间倍率。

## O. 更新 HUD 显示的当前路径摘要

### 代码：1246-1330

这一大段代码就是在设置：

- `_lastScenePathSummary`
- `_lastPostPathSummary`
- `_lastUpscalePathSummary`
- `_lastRuntimeFallbackSummary`

### 解释重点

#### 主题 4 ICB
分三种情况：

1. 真正走 ICB
2. ICB pipeline 不支持 -> fallback
3. ICB buffer 不可用 -> fallback

#### 主题 14 Upscale
分两种情况：

1. `_spatialScaler != nil` -> MetalFX
2. 否则 -> Compute Bilinear fallback

#### 作用
让 HUD 展示“真实执行路径”，而不是只展示“用户选择的主题名”。

这是非常好的教学设计。

## P. 写入 uniform 数据

### 代码：1332-1353

```objc
elapsed *= timeScale;
Uniforms *uniforms = (Uniforms *)_uniformBuffers[uniformIndex].contents;

float aspect = (float)_sceneResolveTexture.width / (float)MAX((NSUInteger)1, _sceneResolveTexture.height);
matrix_float4x4 projection = matrix_perspective(65.0f * ((float)M_PI / 180.0f), aspect, 0.1f, 100.0f);
matrix_float4x4 view = matrix_translation(0.0f, 0.0f, -5.2f);
matrix_float4x4 viewProjection = matrix_multiply(projection, view);
matrix_float4x4 rotationY = matrix_rotation(elapsed * 0.8f, (vector_float3){0.0f, 1.0f, 0.0f});
matrix_float4x4 rotationX = matrix_rotation(elapsed * 0.5f, (vector_float3){1.0f, 0.0f, 0.0f});
matrix_float4x4 model = matrix_multiply(rotationY, rotationX);
matrix_float4x4 mv = matrix_multiply(view, model);

uniforms->viewProjectionMatrix = viewProjection;
uniforms->modelViewProjectionMatrix = matrix_multiply(projection, mv);
uniforms->modelMatrix = model;
uniforms->lightDirection = simd_normalize((vector_float3){0.5f, 0.8f, 0.4f});
uniforms->time = elapsed;
uniforms->exposure = exposureBias;
uniforms->bloomStrength = bloomStrength;
uniforms->demoTopic = (uint32_t)_demoTopic;
uniforms->featureFlags = (useBloom ? 1u : 0u) | (useParticles ? 2u : 0u) |
                         (useRayTraceMode ? 4u : 0u) | (useUpscale ? 8u : 0u);
```

### 解释

#### `elapsed *= timeScale`
动画时间乘上时间倍率。

#### `uniforms = ...contents`
拿到当前帧这份 uniform buffer 的 CPU 可写指针。

#### `aspect`
屏幕纵横比，用于透视投影。

#### `projection`
透视投影矩阵。

#### `view`
视图矩阵，这里相机往后退了 5.2。

#### `viewProjection`
提前把投影和视图乘起来。

#### `rotationY / rotationX`
让模型绕 Y 和 X 轴转动。

#### `model`
模型变换矩阵。

#### `mv`
model-view 矩阵。

#### 写入 uniforms 各字段
后面 vertex / fragment shader 都会读这些参数。

特别是：

- `viewProjectionMatrix`：ICB/实例路径使用
- `modelViewProjectionMatrix`：普通路径使用
- `modelMatrix`：算世界空间法线/位置
- `time`：动画与 pulse
- `demoTopic`：shader 内部可根据主题做特殊处理
- `featureFlags`：把一些开关打包成 bit flags

## Q. 更新 instance buffer：给 3 个对象不同变换和颜色

### 代码：1355-1377

```objc
if (_instanceBuffer)
{
    InstanceData *instances = (InstanceData *)_instanceBuffer.contents;
    simd_float3 tints[3] = {
        {1.00f, 0.72f, 0.72f},
        {0.72f, 1.00f, 0.80f},
        {0.74f, 0.84f, 1.00f}
    };
    float xOffsets[3] = {-2.35f, 0.0f, 2.35f};
    float phaseOffsets[3] = {0.0f, 1.4f, 2.8f};
    for (NSUInteger i = 0; i < 3; ++i)
    {
        matrix_float4x4 localRotY = ...
        matrix_float4x4 localRotX = ...
        matrix_float4x4 localModel = ...
        instances[i].modelMatrix = localModel;
        instances[i].tint = tints[i];
        instances[i].pad = 0.0f;
    }
}
```

### 解释

#### `_instanceBuffer.contents`
拿到实例数据的 CPU 写指针。

#### `tints`
3 个不同颜色。

#### `xOffsets`
3 个物体分别放在左、中、右。

#### `phaseOffsets`
让它们旋转不同步，看起来更丰富。

#### 每个实例写入：
- 自己的 model matrix
- 自己的 tint

这样主题 4 的 ICB 或实例逻辑就能渲染成多个对象，而不是一个。

## R. 选择本帧 Scene Pipeline 和 Sampler

### 代码：1379-1397

```objc
id<MTLRenderPipelineState> selectedScenePipeline = _scenePipelineState;
if (useICB)
{
    selectedScenePipeline = _sceneICBPipelineState;
}
else if (useArgumentShader)
{
    selectedScenePipeline = _sceneArgumentBufferPipelineState;
}
else if (usePBR)
{
    selectedScenePipeline = _scenePBRPipelineState;
}
else if (useShadow)
{
    selectedScenePipeline = _sceneShadowPipelineState;
}

id<MTLSamplerState> sceneSampler = useAnisoSampler ? _anisoSamplerState : _samplerState;
```

### 解释

#### `selectedScenePipeline`
默认是普通 scene pipeline。

#### 按优先级切换
- ICB
- Argument Buffer
- PBR
- Shadow

#### `sceneSampler`
主题 11 时改用各向异性采样器，否则用普通采样器。

## S. 配置 Scene Render Pass

### 代码：1399-1408

```objc
MTLRenderPassDescriptor *scenePass = [MTLRenderPassDescriptor renderPassDescriptor];
scenePass.colorAttachments[0].texture = _sceneMSAATexture;
scenePass.colorAttachments[0].resolveTexture = _sceneResolveTexture;
scenePass.colorAttachments[0].loadAction = MTLLoadActionClear;
scenePass.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
scenePass.colorAttachments[0].clearColor = sceneClear;
scenePass.depthAttachment.texture = _sceneDepthTexture;
scenePass.depthAttachment.loadAction = MTLLoadActionClear;
scenePass.depthAttachment.storeAction = MTLStoreActionDontCare;
scenePass.depthAttachment.clearDepth = 1.0;
```

### 解释

#### `scenePass`
创建场景渲染 pass 描述。

#### `colorAttachments[0].texture = _sceneMSAATexture`
真正 rasterize 时先写进多采样颜色纹理。

#### `resolveTexture = _sceneResolveTexture`
pass 结束时 resolve 到单采样纹理，后面 compute / post 要读它。

#### `loadAction = Clear`
这一帧开始时先清空颜色缓冲。

#### `storeAction = MultisampleResolve`
结束时执行 resolve。

#### `clearColor = sceneClear`
清屏颜色由当前主题决定。

#### `depthAttachment.texture = _sceneDepthTexture`
深度缓冲也附上。

#### `depthAttachment.loadAction = Clear`
每帧深度从 1.0 开始清空。

#### `storeAction = DontCare`
scene pass 之后不会再读深度，所以不需要保存深度内容。

## T. 主题 5：Parallel Render Encoding

### 代码：1410-1495

这是 parallel encoder 的整段逻辑。

### 解释主线

#### `parallelRenderCommandEncoderWithDescriptor:scenePass`
创建并行渲染编码器。

#### `enc1 / enc2`
从 parallel encoder 中拿两个子 render encoder。

#### `halfCount / halfOffset`
把立方体索引拆成两半：

- 前半交给 enc1
- 后半交给 enc2

#### `dispatch_group_async`
两个 GCD 任务并行编码。

#### 每个 encoder 都做同样的事情
- 设 pipeline
- 设 depth state
- 设 cull mode
- 绑 vertex buffer
- 绑 uniform buffer
- 绑 instance buffer
- 绑 fragment buffer
- 绑纹理
- draw 一半索引

#### `dispatch_group_wait`
等两个编码任务都完成。

#### `[parallelEncoder endEncoding]`
结束整个 parallel pass。

### 初学者理解重点
这不是 GPU 并行画两个 pass，  
而是 **CPU 端并行录制命令**。

## U. 普通 Scene Pass 路径

### 代码：1496-1555

如果不是 parallel，就走普通 render encoder。

### U1. 创建 scene encoder

```objc
id<MTLRenderCommandEncoder> sceneEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:scenePass];
if (!sceneEncoder)
{
    dispatch_semaphore_signal(_inFlightSemaphore);
    return;
}
```

解释：

- 从 command buffer 创建 render encoder
- 如果失败，本帧无法继续

### U2. Profiling Debug Group

```objc
if (useProfiling)
{
    [sceneEncoder pushDebugGroup:@"ScenePass"];
}
```

解释：

给 GPU Capture / profiler 打一个标签，便于后面在工具里看见“这是 ScenePass”。

### U3. 设置固定状态

```objc
[sceneEncoder setRenderPipelineState:selectedScenePipeline];
[sceneEncoder setDepthStencilState:_depthState];
[sceneEncoder setCullMode:MTLCullModeBack];
[sceneEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
```

解释：

- 设置当前渲染管线
- 设置深度状态
- 开启背面剔除
- 设定逆时针为正面

### U4. ICB 分支

```objc
if (useICB)
{
    [sceneEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    [sceneEncoder setVertexBuffer:_uniformBuffers[uniformIndex] offset:0 atIndex:1];
    [sceneEncoder setVertexBuffer:_instanceBuffer offset:0 atIndex:2];
    [sceneEncoder useResource:_indexBuffer usage:MTLResourceUsageRead stages:MTLRenderStageVertex];
    [sceneEncoder executeCommandsInBuffer:_indirectCommandBuffer withRange:NSMakeRange(0, 3)];
}
```

解释：

#### 设置 vertex buffers
因为 ICB 命令继承 buffer 绑定，所以外部 encoder 还是要先把这些 buffer 绑好。

#### `useResource:_indexBuffer`
告诉 Metal：这个 render pass 会读取 `_indexBuffer`。  
因为 ICB 内部会使用它，显式声明有助于资源 hazard 跟踪。

#### `executeCommandsInBuffer`
执行 ICB 中预录制的 3 条命令。

### U5. 普通 direct draw 分支

```objc
else
{
    [sceneEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
    [sceneEncoder setVertexBuffer:_uniformBuffers[uniformIndex] offset:0 atIndex:1];
    [sceneEncoder setVertexBuffer:_instanceBuffer offset:0 atIndex:2];
    [sceneEncoder setFragmentBuffer:_uniformBuffers[uniformIndex] offset:0 atIndex:1];
    [sceneEncoder setFragmentBuffer:_materialArgumentBuffer offset:0 atIndex:2];
    [sceneEncoder setFragmentSamplerState:sceneSampler atIndex:0];
    if (useArgumentShader)
    {
        [sceneEncoder useResource:_albedoTexture usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
        [sceneEncoder useResource:_normalTexture usage:MTLResourceUsageRead stages:MTLRenderStageFragment];
    }
    else
    {
        [sceneEncoder setFragmentTexture:_albedoTexture atIndex:0];
        [sceneEncoder setFragmentTexture:_normalTexture atIndex:1];
    }
    [sceneEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                              indexCount:_indexCount
                               indexType:MTLIndexTypeUInt16
                             indexBuffer:_indexBuffer
                       indexBufferOffset:0];
}
```

### 解释

#### vertex buffer 绑定
- `atIndex:0`：顶点数组
- `atIndex:1`：uniform
- `atIndex:2`：instance 数据

这和 shader 中的 `[[buffer(n)]]` 对应。

#### fragment buffer 绑定
- uniform 给 fragment 用
- argument buffer 给 fragment 用

#### `setFragmentSamplerState`
纹理采样器绑定到 slot 0。

#### `if (useArgumentShader)`
如果走 argument buffer 主题，这里不直接 `setFragmentTexture`，而是用 `useResource` 告诉 Metal 资源会被 shader 读取。

#### `else`
普通路径下，直接把 albedo 和 normal 纹理绑定到 fragment texture slot 0 和 1。

#### `drawIndexedPrimitives`
发起 indexed draw call，真正开始画立方体。

### U6. 结束 Profiling Group 和 Scene Encoder

```objc
if (useProfiling)
{
    [sceneEncoder popDebugGroup];
}

[sceneEncoder endEncoding];
```

解释：

- profiling 标签结束
- render encoder 编码结束

## V. Deferred-like 路径的额外 Edge Compute

### 代码：1557-1569

```objc
if (useDeferredLike)
{
    id<MTLComputeCommandEncoder> deferredEncoder = [commandBuffer computeCommandEncoder];
    [deferredEncoder setComputePipelineState:_edgeComputePipelineState];
    [deferredEncoder setTexture:_sceneResolveTexture atIndex:0];
    [deferredEncoder setTexture:_edgeTexture atIndex:1];

    MTLSize gridDeferred = MTLSizeMake(_edgeTexture.width, _edgeTexture.height, 1);
    NSUInteger wDeferred = _edgeComputePipelineState.threadExecutionWidth;
    NSUInteger hDeferred = MAX((NSUInteger)1, _edgeComputePipelineState.maxTotalThreadsPerThreadgroup / wDeferred);
    [deferredEncoder dispatchThreads:gridDeferred threadsPerThreadgroup:MTLSizeMake(wDeferred, hDeferred, 1)];
    [deferredEncoder endEncoding];
}
```

### 解释

#### 这是主题 6 的“多阶段中间结果”演示
scene pass 完了之后，立刻对场景结果做一次 edge compute。

#### `setTexture source/dest`
输入是 `_sceneResolveTexture`，输出是 `_edgeTexture`。

#### `threadExecutionWidth`
这个值来自 compute pipeline，表示硬件友好的线程宽度。

#### `dispatchThreads`
对整个 `_edgeTexture` 网格发起线程。

## W. 通用 Edge Compute Pass

### 代码：1571-1600

```objc
id<MTLComputeCommandEncoder> computeEncoder = [commandBuffer computeCommandEncoder];
if (!computeEncoder)
{
    dispatch_semaphore_signal(_inFlightSemaphore);
    return;
}

[computeEncoder setComputePipelineState:_edgeComputePipelineState];
[computeEncoder setTexture:_sceneResolveTexture atIndex:0];
[computeEncoder setTexture:_edgeTexture atIndex:1];

MTLSize grid = MTLSizeMake(_edgeTexture.width, _edgeTexture.height, 1);
NSUInteger tgWidth = _edgeComputePipelineState.threadExecutionWidth;
NSUInteger tgHeight = _edgeComputePipelineState.maxTotalThreadsPerThreadgroup / tgWidth;
if (tgHeight == 0)
{
    tgHeight = 1;
}
MTLSize tgSize = MTLSizeMake(tgWidth, tgHeight, 1);
if (!useDeferredLike)
{
    [computeEncoder dispatchThreads:grid threadsPerThreadgroup:tgSize];
    for (uint32_t i = 0; i < extraStressPasses; ++i)
    {
        [computeEncoder dispatchThreads:grid threadsPerThreadgroup:tgSize];
    }
}
[computeEncoder endEncoding];
```

### 解释

#### 创建 compute encoder
这是本帧的通用 compute pass 入口。

#### 设置 edge pipeline 和输入输出纹理
和上面的 deferredEncoder 一样。

#### `grid`
整个输出纹理覆盖范围。

#### `tgWidth / tgHeight`
动态计算 threadgroup 大小，尽量和硬件友好。

#### `if (!useDeferredLike)`
如果主题 6 已经单独跑过 edge detect，这里就不重复跑。

#### `extraStressPasses`
错误示例模式下，会额外多 dispatch 几次，故意制造 GPU 压力。

## X. `dispatch2D` 小工具 block

### 代码：1601-1610

```objc
auto dispatch2D = ^(id<MTLComputeCommandEncoder> encoder,
                    id<MTLComputePipelineState> pipeline,
                    NSUInteger width,
                    NSUInteger height) {
    [encoder setComputePipelineState:pipeline];
    NSUInteger tw = pipeline.threadExecutionWidth;
    NSUInteger th = MAX((NSUInteger)1, pipeline.maxTotalThreadsPerThreadgroup / tw);
    [encoder dispatchThreads:MTLSizeMake(width, height, 1)
      threadsPerThreadgroup:MTLSizeMake(tw, th, 1)];
};
```

### 解释

这是一个小型辅助函数，用来减少重复代码。

给它：

- encoder
- pipeline
- 输出宽高

它就会自动：

- 设置 compute pipeline
- 计算线程组尺寸
- dispatch 整个二维网格

后面的 bloom、particles、upscale 都靠它。

## Y. Bloom 路径

### 代码：1612-1648

这段包含：

1. bright extract
2. horizontal blur
3. vertical blur
4. 错误示例下额外 blur

### 分步解释

#### Y1. Bright Extract

```objc
id<MTLComputeCommandEncoder> brightEncoder = [commandBuffer computeCommandEncoder];
float threshold = (_demoTopic == MetalDemoTopicHDRBloomTAA) ? 1.30f : 0.90f;
[brightEncoder setTexture:_sceneResolveTexture atIndex:0];
[brightEncoder setTexture:_bloomTextureA atIndex:1];
[brightEncoder setBytes:&threshold length:sizeof(float) atIndex:0];
dispatch2D(brightEncoder, _brightExtractPipelineState, _bloomTextureA.width, _bloomTextureA.height);
[brightEncoder endEncoding];
```

解释：

- 输入：全分辨率场景
- 输出：半分辨率 bloomTextureA
- threshold 决定多亮的像素才算“高亮”

#### Y2. 水平模糊

```objc
id<MTLComputeCommandEncoder> blurHEncoder = ...
uint32_t horizontal = 1;
...
dispatch2D(... _blurPipelineState ...)
```

解释：

- 输入：A
- 输出：B
- `horizontal = 1` 表示横向卷积

#### Y3. 垂直模糊

```objc
id<MTLComputeCommandEncoder> blurVEncoder = ...
horizontal = 0;
...
```

解释：

- 输入：B
- 输出：A
- `horizontal = 0` 表示纵向卷积

这样 A 最终保存纵向模糊后的结果。

#### Y4. 错误示例：再多 blur 一轮

```objc
if (_errorExampleEnabled && _demoTopic == MetalDemoTopicHDRBloomTAA)
{
    ...
}
```

解释：

让 bloom 故意变得更糊、更大，更容易观察错误配置造成的画面问题。

## Z. Particles 路径

### 代码：1650-1657

```objc
if (useParticles)
{
    id<MTLComputeCommandEncoder> particleEncoder = [commandBuffer computeCommandEncoder];
    [particleEncoder setTexture:_particleTexture atIndex:0];
    [particleEncoder setBytes:&elapsed length:sizeof(float) atIndex:0];
    dispatch2D(particleEncoder, _particlePipelineState, _particleTexture.width, _particleTexture.height);
    [particleEncoder endEncoding];
}
```

### 解释

#### 输入参数
这里 compute kernel 只需要：

- 输出纹理 `_particleTexture`
- 当前时间 `elapsed`

#### 输出
compute shader 会把粒子叠加图写进 `_particleTexture`。

后面 post pass 再把它混到最终结果里。

## AA. Upscale 路径

### 代码：1659-1698

```objc
id<MTLTexture> sceneForPost = _sceneResolveTexture;
if (useUpscale)
{
    ...
    sceneForPost = _upscaledTexture;
}
```

### 解释总览
默认情况下，post pass 直接用 `_sceneResolveTexture`。  
如果开启主题 14，就先：

1. downsample 到半分辨率
2. 再 upscale 回全分辨率
3. post pass 改用 `_upscaledTexture`

### AA1. Downsample

```objc
id<MTLComputeCommandEncoder> downsampleEncoder = [commandBuffer computeCommandEncoder];
[downsampleEncoder setTexture:_sceneResolveTexture atIndex:0];
[downsampleEncoder setTexture:_halfResTexture atIndex:1];
dispatch2D(downsampleEncoder, _downsamplePipelineState, _halfResTexture.width, _halfResTexture.height);
[downsampleEncoder endEncoding];
```

解释：

- 输入：全分辨率 scene
- 输出：半分辨率 `_halfResTexture`

### AA2. 如果系统支持 MetalFX，就用 Spatial Scaler

```objc
if (@available(macOS 13.0, *))
{
    if (_spatialScaler != nil)
    {
        _spatialScaler.colorTexture  = _halfResTexture;
        _spatialScaler.outputTexture = _upscaledTexture;
        [_spatialScaler encodeToCommandBuffer:commandBuffer];
    }
```

解释：

#### `_spatialScaler.colorTexture`
输入半分辨率图像。

#### `_spatialScaler.outputTexture`
输出全分辨率上采样结果。

#### `encodeToCommandBuffer`
把上采样工作编码进 command buffer。

### AA3. Fallback：手写 bilinear upscale

```objc
else
{
    id<MTLComputeCommandEncoder> upscaleEncoder = [commandBuffer computeCommandEncoder];
    [upscaleEncoder setTexture:_halfResTexture atIndex:0];
    [upscaleEncoder setTexture:_upscaledTexture atIndex:1];
    dispatch2D(upscaleEncoder, _upscalePipelineState, _upscaledTexture.width, _upscaledTexture.height);
    [upscaleEncoder endEncoding];
}
```

解释：

如果 MetalFX 不可用，就自己用 compute shader 做双线性上采样。

#### 最后
```objc
sceneForPost = _upscaledTexture;
```
让 post pass 改读上采样结果。

## AB. 配置 Post Render Pass

### 代码：1700-1705

```objc
MTLRenderPassDescriptor *postPass = [MTLRenderPassDescriptor renderPassDescriptor];
postPass.colorAttachments[0].texture = _postMSAATexture;
postPass.colorAttachments[0].resolveTexture = drawable.texture;
postPass.colorAttachments[0].loadAction = MTLLoadActionClear;
postPass.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
postPass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
```

### 解释

#### `_postMSAATexture`
post pass 自己的 MSAA 颜色目标。

#### `resolveTexture = drawable.texture`
post pass 结束时直接 resolve 到真正屏幕显示用的 drawable。

#### `loadAction = Clear`
清成黑色。

## AC. 创建 post encoder

### 代码：1707-1713

```objc
id<MTLRenderCommandEncoder> postEncoder =
    [commandBuffer renderCommandEncoderWithDescriptor:postPass];
if (!postEncoder)
{
    dispatch_semaphore_signal(_inFlightSemaphore);
    return;
}
```

### 解释

post pass 也是一个 render pass，所以也要用 render encoder。

如果创建失败，本帧直接中止。

## AD. 填充 PostProcessParams

### 代码：1715-1723

```objc
PostProcessParams params;
params.edgeStrength = edgeStrength;
params.sceneMix = sceneMix;
params.bloomStrength = bloomStrength;
params.particleStrength = particleStrength;
params.temporalBlend = temporalBlend;
params.exposure = exposureBias;
params.texelSize = (simd_float2){1.0f / (float)_sceneResolveTexture.width,
                                 1.0f / (float)_sceneResolveTexture.height};
```

### 解释

把本帧后处理需要的参数打包成一个小结构体，传给 `post_fragment`。

#### `texelSize`
一个像素在 UV 空间里有多大。  
有些后处理会依赖它做邻域采样。虽然当前 shader 没大规模使用它，但保留这种字段很常见。

## AE. 绑定 post pass 资源并画全屏三角形

### 代码：1725-1734

```objc
[postEncoder setRenderPipelineState:_postPipelineState];
[postEncoder setFragmentTexture:sceneForPost atIndex:0];
[postEncoder setFragmentTexture:_edgeTexture atIndex:1];
[postEncoder setFragmentTexture:_bloomTextureA atIndex:2];
[postEncoder setFragmentTexture:_particleTexture atIndex:3];
[postEncoder setFragmentTexture:_historyTexture atIndex:4];
[postEncoder setFragmentSamplerState:useAnisoSampler ? _anisoSamplerState : _samplerState atIndex:0];
[postEncoder setFragmentBytes:&params length:sizeof(params) atIndex:0];
[postEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
[postEncoder endEncoding];
```

### 解释

#### `setRenderPipelineState:_postPipelineState`
post shader 生效。

#### 各个 texture slot
- 0：场景结果
- 1：边缘图
- 2：bloom
- 3：particles
- 4：history

#### `setFragmentSamplerState`
给 fragment shader 采样这些纹理时用。

#### `setFragmentBytes`
把后处理参数结构体直接传进去。

#### `drawPrimitives ... vertexCount:3`
画一个全屏三角形，不需要顶点 buffer。

#### `endEncoding`
post pass 编码结束。

## AF. 如果后面还要 temporal，就把当前结果拷成 history

### 代码：1736-1752

```objc
if (temporalBlend > 0.0f || useUpscale)
{
    id<MTLBlitCommandEncoder> historyBlit = [commandBuffer blitCommandEncoder];
    [historyBlit copyFromTexture:sceneForPost
                     sourceSlice:0
                     sourceLevel:0
                    sourceOrigin:MTLOriginMake(0, 0, 0)
                      sourceSize:MTLSizeMake(sceneForPost.width, sceneForPost.height, 1)
                       toTexture:_historyTexture
                destinationSlice:0
                destinationLevel:0
               destinationOrigin:MTLOriginMake(0, 0, 0)];
    [historyBlit endEncoding];
    _historyValid = YES;
}
```

### 解释

#### 为什么不是每帧都拷
因为不是每个主题都需要 history。  
比如只有 temporal 或 upscale 路径才真正会用到它。

#### `copyFromTexture -> toTexture`
把本帧结果拷进 `_historyTexture`，供下一帧读取。

#### `_historyValid = YES`
表示下一帧开始，历史纹理已经有合法内容了。

## AG. 同步/调度主题：signal shared event

### 代码：1754-1760

```objc
if (useSyncScheduling)
{
    if (_sharedEvent)
    {
        [commandBuffer encodeSignalEvent:_sharedEvent value:(uint64_t)_frameIndex];
    }
}
```

### 解释

如果当前主题是同步/调度主题，并且 shared event 存在，就在 command buffer 中编码一个 signal。

#### 意义
这属于更高级的 CPU/GPU 同步教学内容。  
它告诉你 command buffer 完成到某个点时，可以用 GPU 事件来同步更复杂的工作流。

## AH. Profiling 主题：FrameCommit Debug Group

### 代码：1762-1766

```objc
if (useProfiling)
{
    [commandBuffer pushDebugGroup:@"FrameCommit"];
    [commandBuffer popDebugGroup];
}
```

### 解释

给整帧提交点再打一个调试标签。  
这样 Xcode 的 GPU 调试工具里更容易定位阶段边界。

## AI. 更新 CPU 侧统计信息

### 代码：1768-1779

```objc
double cpuFrameMs = (CFAbsoluteTimeGetCurrent() - cpuFrameStart) * 1000.0;
double memoryMB = (double)[self estimatedVideoMemoryBytes] / (1024.0 * 1024.0);
os_unfair_lock_lock(&_metricsLock);
_lastCPUFrameTimeMs    = cpuFrameMs;
_lastEstimatedMemoryMB = memoryMB;
_lastTimeScale         = timeScale;
_lastEdgeStrength      = edgeStrength;
_lastExposure          = exposureBias;
_lastBloomStrength     = bloomStrength;
_lastParticleStrength  = particleStrength;
_lastTemporalBlend     = temporalBlend;
os_unfair_lock_unlock(&_metricsLock);
```

### 解释

#### `cpuFrameMs`
计算 CPU 端编码这一帧花了多少时间。  
注意这不是 GPU 执行时间，而是 CPU 从进入 `render()` 到提交前花的时间。

#### `memoryMB`
估算当前各种 texture/buffer 占用了多少显存/内存。

#### 加锁更新 HUD 缓存
这些值供 UI 面板显示。

## AJ. present + commit

### 代码：1781-1782

```objc
[commandBuffer presentDrawable:drawable];
[commandBuffer commit];
```

### 解释

#### `presentDrawable`
告诉系统：这张 drawable 处理好了，这帧显示它。

#### `commit`
把整份 command buffer 提交给 GPU 执行。

这是每帧的最终“发车按钮”。

# 第四部分：把两部分知识合起来，你现在应该怎么理解这个项目

如果把“零基础课”和“逐行源码”合起来，你现在应该已经能这样理解：

## 1. `initWithLayer:` 做的是“搭舞台”

它负责：

- 拿 GPU 设备
- 配置 `CAMetalLayer`
- 加载 shader
- 创建各种 pipeline
- 创建 buffer / texture / sampler / depth state
- 准备 ICB
- 准备静态 mesh 和材质纹理

一句话：

> **它不负责每帧画什么，而是把“以后每帧渲染要用的工具箱”都准备好。**

## 2. `render()` 做的是“每帧开工”

它负责：

- 等 GPU 空出一个 in-flight 槽位
- 拿 drawable
- 选当前主题路径
- 写 uniform / instance 数据
- 编 scene pass
- 编 compute pass
- 编 post pass
- 必要时拷 history
- present + commit

一句话：

> **它是每帧真正的施工流程。**

## 3. 这个项目的一帧，最简版口语翻译

你可以把整个 `render()` 翻译成一句口语：

> “先拿到当前这一帧的屏幕目标，然后把 3D 场景画到中间纹理里，再按主题决定要不要做边缘、bloom、粒子或上采样，最后用一个全屏后处理把结果混到屏幕上，顺手记录性能指标并提交给 GPU。”

# 第五部分：你现在最该继续怎么学

如果你真想靠这个项目入门 Metal，我建议你下一步这样做：

## 第一步：你自己重新讲一遍 render 流程
你可以试着不看代码，自己复述这 8 步：

1. 等 semaphore
2. 拿 drawable
3. 确保 render targets
4. 建 command buffer
5. 写 uniform / instance
6. scene pass
7. compute/post
8. present + commit

如果你能讲顺，说明骨架已经进脑子了。

## 第二步：自己只盯着一条路径看
我建议先看**最普通的一条路径**，别一上来追全部 15 个主题。

推荐你先只看这几个主题：

- 1：Resource & Memory
- 8：PBR
- 9：Bloom
- 14：Upscale

## 第三步：自己动手做 3 个最有价值的小改动

### 改动 A
把 scene clear color 改成你喜欢的颜色，确认你知道它影响的是哪一层。

### 改动 B
把 `edgeStrength` 改成 0 / 2，观察 post pass 变化。

### 改动 C
把 `kSampleCount` 从 4 改成 1，观察 MSAA 变化。

这 3 个实验非常适合新手。

## 第四步：再去看 shader 文件
现在再回去看：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/shaders/triangle.metal`

你会更容易看懂：

- 哪个 buffer 对应哪个 slot
- 哪个 texture 是从哪里来的
- 为什么 post pass 只画 3 个顶点

如果你愿意，我下一条可以继续做两件非常适合你的事，任选一个或都要：

1. **继续按源码顺序，逐行讲 `/Users/mtl/Learn/my-demo/MetalCMakeDemo/shaders/triangle.metal`**
2. **我给你画一份“这个项目的 Metal 学习地图”，告诉你每个主题该先学什么、后学什么、重点盯哪几个函数** 

如果你想，我也可以下一条直接进入：  
**“逐行讲 shader 文件”**。

---

## 第 3 轮

**用户：**

 [postEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3]; 为啥绘制只用了vertexCount:3，
另外，在项目根目录新建一个md文件夹， 把当前对话及之前的对话保存成md文件存到md文件夹

**助手：**

这里的 `vertexCount:3`，因为它**不是在画一个普通模型**，而是在画一个 **全屏三角形（full-screen triangle）**。

## 为啥 3 个点就够了

这句：

```objc
[postEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
```

意思是：

- 图元类型：三角形
- 从第 0 个顶点开始
- 一共取 3 个顶点

所以最终就是画 **1 个三角形**。

但这个三角形不是“小三角形”，而是一个**覆盖整个屏幕的大三角形**。

## 对应的顶点在哪来的

它不是从 vertex buffer 里读的，而是 shader 里直接生成的。  
在 `/Users/mtl/Learn/my-demo/MetalCMakeDemo/shaders/triangle.metal` 里：

```metal
float2 positions[3] = {
    float2(-1.0, -1.0),
    float2(3.0, -1.0),
    float2(-1.0, 3.0)
};
```

这 3 个点是：

- 左下角：`(-1, -1)`
- 右边屏幕外：`(3, -1)`
- 上边屏幕外：`(-1, 3)`

它们组成的那个大三角形，会把屏幕区域整个盖住。

## 为啥后处理常这么干，而不是画两个三角形拼矩形

因为全屏三角形通常更好：

### 1. 更简单
- 不用 vertex buffer
- 不用 index buffer
- 只靠 `vertex_id` 就能生成顶点

### 2. 避免中间拼接缝
如果你用两个三角形拼一个矩形，中间会有一条对角线。  
某些后处理里可能出现：

- 插值差异
- 导数不连续
- 接缝伪影

全屏三角形没有这条内部边。

### 3. 很常见
很多后处理 pass 都这么做，比如：

- tone mapping
- bloom composite
- FXAA / TAA
- copy pass
- debug view

## 这句代码真正的意义

它表面上是在“画一个三角形”，  
本质上是在说：

> 用一个覆盖全屏的大三角形，触发 fragment shader 对屏幕上每个像素执行一次后处理。

所以重点不是几何本身，重点是：

- `post_vertex` 生成全屏覆盖
- `post_fragment` 对每个像素采样：
  - scene
  - edge
  - bloom
  - particles
  - history

然后输出最终颜色。

## 一句话记忆

**普通模型绘制：**
- `vertexCount` 对应真实几何顶点

**全屏后处理：**
- `vertexCount:3` 只是为了触发一个 full-screen triangle

另外，按你的要求我已经创建好了目录和文件：

- 目录：`/Users/mtl/Learn/my-demo/MetalCMakeDemo/md`
- 文件：`/Users/mtl/Learn/my-demo/MetalCMakeDemo/md/2026-04-21_metal_learning_dialogue.md`

我保存的是**当前及之前对话的 Markdown 整理版记录**。  
如果你要，我下一步可以继续给你讲：

1. **为什么 `(-1,-1) / (3,-1) / (-1,3)` 恰好能覆盖全屏**
2. **`uv = pos * 0.5 + 0.5` 为什么这么写**
3. **clip space / NDC / viewport 三者关系**

这三个问题一搞懂，你对 post pass 会彻底通。

---

## 第 4 轮

**用户：**

为什么 (-1,-1) / (3,-1) / (-1,3) 恰好能覆盖全屏
uv = pos * 0.5 + 0.5 为什么这么写
clip space / NDC / viewport 三者关系
讲解 ，并且同步更新md文档

**助手：**

可以，我们把这三个问题串起来讲。  
因为它们本质上是同一条链：

> **顶点坐标怎么从 shader 里的数，变成屏幕上的像素位置；再怎么变成纹理采样坐标。**

我先给你一句总纲：

- `(-1,-1) / (3,-1) / (-1,3)`：是在**构造一个覆盖整个屏幕的大三角形**
- `uv = pos * 0.5 + 0.5`：是在把 **[-1,1] 坐标映射到 [0,1] 纹理坐标**
- `clip space -> NDC -> viewport`：是在说明**GPU 最终怎么把这个三角形画到屏幕上**

另外，**md 文档我已经同步更新了**，文件还是这个：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/md/2026-04-21_metal_learning_dialogue.md`

# 一、为什么 `(-1,-1) / (3,-1) / (-1,3)` 恰好能覆盖全屏

先说结论：

> 它们组成的不是“刚好等于屏幕”的三角形，  
> 而是一个**比屏幕更大**的三角形。  
> 屏幕那块矩形区域完整落在这个三角形里面，所以它能覆盖全屏。

## 1. 先明确：屏幕在这个坐标系里对应什么区域

在 post pass 里，我们通常在一种“屏幕风格”的归一化坐标系里思考。  
最常见的二维范围是：

- 左边：`x = -1`
- 右边：`x = 1`
- 下边：`y = -1`
- 上边：`y = 1`

所以屏幕区域可以想成这个方框：

```text
(-1, 1) ---------------- (1, 1)
   |                        |
   |        屏幕区域         |
   |                        |
(-1,-1) ---------------- (1,-1)
```

也就是：

```text
x ∈ [-1, 1]
y ∈ [-1, 1]
```

## 2. 再看这 3 个点

post shader 里这 3 个点是：

- A = `(-1, -1)`
- B = `( 3, -1)`
- C = `(-1,  3)`

画出来大概是这样：

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

注意：

- A 在屏幕左下角
- B 已经跑到屏幕右边外面了
- C 已经跑到屏幕上边外面了

这正是故意设计的。

## 3. 为什么这个大三角形能盖住整个屏幕矩形

你可以这样理解：

### 左边界
三角形的一条边就是从 `(-1,-1)` 到 `(-1,3)`，  
所以屏幕左边这整条线都在三角形边上或内部。

### 下边界
另一条边是从 `(-1,-1)` 到 `(3,-1)`，  
所以屏幕下边这整条线也在三角形边上或内部。

### 右上区域怎么办
关键在第三条斜边，它从 `(-1,3)` 连到 `(3,-1)`，把整个右上方向包了进去。

所以整个 `[-1,1] x [-1,1]` 的屏幕方框都落在这个三角形里面。

## 4. 用一个更“数学直觉”的方式理解

这条斜边从：

- `(-1, 3)` 到 `(3, -1)`

它的方程其实是：

```text
x + y = 2
```

而屏幕右上角 `(1,1)` 正好满足：

```text
1 + 1 = 2
```

也就是说：

- 右上角 `(1,1)` 正好落在这条边上
- 屏幕其它区域都在边的内侧

所以整个屏幕矩形完整被包含住了。

这个点很关键。

## 5. 为什么是 `3`，不是 `2` 或 `10`

因为这个构造刚好简单、常用，而且能保证覆盖完整屏幕。

例如：

- A = `(-1,-1)`
- B = `(3,-1)`
- C = `(-1,3)`

这样斜边正好穿过 `(1,1)`。

如果你把 3 换成别的值，未必不行，但这个写法是最经典、最常见的一种。

## 6. 为什么不用“两个三角形拼满屏矩形”

你可能会想：

> 既然屏幕是矩形，为什么不老老实实画一个矩形？

当然可以。  
常见方式是：

- 4 个顶点
- 2 个三角形
- 拼成 full-screen quad

但全屏三角形更常见，原因是：

### 原因 A：更简单
- 只要 3 个顶点
- 不用 index buffer
- 甚至常常不用 vertex buffer

### 原因 B：没有中间对角线
两个三角形拼矩形时，中间会有一条斜分界线。  
在某些后处理里，这条线附近可能出现：

- 插值差异
- 导数不连续
- 接缝伪影

全屏三角形没有内部拼接边。

### 原因 C：性能和工程上都更干净
少一个三角形，逻辑更统一。

# 二、为什么 `uv = pos * 0.5 + 0.5`

这句是后处理里最经典的坐标变换之一。

## 1. 先看 `pos` 的范围

在 `post_vertex` 里，顶点位置 `pos` 是这种风格：

- 左边 `x = -1`
- 右边 `x = 1`
- 下边 `y = -1`
- 上边 `y = 1`

这是一个 **[-1,1] 区间** 的坐标系统。

但纹理采样用的 `uv` 一般是：

- 左边 `u = 0`
- 右边 `u = 1`
- 下边 `v = 0`
- 上边 `v = 1`

这是一个 **[0,1] 区间** 的坐标系统。

所以你现在要做的事情，本质上就是：

> 把 `[-1,1]` 映射成 `[0,1]`

## 2. 线性映射怎么做

把区间 `[-1,1]` 映射到 `[0,1]`，最标准的公式就是：

```text
uv = pos * 0.5 + 0.5
```

验证一下：

### 当 `pos = -1`
```text
uv = -1 * 0.5 + 0.5 = 0
```

### 当 `pos = 0`
```text
uv = 0 * 0.5 + 0.5 = 0.5
```

### 当 `pos = 1`
```text
uv = 1 * 0.5 + 0.5 = 1
```

完全符合预期。

## 3. 所以这句代码本质是在干嘛

```metal
out.uv = pos * 0.5 + 0.5;
```

本质含义是：

> “把屏幕风格坐标变成纹理风格坐标。”

这样 fragment shader 就能用这个 `uv` 去采样：

- `sceneTexture`
- `edgeTexture`
- `bloomTexture`
- `particleTexture`
- `historyTexture`

## 4. 但这里顶点里有 `3`，算出来不会超过 1 吗？

会，确实会。

比如：

- `pos.x = 3`
- 那 `uv.x = 3 * 0.5 + 0.5 = 2.0`

这不是 bug。

因为虽然**顶点**在屏幕外，  
但真正会被 rasterize 并进入 fragment shader 的，是**屏幕内部那一块**。

也就是说：

- 顶点坐标可以超出屏幕
- GPU 只会对屏幕可见区域生成片元
- 屏幕内部那部分插值得到的 `uv`，正好是你想要的范围

这是 full-screen triangle 的正常工作方式。

# 三、clip space / NDC / viewport 三者关系

这是图形学坐标系统的关键链条。  
你搞懂这个，很多 shader 代码都会突然变清晰。

## 1. Clip Space 是什么

顶点着色器最终要输出：

```metal
float4 position [[position]];
```

这个输出最先处在 **clip space（裁剪空间）** 概念里。

它是一个齐次坐标，形式是：

```text
(x, y, z, w)
```

在你的 post pass 里：

```metal
out.position = float4(pos, 0.0, 1.0);
```

所以这里其实是：

```text
x = pos.x
y = pos.y
z = 0
w = 1
```

## 2. NDC 是什么

GPU 接下来会做一步很重要的操作，叫：

> **透视除法**

公式是：

```text
ndc = (x / w, y / w, z / w)
```

这一步之后，就进入 **NDC（Normalized Device Coordinates，标准化设备坐标）**。

## 3. 在这个 post pass 里，为什么特别简单

因为这里你写的是：

```text
w = 1
```

所以：

```text
ndc = (x, y, z)
```

也就是说，在这个全屏后处理里：

- clip space 和 NDC 在数值上几乎一样好理解

所以你看到的这些点：

- `(-1,-1)`
- `(3,-1)`
- `(-1,3)`

其实你完全可以把它们当作“直接在 NDC 风格里思考”。

## 4. NDC 的典型范围

通常可以这样记：

- x ∈ `[-1, 1]`
- y ∈ `[-1, 1]`

其中：

- `(-1,-1)`：左下
- `(1,-1)`：右下
- `(-1,1)`：左上
- `(1,1)`：右上

这个正方形就是屏幕映射前的标准化范围。

## 5. Viewport 是什么

NDC 还不是最终屏幕像素坐标。  
接下来 GPU 会做 **viewport transform（视口变换）**。

它把 NDC 映射到真正的像素矩形。

比如窗口大小是 800 x 600，那么大致上：

- `x = -1` -> 映射到屏幕最左边
- `x = 1` -> 映射到屏幕最右边
- `y = -1` -> 映射到屏幕最下边
- `y = 1` -> 映射到屏幕最上边

于是：

- NDC 是“归一化后的逻辑坐标”
- viewport 后才变成“真正屏幕像素坐标”

## 6. 三者的完整关系图

你可以记成这条链：

```text
Vertex Shader 输出
clip space: (x, y, z, w)
        |
        | 透视除法: (x/w, y/w, z/w)
        v
NDC: [-1,1] 范围
        |
        | viewport transform
        v
屏幕像素坐标
```

## 7. `uv` 又是另一条平行映射

同时还有一条很常见的“小支线”：

```text
屏幕/NDC 风格坐标 [-1,1]
        |
        | *0.5 + 0.5
        v
纹理坐标 [0,1]
```

这就是：

```metal
uv = pos * 0.5 + 0.5
```

的本质。

# 四、把这三件事连成一个整体来理解

现在把三个问题合起来：

## 1. 为什么那 3 个点能覆盖全屏
因为它们在 clip/NDC 风格坐标里构成了一个超大的三角形，完整罩住了屏幕对应的 `[-1,1] x [-1,1]` 区域。

## 2. 为什么 `uv = pos * 0.5 + 0.5`
因为 `pos` 是屏幕/NDC 风格坐标，而纹理采样要用 `[0,1]` 的 UV，所以要做线性映射。

## 3. clip / NDC / viewport 关系
因为顶点不是直接“变成屏幕像素”，而是经过：

- clip space
- 透视除法变 NDC
- viewport 变换到屏幕

这条链路。

# 五、你可以这样牢牢记住

## 对 3D 模型渲染
- 顶点来自 vertex buffer
- 经过 MVP 变换
- 输出到 clip space
- GPU 做透视除法得到 NDC
- 再映射到 viewport
- 最后光栅化成屏幕像素

## 对全屏后处理
- 顶点经常不来自真实模型
- 直接在 vertex shader 里构造一个 full-screen triangle
- fragment shader 对屏幕每个像素做采样和合成
- `uv` 用来采样 scene / bloom / edge 等纹理

# 六、最简总结版

### 为什么 `(-1,-1)/(3,-1)/(-1,3)` 能覆盖全屏？
因为它们组成了一个比屏幕更大的三角形，屏幕矩形完整落在它内部。

### 为什么 `uv = pos * 0.5 + 0.5`？
因为它把 `[-1,1]` 的屏幕/NDC 风格坐标，线性映射成 `[0,1]` 的纹理坐标。

### clip space / NDC / viewport 是什么关系？
- vertex shader 输出 clip space
- GPU 做透视除法得到 NDC
- GPU 再把 NDC 映射到 viewport，也就是实际屏幕像素区域

如果你愿意，我下一步可以继续专门讲两个非常关键的问题：

1. **为什么 full-screen triangle 不会在屏幕边缘出错插值**
2. **post pass 里的 `uv` 插值过程到底是怎么发生的**

这两个一旦搞懂，你对后处理 pipeline 的理解会再上一个台阶。

---

## 第 5 轮

**用户：**

为什么 full-screen triangle 不会在屏幕边缘出错插值
post pass 里的 uv 插值过程到底是怎么发生的
另外 出现的是一个立方体，为啥最后绘制只画了三角形 ，需要同步md文档

**助手：**

当然，这几个问题是**后处理 pipeline 的核心**。  
你一旦搞懂，Metal 里很多 screen-space 技术都会变得很顺。

另外我已经**同步更新 md 文档**了，文件还是：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/md/2026-04-21_metal_learning_dialogue.md`

# 一、为什么 full-screen triangle 不会在屏幕边缘出错插值

先给结论：

> **它不仅不会更容易错，反而通常比“两个三角形拼一个矩形”更稳定。**

原因主要有 4 个：

1. GPU 会先做 **裁剪（clipping）**
2. 只对**屏幕内真正可见的 fragment**做插值
3. 这个 pass 只有**一个三角形**，没有内部拼接缝
4. 这里 `w = 1`，所以 UV 插值非常干净，几乎就是屏幕空间线性插值

## 1. 顶点在屏幕外，不等于会“错误显示”

full-screen triangle 的 3 个顶点是：

- A = `(-1, -1)`
- B = `( 3, -1)`
- C = `(-1,  3)`

其中：

- B 在屏幕右边外面
- C 在屏幕上边外面

但 GPU 不会把“屏幕外部分”也傻乎乎画出来。  
它的流程是：

### 第一步：裁剪
先把超出视口/裁剪范围的三角形处理掉，只保留会落到屏幕上的那一部分。

### 第二步：光栅化
只对屏幕内真正被覆盖的像素生成 fragment。

所以虽然顶点在屏幕外，  
**真正进入 fragment shader 的，只是屏幕内那块区域。**

## 2. 为什么边缘不会 UV 错位

因为 `uv` 不是“自己突然冒出来的”，而是**跟着顶点一起输出，再由 GPU 自动插值出来的**。

在 `post_vertex` 里：

```metal
out.position = float4(pos, 0.0, 1.0);
out.uv = pos * 0.5 + 0.5;
```

于是三个顶点对应的 UV 是：

- A = `(-1,-1)` -> `uv = (0,0)`
- B = `( 3,-1)` -> `uv = (2,0)`
- C = `(-1, 3)` -> `uv = (0,2)`

你会发现，B 和 C 的 UV 已经超过 1 了。  
这没问题。

因为真正关键不是“顶点本身的 UV 超没超”，  
而是：

> **屏幕内部那些 fragment 插值出来的 UV 是不是对的。**

而屏幕四个角，恰好会插值到标准纹理坐标：

- 左下角 -> `(0,0)`
- 右下角 -> `(1,0)`
- 左上角 -> `(0,1)`
- 右上角 -> `(1,1)`

所以屏幕内部自然就是完整的 `[0,1] x [0,1]` 采样域。

## 3. 它为什么反而比 full-screen quad 更不容易出问题

如果你用“两个三角形拼一个矩形”，屏幕会被分成两块：

- 左上一个三角形
- 右下一个三角形

这样会带来一个隐藏问题：

> 中间有一条对角线分界线

很多后处理里，这条线附近可能出现：

- 插值方式不完全一致
- 导数不连续
- ddx / ddy 差异
- 细微接缝伪影

而 full-screen triangle 有一个巨大优点：

> **整个屏幕都属于同一个三角形**

所以：

- 没有内部拼接边
- 没有跨两个三角形的导数断点
- 插值逻辑完全统一

这就是为什么现代图形 API 里 full-screen triangle 很常见。

## 4. 这里 `w = 1`，所以更稳

在 post pass 中：

```metal
out.position = float4(pos, 0.0, 1.0);
```

所有顶点的 `w` 都是 1。  
这意味着：

- 不涉及复杂的透视深度变化
- 透视校正插值会退化成非常直观的线性插值

所以这个场景下，UV 插值是非常稳定的。

# 二、post pass 里的 UV 插值过程到底是怎么发生的

这是 GPU 光栅化最重要的机制之一。

我按步骤讲。

## 1. Vertex Shader 先给每个顶点准备好 UV

在 `post_vertex` 中：

```metal
float2 positions[3] = {
    float2(-1.0, -1.0),
    float2(3.0, -1.0),
    float2(-1.0, 3.0)
};

float2 pos = positions[vertexID];
out.position = float4(pos, 0.0, 1.0);
out.uv = pos * 0.5 + 0.5;
```

所以 3 个顶点的输出大概是：

### 顶点 A
```text
position = (-1,-1,0,1)
uv       = (0,0)
```

### 顶点 B
```text
position = (3,-1,0,1)
uv       = (2,0)
```

### 顶点 C
```text
position = (-1,3,0,1)
uv       = (0,2)
```

也就是说：

> vertex shader 负责定义“顶点处的已知 UV 值”。

## 2. Rasterizer 负责把三角形铺成很多 fragment

接下来 GPU 会做 rasterization：

- 判断这个三角形覆盖了哪些像素
- 对每个被覆盖的像素中心生成一个 fragment

注意：

- 不是只处理 3 个点
- 是处理这个三角形覆盖到的整片区域

这就是为什么后处理能“扫满整个屏幕”。

## 3. 每个 fragment 都会算自己的重心坐标

对于三角形内部任意一个 fragment，GPU 会计算它相对于三个顶点的权重：

- `α`
- `β`
- `γ`

并满足：

```text
α + β + γ = 1
```

这些权重就是**重心坐标（barycentric coordinates）**。

你可以把它理解成：

> “这个像素离 3 个顶点分别有多近，所以应该从 3 个顶点各拿多少属性值来混合。”

## 4. 用重心坐标插值 UV

如果三个顶点的 UV 分别是：

- `uv0`
- `uv1`
- `uv2`

那么三角形内部任意一个 fragment 的 UV 就是：

```text
uv = α * uv0 + β * uv1 + γ * uv2
```

这就是 varying 插值。

所以 post pass 里的 UV 并不是你手动一像素一像素算出来的，  
而是 GPU 光栅化阶段自动插值出来的。

## 5. 这里其实是 perspective-correct interpolation

严格地说，GPU 默认不是做“普通线性插值”，而是做：

> **透视正确插值（perspective-correct interpolation）**

因为正常 3D 场景里，顶点的 `w` 往往不同。  
如果不用透视修正，纹理会扭曲。

但在这个 post pass 里：

```metal
w = 1
```

所有顶点的 `w` 都相同，所以透视修正前后结果一致。

因此这里你可以放心把它理解成：

> **屏幕空间中的线性 UV 插值**

这也是 full-screen triangle 做 post 的原因之一：很干净。

## 6. 为什么屏幕四角刚好对应标准 UV 四角

这是个很好的直觉点。

三个顶点的 UV 是：

- A -> `(0,0)`
- B -> `(2,0)`
- C -> `(0,2)`

虽然顶点 UV 超出标准范围，但屏幕区域只是这个大三角形的一部分。

### 屏幕右下角 `(1,-1)`
它位于边 AB 上。  
AB 从 x=-1 走到 x=3，刚好跨度 4。  
从 -1 到 1 刚好走了一半，所以 UV 也走到一半：

```text
(0,0) -> (2,0) 的中点 = (1,0)
```

### 屏幕左上角 `(-1,1)`
它位于边 AC 上，也刚好是中点：

```text
(0,0) -> (0,2) 的中点 = (0,1)
```

### 屏幕右上角 `(1,1)`
它位于边 BC 上，也刚好会插值到：

```text
(1,1)
```

于是整个屏幕内自然就形成了标准纹理 UV 网格。

# 三、为什么出现的是一个立方体，但最后绘制只画了三角形

这个问题非常关键。  
因为它能帮你真正理解“多 pass 渲染”。

先说结论：

> **因为你看到的立方体，是在前一个 pass 里画出来的。**  
> 最后那个三角形，只是把“已经画好的立方体图像”拿来做后处理并显示到屏幕。

## 1. 这一帧其实不是只 draw 一次

虽然你盯到这句：

```objc
[postEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
```

但这只是 **post pass** 的 draw。  
在它之前，scene pass 已经画过立方体了。

## 2. Scene Pass 里真正画了立方体

前面在 scene pass 里有这句：

```objc
[sceneEncoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                          indexCount:_indexCount
                           indexType:MTLIndexTypeUInt16
                         indexBuffer:_indexBuffer
                   indexBufferOffset:0];
```

这里才是真正用：

- `_vertexBuffer`
- `_indexBuffer`
- `scene_vertex`
- `scene_fragment`

把立方体模型画出来。

它的输出不是直接上屏，而是写进：

- `_sceneMSAATexture`
- resolve 到 `_sceneResolveTexture`

你可以把 `_sceneResolveTexture` 想成：

> “已经画好立方体的一张中间图片”

## 3. Post Pass 画的三角形，本质上是“屏幕载体”

到了 post pass：

```objc
[postEncoder setFragmentTexture:sceneForPost atIndex:0];
...
[postEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
```

这里的意思不是“再画一个立方体”。

而是：

- 画一个 full-screen triangle
- 让 `post_fragment` 对屏幕每个像素运行一次
- 在 `post_fragment` 里去采样 `sceneTexture`
- 而 `sceneTexture` 里面已经有立方体图像了

所以最终你看到的是：

> **一个立方体的屏幕图像，经过 post pass 处理后，被显示出来。**

## 4. 最好懂的类比：先拍照，再加滤镜

你可以把整条链想成这样：

### Scene Pass
先拍一张“立方体照片”  
存到 `_sceneResolveTexture`

### Post Pass
拿这张照片做滤镜：
- 边缘增强
- bloom
- 粒子叠加
- temporal 混合

最后输出到屏幕

所以最后那个三角形不是“画面内容本身”，而是：

> **承载全屏滤镜处理的几何体**

## 5. 为什么后处理几乎总是这样做

因为后处理是**屏幕空间**操作。  
它关心的不是“再画一次模型”，而是：

- 当前屏幕这个像素原来是什么颜色
- 它周围像素是什么颜色
- 需不需要做边缘、模糊、曝光、混合

所以最自然的做法就是：

1. 先把 3D 场景画成一张 texture
2. 再用一个 full-screen triangle 把这张 texture 铺到屏幕上
3. fragment shader 在铺的过程中做各种图像处理

# 四、把这三个问题合成一句总理解

现在你可以把 post pass 这么理解：

> **GPU 先在 scene pass 里把立方体画进一张中间纹理；然后用一个覆盖全屏的大三角形，把这张纹理重新采样到屏幕上；在重新采样过程中，UV 通过重心坐标插值得到，并且因为整个屏幕只属于一个三角形，所以不会有内部拼缝和边缘插值问题。**

# 五、最简总结

### 为什么 full-screen triangle 不会在边缘出错？
因为 GPU 会先裁剪，然后只对屏幕内 fragment 插值；而且屏幕只属于一个三角形，没有内部拼接缝。

### post pass 的 UV 是怎么来的？
vertex shader 先给 3 个顶点输出 UV，rasterizer 再对每个 fragment 用重心坐标做插值；本例中因为 `w=1`，近似等同于屏幕空间线性插值。

### 为什么看到的是立方体，但最后只画三角形？
因为立方体是在 **scene pass** 里画出来的；最后那一个三角形只是 **post pass 的全屏载体**，它负责把 scene 结果采样并输出到屏幕。

如果你愿意，我下一步可以继续接着讲两个很关键的问题：

1. **`scene pass -> post pass` 之间 texture 是怎么传递的**
2. **为什么 `_sceneMSAATexture` 还要 resolve 到 `_sceneResolveTexture`，不能直接给 post pass 用**

这两个问题会把你对整个渲染链再打通一层。

---

## 第 6 轮

**用户：**

scene pass -> post pass 之间 texture 是怎么传递的
为什么 _sceneMSAATexture 还要 resolve 到 _sceneResolveTexture，不能直接给 post pass 用
对话完成之后，需要同步到md文件，我看md文件没有包括整个全部的对话，我需要包括整个完整的全部对话

**助手：**

先回答这两个 Metal 问题，再说文档同步。

# 一、scene pass -> post pass 之间 texture 是怎么传递的

你可以把它理解成：

> **前一个 pass 把结果写进一张 GPU 纹理，后一个 pass 再把这张纹理当输入读出来。**

这就是多 pass 渲染最核心的“传棒”方式。

在这个项目里，scene pass 和 post pass 之间并不是“直接把像素塞给下一个函数”，而是通过**中间纹理**传递。

## 1. Scene pass 先把场景画到 `_sceneMSAATexture`

在 `render()` 里，scene pass 的关键配置是：

```objc
scenePass.colorAttachments[0].texture = _sceneMSAATexture;
scenePass.colorAttachments[0].resolveTexture = _sceneResolveTexture;
scenePass.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
```

这表示：

- 立方体、光照、纹理采样等 scene 渲染，先写进 `_sceneMSAATexture`
- scene pass 结束时，再 resolve 成 `_sceneResolveTexture`

所以从“数据流”角度看：

```text
scene vertex/fragment shader
        ↓
_sceneMSAATexture
        ↓ resolve
_sceneResolveTexture
```

## 2. 后续 compute pass 直接读取 `_sceneResolveTexture`

比如 edge detect：

```objc
[computeEncoder setTexture:_sceneResolveTexture atIndex:0];
[computeEncoder setTexture:_edgeTexture atIndex:1];
```

意思就是：

- `_sceneResolveTexture` 是输入
- `_edgeTexture` 是输出

同样，bloom 的亮部提取也是读 `_sceneResolveTexture`：

```objc
[brightEncoder setTexture:_sceneResolveTexture atIndex:0];
[brightEncoder setTexture:_bloomTextureA atIndex:1];
```

所以 scene pass 的输出不会只给 post pass，实际上会先被多个 compute pass 消费。

## 3. post pass 再把这些中间纹理统一读进来

到了 post pass：

```objc
[postEncoder setFragmentTexture:sceneForPost atIndex:0];
[postEncoder setFragmentTexture:_edgeTexture atIndex:1];
[postEncoder setFragmentTexture:_bloomTextureA atIndex:2];
[postEncoder setFragmentTexture:_particleTexture atIndex:3];
[postEncoder setFragmentTexture:_historyTexture atIndex:4];
```

这里的 `sceneForPost` 通常是：

- 默认：`_sceneResolveTexture`
- 如果走上采样路径：`_upscaledTexture`

所以 post pass 实际上是在读：

- scene 结果
- edge 结果
- bloom 结果
- particle 结果
- history 结果

然后在 `post_fragment` 里统一合成，最后输出到屏幕。

## 4. 所以 scene -> post 的传递，本质就是“GPU 纹理接力”

你可以把整个链路简单记成：

```text
Scene Pass
  输出 -> _sceneMSAATexture
  resolve -> _sceneResolveTexture

Compute Passes
  读取 _sceneResolveTexture
  产出 _edgeTexture / _bloomTextureA / ...

Post Pass
  读取 scene + edge + bloom + particle + history
  输出 -> drawable.texture
```

这就是 render pass 和 render/compute pass 之间最典型的资源流。

## 5. Metal 怎么知道顺序不会乱？

因为这些 encoder 都被编码进**同一个 `MTLCommandBuffer`** 里。

顺序大致是：

1. scene render encoder
2. compute encoder(s)
3. post render encoder
4. blit encoder
5. present / commit

Metal 会按 command buffer 中的顺序执行，并对资源访问做 hazard 跟踪。  
所以只要你正确配置资源 usage / pass 顺序，就不需要你手动做“把纹理传给下一个函数”的工作。

换句话说：

> **纹理不是在 CPU 里搬来搬去，而是在 GPU 命令流里被前一个 pass 写、后一个 pass 读。**

# 二、为什么 `_sceneMSAATexture` 还要 resolve 到 `_sceneResolveTexture`，不能直接给 post pass 用

先说结论：

> **因为 `_sceneMSAATexture` 是多采样纹理，而 post/compute 通常想读的是“每像素一个最终颜色”的普通单采样纹理。**

这两者不是一回事。

## 1. `_sceneMSAATexture` 里存的不是“一个像素一个颜色”

MSAA texture 的本质是：

- 一个像素里有多个 sample
- 例如 4x MSAA 时，一个像素内部可能存 4 份颜色样本

它更像这样：

```text
pixel(10,20):
  sample0 = ...
  sample1 = ...
  sample2 = ...
  sample3 = ...
```

而普通纹理 `_sceneResolveTexture` 则是：

```text
pixel(10,20):
  finalColor = average/resolved result
```

后处理大多数时候需要的是后者。

## 2. post shader 里用的是普通 `texture2d<float>` 采样

你看 `post_fragment`：

```metal
fragment float4 post_fragment(PostVertexOut in [[stage_in]],
                              texture2d<float> sceneTexture [[texture(0)]],
                              ...)
```

这里声明的是：

```metal
texture2d<float>
```

不是：

```metal
texture2d_ms<float>
```

说明 post shader 期望读的是**普通二维纹理**，不是多采样纹理。

也就是说，从 shader 类型上，这个项目的 post pass 就是围绕“resolved 后的单采样纹理”设计的。

## 3. compute shader 也不适合直接把 MSAA 纹理当普通图来处理

像 edge detect / bloom 这些 compute kernel，声明的也都是普通纹理：

```metal
texture2d<float, access::read>
```

不是 multi-sample texture。

如果你非要直接用 `_sceneMSAATexture`，那就要：

- 改 shader 类型
- 改访问方式
- 按 sample 单独读取
- 自己手动 resolve / 平均

这会让后处理逻辑变复杂很多。

## 4. resolve 是从“几何渲染阶段”过渡到“屏幕空间后处理阶段”的天然分界点

你可以把它理解成：

### Scene pass 阶段
关心的是：

- 三角形边缘锯齿
- coverage
- 每像素多个 sample 的保真度

所以使用 `_sceneMSAATexture`。

### Post pass / Compute 阶段
关心的是：

- 每个屏幕像素最终颜色是多少
- 做模糊、边缘检测、曝光、合成

所以更适合使用 `_sceneResolveTexture`。

也就是说，resolve 刚好是：

> “从多 sample 几何世界，进入单 sample 图像处理世界”的边界。

## 5. 还有一个很现实的原因：性能和带宽

如果你强行在后处理里反复访问 `_sceneMSAATexture`：

- 每个像素不是读 1 份颜色，而是可能读 4 份 sample
- 采样、模糊、边缘检测都会更贵
- 显存带宽消耗也更大

而 resolve 之后：

- 每个像素就是 1 个最终颜色
- 后处理最自然
- 代价更低

所以绝大多数后处理链都会在 geometry pass 后先 resolve。

## 6. 在这个项目里，甚至 usage 也说明它本来就不是拿来 shader-read 的

在 `ensureRenderTargetsForDrawable:` 中：

```objc
sceneMSAADescriptor.usage = MTLTextureUsageRenderTarget;
```

而 `_sceneResolveTexture` 是：

```objc
sceneResolveDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
```

这很明确地表达了设计意图：

- `_sceneMSAATexture`：只给 render target 用
- `_sceneResolveTexture`：后面要给 shader read 用

所以不仅“逻辑上不合适”，在这个项目的资源 usage 设计里，它本来就不是给 post/compute 直接读的。

## 7. 能不能技术上直接读 MSAA texture？

**能，但不是这个项目的设计方向，而且通常没必要。**

如果你真想这么做，需要：

- 改成支持 multi-sample texture 的 shader 接口
- 使用按 sample 读取的方式
- 自己决定如何合并这些 sample

这通常用于一些特殊技术，而不是常规 post-processing 主路径。

所以对于这个项目来说，最合理的路线就是：

```text
_sceneMSAATexture
   -> resolve
_sceneResolveTexture
   -> compute/post
```

# 三、把这两个问题合成一句最关键的话

你可以记住：

> **scene pass 和 post pass 之间不是直接传“函数返回值”，而是通过 GPU 中间纹理传递；而 `_sceneMSAATexture` 之所以要 resolve 成 `_sceneResolveTexture`，是因为后处理要消费的是“每像素一个最终颜色”的单采样图像，而不是多采样几何缓冲。**

# 四、最简图示

```text
Scene Pass
  render to _sceneMSAATexture (4x MSAA)
          |
          | resolve
          v
  _sceneResolveTexture (single-sample)
          |
          +--> edge compute -> _edgeTexture
          +--> bloom compute -> _bloomTextureA/B
          +--> upscale path -> _upscaledTexture
          |
          v
Post Pass
  sample scene/edge/bloom/particle/history
          |
          v
  drawable.texture
```

# 五、关于 md 文件：这次我已经按你的要求补成“完整对话版”

你说得对，之前那个文件是整理版，不是完整逐轮全文。

这次我已经另外生成了一个**完整全文版**，包含从一开始到当前这轮的全部用户/助手对话：

- `/Users/mtl/Learn/my-demo/MetalCMakeDemo/md/2026-04-21_full_conversation.md`

说明：

- 原来的 `2026-04-21_metal_learning_dialogue.md` 还保留着，属于整理版/学习版
- 新的 `2026-04-21_full_conversation.md` 是你要的**完整全文对话版**

如果你愿意，我下一步可以继续往下讲一个非常自然的后续问题：

1. **为什么 compute pass 里 `setTexture(... atIndex:n)` 和 post pass 里 `setFragmentTexture(... atIndex:n)` 本质上是同一类“资源绑定”**
2. **为什么 `_historyTexture` 不是直接在 post pass 里写，而是额外用 blit copy**
