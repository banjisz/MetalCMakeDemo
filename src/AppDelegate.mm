#import "AppDelegate.h"
#import "Renderer.h"
#import "OpenGLRenderer.h"
#import <QuartzCore/CAMetalLayer.h>
#import <QuartzCore/CADisplayLink.h>   // macOS 14+: replaces CVDisplayLink
// CADisplayLink fires directly on the main run loop — no dispatch_async needed.

static NSString *TopicDocumentation(MetalDemoTopic topic)
{
    switch (topic)
    {
        case MetalDemoTopicResourceMemory:
            return @"原理:\n资源与内存模式决定 CPU/GPU 访问路径与带宽成本。\n\n实现:\n按 drawable 尺寸重建 scene/depth/post 纹理，并保持中间纹理复用。\n\n常见坑:\n每帧创建纹理、MSAA 与 resolve 尺寸不一致、depth 格式不匹配。\n\n性能建议:\n只在尺寸变化时重建；中间纹理优先 Private；统计显存峰值。";
        case MetalDemoTopicArgumentBuffer:
            return @"原理:\nArgument Buffer 将纹理/采样器集中绑定，减少离散 setTexture 调用。\n\n实现:\nCPU 使用 argumentEncoder 写入材质纹理，渲染时统一绑定 buffer index。\n\n常见坑:\nbuffer index 与 shader 声明不一致，资源 id 映射错误。\n\n性能建议:\n批量材质预编码，按材质组提交 draw，减少 CPU 绑定开销。";
        case MetalDemoTopicFunctionConstants:
            return @"原理:\nFunction Constants 在编译期裁剪分支，生成多个高效 pipeline 变体。\n\n实现:\n同一 scene_fragment 生成 base/PBR/shadow/AB 四条 pipeline。\n\n常见坑:\n将运行时频繁变化参数放入 function constants 导致变体爆炸。\n\n性能建议:\n只将低频开关做成常量，高频参数仍使用 uniform。";
        case MetalDemoTopicIndirectCommandBuffer:
            return @"原理:\nICB 先录制 draw 命令，再由 render encoder 执行，降低 CPU 编码压力。\n\n实现:\n初始化预录制 drawIndexed，运行时 executeCommandsInBuffer。\n\n常见坑:\n每帧重录 ICB、继承状态配置不完整导致执行异常。\n\n性能建议:\n预录制稳定命令，动态内容拆分为少量可更新段。";
        case MetalDemoTopicParallelEncoding:
            return @"原理:\nParallel Encoder 允许多线程并行编码渲染命令。\n\n实现:\n主题 5 走 parallelRenderCommandEncoder 路径。\n\n常见坑:\n任务粒度过细导致线程调度成本高于收益。\n\n性能建议:\n只在多对象、多材质场景启用并行编码。";
        case MetalDemoTopicDeferredLike:
            return @"原理:\nDeferred 风格强调先产出中间结果，再做光照/后处理组合。\n\n实现:\nscene resolve 后执行 edge compute，再进入 post 合成。\n\n常见坑:\n中间纹理过多导致显存压力，pass 顺序依赖错误。\n\n性能建议:\n压缩中间缓冲分辨率，尽量复用纹理并减少读写回合。";
        case MetalDemoTopicShadowing:
            return @"原理:\n阴影本质是可见性问题，常用 shadow map 或屏幕空间近似。\n\n实现:\n使用 shadow 变体调制片元亮度，展示阴影因子作用。\n\n常见坑:\n偏移参数不当导致 acne 或 peter-panning。\n\n性能建议:\n先用低分辨率阴影贴图验证，再逐步提升质量。";
        case MetalDemoTopicPBR:
            return @"原理:\nPBR 使用能量守恒 BRDF（GGX + Fresnel + Geometry）。\n\n实现:\nscene_fragment 中计算 Cook-Torrance 镜面项与漫反射项。\n\n常见坑:\nroughness/metallic 范围错误，曝光叠加造成过曝。\n\n性能建议:\n预积分 LUT 与材质参数打包可显著降 ALU 成本。";
        case MetalDemoTopicHDRBloomTAA:
            return @"原理:\nHDR 下先提取亮部并模糊，再做 tone mapping 与时域混合。\n\n实现:\nbright_extract -> blur(H/V) -> post 中 exposure + temporal blend。\n\n常见坑:\n阈值过低导致整屏发光，temporal 过高导致拖影。\n\n性能建议:\nBloom 在半分辨率执行，历史混合按运动幅度自适应。";
        case MetalDemoTopicComputeParticles:
            return @"原理:\nCompute 并行生成粒子叠加图，再与场景合成。\n\n实现:\nparticle_overlay_kernel 每帧更新 particleTexture。\n\n常见坑:\n线程组尺寸不合理、粒子层数过高导致 fill-rate 紧张。\n\n性能建议:\n控制粒子密度，分辨率与层数按设备能力分档。";
        case MetalDemoTopicTextureAdvanced:
            return @"原理:\nmipmap 与各向异性采样提升斜角纹理稳定性。\n\n实现:\n初始化生成 mipmap，主题 11 切换 maxAnisotropy sampler。\n\n常见坑:\n忘记生成 mipmap 或采样器过滤模式与用途不匹配。\n\n性能建议:\n仅在需要的材质上开启高 anisotropy，避免全局拉满。";
        case MetalDemoTopicSyncAndScheduling:
            return @"原理:\n帧同步控制 CPU/GPU 在飞帧数，避免积压与阻塞。\n\n实现:\nin-flight semaphore + shared event signal（非阻塞）。\n\n常见坑:\n主线程 waitUntilScheduled/Completed 导致 UI 卡住。\n\n性能建议:\n保持 2~3 帧在飞，使用 completed handler 回收资源。";
        case MetalDemoTopicRayTracing:
            return @"原理:\n先做设备能力探测，再按能力启用或回退效果。\n\n实现:\nsupportsRaytracing 决定参数与视觉路径强度。\n\n常见坑:\n未做 capability check 直接启用高级路径引发兼容问题。\n\n性能建议:\n定义明确的降级矩阵，保持所有设备可运行。";
        case MetalDemoTopicMetalFXLike:
            return @"原理:\n低分辨率处理 + 上采样可降低成本并保持可接受清晰度。\n\n实现:\ndownsample_half + upscale_linear，再进入 post 合成。\n\n常见坑:\n锐化或 temporal 叠加过强造成振铃与鬼影。\n\n性能建议:\n优先做稳定性，再调锐度；分辨率比例按目标帧率调度。";
        case MetalDemoTopicProfiling:
            return @"原理:\n通过 Debug Group 与 GPU Capture 定位热点阶段。\n\n实现:\n关键 pass 打标，观察 Scene/Compute/Post 的耗时占比。\n\n常见坑:\n没有分阶段标记，导致性能瓶颈难以归因。\n\n性能建议:\n先定位最大热点，再做单点优化并复测。";
    }

    return @"暂无说明。";
}

static NSTextField *MakeHUDLabel(NSRect frame, CGFloat fontSize, NSColor *color, BOOL bold)
{
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.bezeled = NO;
    label.editable = NO;
    label.selectable = NO;
    label.drawsBackground = NO;
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.usesSingleLineMode = NO;
    label.font = bold ? [NSFont monospacedSystemFontOfSize:fontSize weight:NSFontWeightSemibold]
                      : [NSFont monospacedSystemFontOfSize:fontSize weight:NSFontWeightRegular];
    return label;
}

typedef NS_ENUM(NSInteger, DemoRenderBackend)
{
    DemoRenderBackendMetal = 0,
    DemoRenderBackendOpenGLTriangle = 1,
    DemoRenderBackendOpenGLCube = 2
};

@interface MetalView : NSView
@property (nonatomic, weak) id keyEventTarget;
@end

@implementation MetalView

- (CALayer *)makeBackingLayer
{
    return [CAMetalLayer layer];
}

- (BOOL)wantsUpdateLayer
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)keyDown:(NSEvent *)event
{
    if (_keyEventTarget && [_keyEventTarget respondsToSelector:@selector(handleDemoKeyEvent:)])
    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [_keyEventTarget performSelector:@selector(handleDemoKeyEvent:) withObject:event];
#pragma clang diagnostic pop
        return;
    }

    [super keyDown:event];
}

@end

@interface OpenGLView : NSOpenGLView
@property (nonatomic, weak) id keyEventTarget;
@end

@implementation OpenGLView

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)keyDown:(NSEvent *)event
{
    if (_keyEventTarget && [_keyEventTarget respondsToSelector:@selector(handleDemoKeyEvent:)])
    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [_keyEventTarget performSelector:@selector(handleDemoKeyEvent:) withObject:event];
#pragma clang diagnostic pop
        return;
    }

    [super keyDown:event];
}

@end

@interface AppDelegate ()
{
    NSWindow *_window;
    NSView *_contentRootView;
    MetalView *_metalView;
    OpenGLView *_openGLView;
    Renderer *_renderer;
    OpenGLRenderer *_openGLRenderer;
    DemoRenderBackend _activeBackend;
    CADisplayLink *_displayLink;     // macOS 14+ replacement for CVDisplayLink
    NSMutableString *_topicInputBuffer;
    NSTimer *_topicInputTimer;

    NSVisualEffectView *_runtimePanel;
    NSTextField *_metricsLabel;
    NSTextField *_parameterLabel;
    NSTextField *_errorHintLabel;
    NSSlider *_timeScaleSlider;
    NSSlider *_edgeGainSlider;
    NSSlider *_exposureGainSlider;
    NSSlider *_topic9ThresholdASlider;
    NSSlider *_topic9ThresholdBSlider;
    NSSlider *_topic9BlurPassSlider;
    NSTextField *_timeScaleValueLabel;
    NSTextField *_edgeGainValueLabel;
    NSTextField *_exposureGainValueLabel;
    NSTextField *_topic9ThresholdAValueLabel;
    NSTextField *_topic9ThresholdBValueLabel;
    NSTextField *_topic9BlurPassValueLabel;
    NSSegmentedControl *_backendSegmentedControl;
    NSButton *_errorToggleButton;

    NSWindow *_docWindow;
    NSTextView *_docTextView;

    NSMenuItem *_errorMenuItem;
    NSMenuItem *_docMenuItem;
    NSMenuItem *_metalBackendMenuItem;
    NSMenuItem *_openGLTriangleBackendMenuItem;
    NSMenuItem *_openGLCubeBackendMenuItem;

    // Perf: cache last drawable size to skip redundant CALayer property writes.
    CGSize _lastDrawableSize;
    // Perf: throttle HUD NSTextField updates to ~5fps instead of 60fps.
    NSUInteger _hudRefreshCounter;
}

- (BOOL)startDisplayLink;
- (void)stopDisplayLink;
- (void)handleDisplayLink:(CADisplayLink *)displayLink;
- (void)drawFrame;
- (void)installDemoMenu;
- (void)updateWindowTitle;
- (void)switchToTopic:(MetalDemoTopic)topic;
- (void)commitTopicBuffer;
- (void)handleDemoKeyEvent:(NSEvent *)event;
- (void)selectDemoTopicFromMenu:(NSMenuItem *)sender;
- (void)installRuntimePanel;
- (void)installDocumentationWindow;
- (void)refreshRuntimePanel;
- (void)applyUserParametersFromPanel;
- (void)updateDocumentationPage;
- (void)handleParameterSliderChanged:(id)sender;
- (void)toggleErrorExample:(id)sender;
- (void)toggleDocumentationWindow:(id)sender;
- (void)selectRenderBackendFromPanel:(id)sender;
- (void)selectMetalBackend:(id)sender;
- (void)selectOpenGLTriangleBackend:(id)sender;
- (void)selectOpenGLCubeBackend:(id)sender;
- (void)switchRenderBackend:(DemoRenderBackend)backend;
- (void)applyBackendControlState;
- (NSView *)activeRenderView;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    (void)notification;
    NSRect frame = NSMakeRect(100, 100, 800, 600);

    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:(NSWindowStyleMaskTitled |
                                                     NSWindowStyleMaskClosable |
                                                     NSWindowStyleMaskResizable)
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setTitle:@"Metal CMake Advanced Demo"];
    [_window setRestorable:NO];

    _contentRootView = [[NSView alloc] initWithFrame:frame];
    _contentRootView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_window setContentView:_contentRootView];

    _metalView = [[MetalView alloc] initWithFrame:_contentRootView.bounds];
    _metalView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _metalView.keyEventTarget = self;
    [_metalView setWantsLayer:YES];
    [_contentRootView addSubview:_metalView];

    NSOpenGLPixelFormatAttribute attrs[] = {
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFAAlphaSize, 8,
        NSOpenGLPFADepthSize, 24,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAAccelerated,
        0
    };

    NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    if (!pixelFormat)
    {
        NSLog(@"Failed to create NSOpenGLPixelFormat. OpenGL backend disabled.");
    }
    else
    {
        _openGLView = [[OpenGLView alloc] initWithFrame:_contentRootView.bounds pixelFormat:pixelFormat];
        _openGLView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _openGLView.keyEventTarget = self;
        _openGLView.wantsBestResolutionOpenGLSurface = YES;
        _openGLView.hidden = YES;
        [_contentRootView addSubview:_openGLView];

        GLint swapInterval = 1;
        [_openGLView.openGLContext setValues:&swapInterval forParameter:NSOpenGLContextParameterSwapInterval];

        _openGLRenderer = [[OpenGLRenderer alloc] initWithOpenGLView:_openGLView];
        if (![_openGLRenderer isReady])
        {
            NSLog(@"OpenGL renderer initialization failed. OpenGL backend disabled.");
            _openGLRenderer = nil;
            [_openGLView removeFromSuperview];
            _openGLView = nil;
        }
    }

    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_metalView];

    if (![_metalView.layer isKindOfClass:[CAMetalLayer class]])
    {
        NSLog(@"MetalView backing layer is not CAMetalLayer.");
        [NSApp terminate:nil];
        return;
    }

    CAMetalLayer *metalLayer = (CAMetalLayer *)_metalView.layer;
    metalLayer.frame = _metalView.bounds;
    metalLayer.contentsScale = [_window backingScaleFactor];
    metalLayer.drawableSize = CGSizeMake(_metalView.bounds.size.width * metalLayer.contentsScale,
                                         _metalView.bounds.size.height * metalLayer.contentsScale);

    _renderer = [[Renderer alloc] initWithLayer:metalLayer];
    if (!_renderer)
    {
        NSLog(@"Renderer initialization failed.");
        [NSApp terminate:nil];
        return;
    }

    _activeBackend = DemoRenderBackendMetal;
    _topicInputBuffer = [NSMutableString string];
    [self switchToTopic:MetalDemoTopicResourceMemory];
    [self installDemoMenu];
    [self installRuntimePanel];
    [self installDocumentationWindow];
    [self applyUserParametersFromPanel];
    [self switchRenderBackend:DemoRenderBackendMetal];
    [self refreshRuntimePanel];
    [self updateDocumentationPage];

    if (![self startDisplayLink])
    {
        NSLog(@"Failed to start CADisplayLink.");
        [NSApp terminate:nil];
        return;
    }
}

- (void)installDemoMenu
{
    NSMenu *mainMenu = NSApp.mainMenu;
    if (!mainMenu)
    {
        mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];
        NSApp.mainMenu = mainMenu;
    }

    NSMenuItem *demoMenuItem = [[NSMenuItem alloc] initWithTitle:@"Demo" action:nil keyEquivalent:@""];
    NSMenu *demoMenu = [[NSMenu alloc] initWithTitle:@"Demo"];
    demoMenuItem.submenu = demoMenu;
    [mainMenu addItem:demoMenuItem];

    NSArray<NSString *> *titles = [Renderer allDemoTopicTitles];
    for (NSInteger i = 0; i < (NSInteger)titles.count; ++i)
    {
        NSInteger topicValue = i + 1;
        NSString *title = [NSString stringWithFormat:@"%ld. %@", (long)topicValue, titles[i]];
        NSString *key = topicValue <= 9 ? [NSString stringWithFormat:@"%ld", (long)topicValue] : @"";

        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(selectDemoTopicFromMenu:)
                                               keyEquivalent:key];
        item.target = self;
        item.tag = topicValue;
        [demoMenu addItem:item];
    }

    [demoMenu addItem:[NSMenuItem separatorItem]];

    _errorMenuItem = [[NSMenuItem alloc] initWithTitle:@"错误示例开关 (E)"
                                                action:@selector(toggleErrorExample:)
                                         keyEquivalent:@"e"];
    _errorMenuItem.target = self;
    _errorMenuItem.state = NSControlStateValueOff;
    [demoMenu addItem:_errorMenuItem];

    _docMenuItem = [[NSMenuItem alloc] initWithTitle:@"显示/隐藏说明页 (H)"
                                              action:@selector(toggleDocumentationWindow:)
                                       keyEquivalent:@"h"];
    _docMenuItem.target = self;
    _docMenuItem.state = NSControlStateValueOn;
    [demoMenu addItem:_docMenuItem];

    NSMenuItem *rendererMenuItem = [[NSMenuItem alloc] initWithTitle:@"Renderer" action:nil keyEquivalent:@""];
    NSMenu *rendererMenu = [[NSMenu alloc] initWithTitle:@"Renderer"];
    rendererMenuItem.submenu = rendererMenu;
    [mainMenu addItem:rendererMenuItem];

    _metalBackendMenuItem = [[NSMenuItem alloc] initWithTitle:@"Metal 渲染 (M)"
                                                       action:@selector(selectMetalBackend:)
                                                keyEquivalent:@"m"];
    _metalBackendMenuItem.target = self;
    [rendererMenu addItem:_metalBackendMenuItem];

        _openGLTriangleBackendMenuItem = [[NSMenuItem alloc] initWithTitle:@"OpenGL 三角形渲染 (O)"
                                         action:@selector(selectOpenGLTriangleBackend:)
                                     keyEquivalent:@"o"];
        _openGLTriangleBackendMenuItem.target = self;
        _openGLTriangleBackendMenuItem.enabled = (_openGLRenderer != nil);
        [rendererMenu addItem:_openGLTriangleBackendMenuItem];

        _openGLCubeBackendMenuItem = [[NSMenuItem alloc] initWithTitle:@"OpenGL 立方体渲染 (P)"
                                        action:@selector(selectOpenGLCubeBackend:)
                                    keyEquivalent:@"p"];
        _openGLCubeBackendMenuItem.target = self;
        _openGLCubeBackendMenuItem.enabled = (_openGLRenderer != nil);
        [rendererMenu addItem:_openGLCubeBackendMenuItem];

    [self applyBackendControlState];
}

- (void)updateWindowTitle
{
    NSString *title;
    if (_activeBackend == DemoRenderBackendMetal)
    {
        title = [NSString stringWithFormat:@"Metal Learning Demo - %ld. %@",
                 (long)_renderer.demoTopic,
                 [_renderer demoTopicTitle]];
    }
    else
    {
        MetalDemoTopic topic = _openGLRenderer ? [_openGLRenderer demoTopic] : _renderer.demoTopic;
        NSString *topicTitle = _openGLRenderer ? [_openGLRenderer demoTopicTitle] : _renderer.demoTopicTitle;
        NSString *modeTitle = _openGLRenderer ? [_openGLRenderer renderModeTitle] : @"OpenGL";
        title = [NSString stringWithFormat:@"%@ - 预选主题 %ld. %@",
                 modeTitle,
                 (long)topic,
                 topicTitle];
    }
    [_window setTitle:title];
}

- (void)switchToTopic:(MetalDemoTopic)topic
{
    if (topic < MetalDemoTopicResourceMemory || topic > MetalDemoTopicProfiling)
    {
        return;
    }

    [_renderer setDemoTopic:topic];
    if (_openGLRenderer)
    {
        [_openGLRenderer setDemoTopic:topic];
    }
    [self updateWindowTitle];
    [self updateDocumentationPage];
    [self refreshRuntimePanel];
}

- (void)installRuntimePanel
{
    if (_runtimePanel)
    {
        return;
    }

    NSRect frame = NSMakeRect(14, 14, 370, 468);
    _runtimePanel = [[NSVisualEffectView alloc] initWithFrame:frame];
    _runtimePanel.material = NSVisualEffectMaterialHUDWindow;
    _runtimePanel.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    _runtimePanel.state = NSVisualEffectStateActive;
    _runtimePanel.wantsLayer = YES;
    _runtimePanel.layer.cornerRadius = 10.0;
    _runtimePanel.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;

    NSTextField *title = MakeHUDLabel(NSMakeRect(12, 438, 346, 20), 12.0, NSColor.whiteColor, YES);
    title.stringValue = @"实时参数面板";
    [_runtimePanel addSubview:title];

    _backendSegmentedControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(140, 436, 218, 22)];
    [_backendSegmentedControl setSegmentCount:3];
    [_backendSegmentedControl setLabel:@"Metal" forSegment:0];
    [_backendSegmentedControl setLabel:@"GL三角" forSegment:1];
    [_backendSegmentedControl setLabel:@"GL立方" forSegment:2];
    _backendSegmentedControl.selectedSegment = 0;
    _backendSegmentedControl.target = self;
    _backendSegmentedControl.action = @selector(selectRenderBackendFromPanel:);
    [_runtimePanel addSubview:_backendSegmentedControl];

    _metricsLabel = MakeHUDLabel(NSMakeRect(12, 366, 346, 62), 11.0, NSColor.whiteColor, NO);
    [_runtimePanel addSubview:_metricsLabel];

    _parameterLabel = MakeHUDLabel(NSMakeRect(12, 302, 346, 60), 11.0, [NSColor colorWithWhite:0.92 alpha:1.0], NO);
    [_runtimePanel addSubview:_parameterLabel];

    NSTextField *timeLabel = MakeHUDLabel(NSMakeRect(12, 288, 170, 16), 11.0, [NSColor colorWithWhite:0.9 alpha:1.0], NO);
    timeLabel.stringValue = @"时间倍率";
    [_runtimePanel addSubview:timeLabel];

    _timeScaleValueLabel = MakeHUDLabel(NSMakeRect(300, 288, 58, 16), 11.0, NSColor.whiteColor, NO);
    _timeScaleValueLabel.alignment = NSTextAlignmentRight;
    [_runtimePanel addSubview:_timeScaleValueLabel];

    _timeScaleSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(12, 267, 346, 20)];
    _timeScaleSlider.minValue = 0.5;
    _timeScaleSlider.maxValue = 2.0;
    _timeScaleSlider.doubleValue = 1.0;
    _timeScaleSlider.target = self;
    _timeScaleSlider.action = @selector(handleParameterSliderChanged:);
    [_runtimePanel addSubview:_timeScaleSlider];

    NSTextField *edgeLabel = MakeHUDLabel(NSMakeRect(12, 247, 170, 16), 11.0, [NSColor colorWithWhite:0.9 alpha:1.0], NO);
    edgeLabel.stringValue = @"边缘强度倍率";
    [_runtimePanel addSubview:edgeLabel];

    _edgeGainValueLabel = MakeHUDLabel(NSMakeRect(300, 247, 58, 16), 11.0, NSColor.whiteColor, NO);
    _edgeGainValueLabel.alignment = NSTextAlignmentRight;
    [_runtimePanel addSubview:_edgeGainValueLabel];

    _edgeGainSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(12, 226, 346, 20)];
    _edgeGainSlider.minValue = 0.5;
    _edgeGainSlider.maxValue = 2.5;
    _edgeGainSlider.doubleValue = 1.0;
    _edgeGainSlider.target = self;
    _edgeGainSlider.action = @selector(handleParameterSliderChanged:);
    [_runtimePanel addSubview:_edgeGainSlider];

    NSTextField *exposureLabel = MakeHUDLabel(NSMakeRect(12, 206, 170, 16), 11.0, [NSColor colorWithWhite:0.9 alpha:1.0], NO);
    exposureLabel.stringValue = @"曝光倍率";
    [_runtimePanel addSubview:exposureLabel];

    _exposureGainValueLabel = MakeHUDLabel(NSMakeRect(300, 206, 58, 16), 11.0, NSColor.whiteColor, NO);
    _exposureGainValueLabel.alignment = NSTextAlignmentRight;
    [_runtimePanel addSubview:_exposureGainValueLabel];

    _exposureGainSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(12, 185, 346, 20)];
    _exposureGainSlider.minValue = 0.5;
    _exposureGainSlider.maxValue = 2.5;
    _exposureGainSlider.doubleValue = 1.0;
    _exposureGainSlider.target = self;
    _exposureGainSlider.action = @selector(handleParameterSliderChanged:);
    [_runtimePanel addSubview:_exposureGainSlider];

    NSTextField *thresholdALabel = MakeHUDLabel(NSMakeRect(12, 165, 170, 16), 11.0, [NSColor colorWithWhite:0.9 alpha:1.0], NO);
    thresholdALabel.stringValue = @"Topic9 Bloom 阈值A";
    [_runtimePanel addSubview:thresholdALabel];

    _topic9ThresholdAValueLabel = MakeHUDLabel(NSMakeRect(300, 165, 58, 16), 11.0, NSColor.whiteColor, NO);
    _topic9ThresholdAValueLabel.alignment = NSTextAlignmentRight;
    [_runtimePanel addSubview:_topic9ThresholdAValueLabel];

    _topic9ThresholdASlider = [[NSSlider alloc] initWithFrame:NSMakeRect(12, 144, 346, 20)];
    _topic9ThresholdASlider.minValue = 0.20;
    _topic9ThresholdASlider.maxValue = 1.60;
    _topic9ThresholdASlider.doubleValue = 0.56;
    _topic9ThresholdASlider.target = self;
    _topic9ThresholdASlider.action = @selector(handleParameterSliderChanged:);
    [_runtimePanel addSubview:_topic9ThresholdASlider];

    NSTextField *thresholdBLabel = MakeHUDLabel(NSMakeRect(12, 124, 170, 16), 11.0, [NSColor colorWithWhite:0.9 alpha:1.0], NO);
    thresholdBLabel.stringValue = @"Topic9 Bloom 阈值B";
    [_runtimePanel addSubview:thresholdBLabel];

    _topic9ThresholdBValueLabel = MakeHUDLabel(NSMakeRect(300, 124, 58, 16), 11.0, NSColor.whiteColor, NO);
    _topic9ThresholdBValueLabel.alignment = NSTextAlignmentRight;
    [_runtimePanel addSubview:_topic9ThresholdBValueLabel];

    _topic9ThresholdBSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(12, 103, 346, 20)];
    _topic9ThresholdBSlider.minValue = 0.30;
    _topic9ThresholdBSlider.maxValue = 2.20;
    _topic9ThresholdBSlider.doubleValue = 0.88;
    _topic9ThresholdBSlider.target = self;
    _topic9ThresholdBSlider.action = @selector(handleParameterSliderChanged:);
    [_runtimePanel addSubview:_topic9ThresholdBSlider];

    NSTextField *blurPassLabel = MakeHUDLabel(NSMakeRect(12, 83, 170, 16), 11.0, [NSColor colorWithWhite:0.9 alpha:1.0], NO);
    blurPassLabel.stringValue = @"Topic9 Blur Pass";
    [_runtimePanel addSubview:blurPassLabel];

    _topic9BlurPassValueLabel = MakeHUDLabel(NSMakeRect(300, 83, 58, 16), 11.0, NSColor.whiteColor, NO);
    _topic9BlurPassValueLabel.alignment = NSTextAlignmentRight;
    [_runtimePanel addSubview:_topic9BlurPassValueLabel];

    _topic9BlurPassSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(12, 62, 346, 20)];
    _topic9BlurPassSlider.minValue = 2.0;
    _topic9BlurPassSlider.maxValue = 16.0;
    _topic9BlurPassSlider.doubleValue = 6.0;
    _topic9BlurPassSlider.target = self;
    _topic9BlurPassSlider.action = @selector(handleParameterSliderChanged:);
    [_runtimePanel addSubview:_topic9BlurPassSlider];

    _errorToggleButton = [[NSButton alloc] initWithFrame:NSMakeRect(12, 36, 220, 20)];
    _errorToggleButton.buttonType = NSButtonTypeSwitch;
    _errorToggleButton.title = @"错误示例开关 (E)";
    _errorToggleButton.state = NSControlStateValueOff;
    _errorToggleButton.target = self;
    _errorToggleButton.action = @selector(toggleErrorExample:);
    [_runtimePanel addSubview:_errorToggleButton];

    _errorHintLabel = MakeHUDLabel(NSMakeRect(12, 8, 346, 24), 10.5, [NSColor colorWithRed:1.0 green:0.84 blue:0.35 alpha:1.0], NO);
    [_runtimePanel addSubview:_errorHintLabel];

    [_contentRootView addSubview:_runtimePanel];
}

- (void)installDocumentationWindow
{
    if (_docWindow)
    {
        return;
    }

    _docWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(940, 120, 500, 580)
                                             styleMask:(NSWindowStyleMaskTitled |
                                                        NSWindowStyleMaskClosable |
                                                        NSWindowStyleMaskResizable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    _docWindow.releasedWhenClosed = NO;
    [_docWindow setTitle:@"场景说明页"];

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:_docWindow.contentView.bounds];
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;

    _docTextView = [[NSTextView alloc] initWithFrame:scrollView.contentView.bounds];
    _docTextView.editable = NO;
    _docTextView.selectable = YES;
    _docTextView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _docTextView.textColor = [NSColor textColor];
    _docTextView.backgroundColor = [NSColor colorWithWhite:0.98 alpha:1.0];
    _docTextView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [scrollView setDocumentView:_docTextView];

    [_docWindow.contentView addSubview:scrollView];
    [_docWindow orderFront:nil];
}

- (void)applyUserParametersFromPanel
{
    [_renderer setUserParameterTimeScale:(float)_timeScaleSlider.doubleValue
                                edgeGain:(float)_edgeGainSlider.doubleValue
                            exposureGain:(float)_exposureGainSlider.doubleValue];
    if (_openGLRenderer)
    {
        [_openGLRenderer setUserParameterTimeScale:(float)_timeScaleSlider.doubleValue
                                          edgeGain:(float)_edgeGainSlider.doubleValue
                                      exposureGain:(float)_exposureGainSlider.doubleValue];
        [_openGLRenderer setTopic9BloomThresholdA:(float)_topic9ThresholdASlider.doubleValue
                                       thresholdB:(float)_topic9ThresholdBSlider.doubleValue
                                    blurPassCount:(NSInteger)(_topic9BlurPassSlider.doubleValue + 0.5)];
    }
}

- (void)refreshRuntimePanel
{
    _timeScaleValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", _timeScaleSlider.doubleValue];
    _edgeGainValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", _edgeGainSlider.doubleValue];
    _exposureGainValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", _exposureGainSlider.doubleValue];
    _topic9ThresholdAValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", _topic9ThresholdASlider.doubleValue];
    _topic9ThresholdBValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", _topic9ThresholdBSlider.doubleValue];
    _topic9BlurPassValueLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)(_topic9BlurPassSlider.doubleValue + 0.5)];

    if (_activeBackend == DemoRenderBackendMetal)
    {
        MetalDemoRuntimeStats stats = [_renderer runtimeStats];
        NSString *gpuText = stats.gpuFrameTimeMs >= 0.0
                            ? [NSString stringWithFormat:@"%.2f ms", stats.gpuFrameTimeMs]
                            : @"N/A";

        _metricsLabel.stringValue = [NSString stringWithFormat:@"主题 %ld: %@\nCPU 帧时: %.2f ms   GPU 帧时: %@\n显存占用: %.1f MB",
                                     (long)_renderer.demoTopic,
                                     _renderer.demoTopicTitle,
                                     stats.cpuFrameTimeMs,
                                     gpuText,
                                     stats.estimatedMemoryMB];

        _parameterLabel.stringValue = [NSString stringWithFormat:@"实时参数\nScene %@\nPost %@\nUpscale %@\nFallback %@",
                                       [_renderer scenePathSummary],
                                       [_renderer postPathSummary],
                                       [_renderer upscalePathSummary],
                                       [_renderer runtimeFallbackSummary]];

        _errorToggleButton.state = stats.errorExampleEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        _errorMenuItem.state = _errorToggleButton.state;
        if (stats.errorExampleEnabled)
        {
            _errorHintLabel.stringValue = [NSString stringWithFormat:@"错误示例: %@", [_renderer errorExampleSummary]];
        }
        else
        {
            _errorHintLabel.stringValue = @"错误示例: 已关闭。可按 E 快速切换。";
        }
    }
    else
    {
        OpenGLRuntimeStats stats = {0};
        if (_openGLRenderer)
        {
            stats = [_openGLRenderer runtimeStats];
        }

        MetalDemoTopic topic = _openGLRenderer ? [_openGLRenderer demoTopic] : _renderer.demoTopic;
        if (topic == MetalDemoTopicHDRBloomTAA && _openGLRenderer)
        {
            _topic9ThresholdASlider.doubleValue = stats.topic9ThresholdA;
            _topic9ThresholdBSlider.doubleValue = stats.topic9ThresholdB;
            _topic9BlurPassSlider.doubleValue = (double)stats.topic9BlurPassCount;
            _topic9ThresholdAValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", stats.topic9ThresholdA];
            _topic9ThresholdBValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", stats.topic9ThresholdB];
            _topic9BlurPassValueLabel.stringValue = [NSString stringWithFormat:@"%ld", (long)stats.topic9BlurPassCount];
        }

        NSString *title = _openGLRenderer ? [_openGLRenderer demoTopicTitle] : _renderer.demoTopicTitle;
        NSString *modeTitle = _openGLRenderer ? [_openGLRenderer renderModeTitle] : @"OpenGL";
        NSString *scenePath = _openGLRenderer ? [_openGLRenderer scenePathSummary] : @"OpenGL Scene";
        NSString *postPath = _openGLRenderer ? [_openGLRenderer postPathSummary] : @"Post";
        NSString *upscalePath = _openGLRenderer ? [_openGLRenderer upscalePathSummary] : @"Off";
        NSString *fallback = _openGLRenderer ? [_openGLRenderer runtimeFallbackSummary] : @"No";
        NSString *topicTuningText = @"";
        if (topic == MetalDemoTopicHDRBloomTAA)
        {
            topicTuningText = [NSString stringWithFormat:@"\nT9 Tune A %.2f B %.2f Blur %ld",
                               stats.topic9ThresholdA,
                               stats.topic9ThresholdB,
                               (long)stats.topic9BlurPassCount];
        }
        NSString *topicDetail = @"";
        if (topic == MetalDemoTopicShadowing)
        {
            topicDetail = [NSString stringWithFormat:@"\nT7 Bias %.4f  PCF %.1f", stats.shadowBias, stats.shadowPCFRadius];
        }
        else if (topic == MetalDemoTopicHDRBloomTAA)
        {
            topicDetail = [NSString stringWithFormat:@"\nT9 A %.2f  B %.2f  Blur %ld",
                           stats.topic9ThresholdA,
                           stats.topic9ThresholdB,
                           (long)stats.topic9BlurPassCount];
        }
        else if (topic == MetalDemoTopicProfiling)
        {
            topicDetail = [NSString stringWithFormat:@"\nT15 Zone %.2f / %.2f / %.2f",
                           stats.heatThreshold1,
                           stats.heatThreshold2,
                           stats.heatThreshold3];
        }

        _metricsLabel.stringValue = [NSString stringWithFormat:@"主题 %ld: %@\n模式: %@  CPU: %.2f ms  FPS: %.1f\nTime %.2f  Edge %.2f  Exp %.2f%@",
                                     (long)topic,
                                     title,
                         modeTitle,
                                     stats.cpuFrameTimeMs,
                                     stats.fpsEstimate,
                                     stats.timeScale,
                                     stats.edgeStrength,
                                     stats.exposure,
                                     topicDetail];

        _parameterLabel.stringValue = [NSString stringWithFormat:@"OpenGL 主题路径\nScene %@\nPost %@\nUpscale %@\nFallback %@%@",
                                       scenePath,
                                       postPath,
                                       upscalePath,
                           fallback,
                           topicTuningText];

        _errorToggleButton.state = stats.errorExampleEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        _errorMenuItem.state = _errorToggleButton.state;
        if (stats.errorExampleEnabled && _openGLRenderer)
        {
            _errorHintLabel.stringValue = [NSString stringWithFormat:@"错误示例: %@", [_openGLRenderer errorExampleSummary]];
        }
        else
        {
            _errorHintLabel.stringValue = @"错误示例: 已关闭。OpenGL 主题展示标准实现路径。";
        }
    }

    [self applyBackendControlState];
}

- (void)updateDocumentationPage
{
    if (!_docTextView)
    {
        return;
    }

    if (_activeBackend != DemoRenderBackendMetal)
    {
        MetalDemoTopic topic = _openGLRenderer ? [_openGLRenderer demoTopic] : _renderer.demoTopic;
        NSString *title = _openGLRenderer ? [_openGLRenderer demoTopicTitle] : _renderer.demoTopicTitle;
        NSString *modeTitle = _openGLRenderer ? [_openGLRenderer renderModeTitle] : @"OpenGL";
        NSString *doc = TopicDocumentation(topic);
        NSString *scenePath = _openGLRenderer ? [_openGLRenderer scenePathSummary] : @"OpenGL Scene";
        NSString *postPath = _openGLRenderer ? [_openGLRenderer postPathSummary] : @"Post";
        NSString *upscalePath = _openGLRenderer ? [_openGLRenderer upscalePathSummary] : @"Off";
        NSString *fallback = _openGLRenderer ? [_openGLRenderer runtimeFallbackSummary] : @"No";
        NSString *errorPart = (_openGLRenderer && [_openGLRenderer errorExampleEnabled])
                              ? [_openGLRenderer errorExampleSummary]
                              : @"错误示例关闭时显示 OpenGL 对应实现路径。";

        _docTextView.string = [NSString stringWithFormat:@"渲染后端: OpenGL\n模式: %@\n主题 %ld: %@\n\n对应渲染路径:\nScene %@\nPost %@\nUpscale %@\nFallback %@\n\n%@\n\n错误示例开关说明:\n%@\n\n快捷键:\nM 切到 Metal\nO 切到 OpenGL 三角形\nP 切到 OpenGL 立方体\nE 错误示例开关\nH 显示/隐藏说明页",
                       modeTitle,
                               (long)topic,
                               title,
                               scenePath,
                               postPath,
                               upscalePath,
                               fallback,
                               doc,
                               errorPart];
        [_docWindow setTitle:[NSString stringWithFormat:@"场景说明页 - OpenGL - %ld. %@",
                              (long)topic,
                              title]];
        return;
    }

    NSString *doc = TopicDocumentation(_renderer.demoTopic);
    NSString *errorPart = _renderer.errorExampleEnabled
                          ? [_renderer errorExampleSummary]
                          : @"错误示例关闭时显示标准实现路径。";
    _docTextView.string = [NSString stringWithFormat:@"主题 %ld: %@\n\n%@\n\n错误示例开关说明:\n%@\n\n快捷键:\nE 错误示例开关\nH 显示/隐藏说明页\nC 触发单帧 GPU Capture（写入 /tmp/MetalDemo_frame.gputrace）",
                           (long)_renderer.demoTopic,
                           _renderer.demoTopicTitle,
                           doc,
                           errorPart];
    [_docWindow setTitle:[NSString stringWithFormat:@"场景说明页 - %ld. %@",
                          (long)_renderer.demoTopic,
                          _renderer.demoTopicTitle]];
}

- (void)handleParameterSliderChanged:(id)sender
{
    (void)sender;
    [self applyUserParametersFromPanel];
    [self refreshRuntimePanel];
}

- (void)toggleErrorExample:(id)sender
{
    BOOL enabled;
    if ([sender isKindOfClass:[NSButton class]])
    {
        enabled = (((NSButton *)sender).state == NSControlStateValueOn);
    }
    else
    {
        BOOL currentEnabled = (_activeBackend == DemoRenderBackendMetal)
                            ? [_renderer errorExampleEnabled]
                            : (_openGLRenderer ? [_openGLRenderer errorExampleEnabled]
                                               : [_renderer errorExampleEnabled]);
        enabled = !currentEnabled;
    }

    [_renderer setErrorExampleEnabled:enabled];
    if (_openGLRenderer)
    {
        [_openGLRenderer setErrorExampleEnabled:enabled];
    }
    _errorToggleButton.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    _errorMenuItem.state = _errorToggleButton.state;
    [self updateDocumentationPage];
    [self refreshRuntimePanel];
    [_window makeFirstResponder:[self activeRenderView]];
}

- (void)toggleDocumentationWindow:(id)sender
{
    (void)sender;
    if (!_docWindow)
    {
        return;
    }

    if (_docWindow.isVisible)
    {
        [_docWindow orderOut:nil];
        _docMenuItem.state = NSControlStateValueOff;
    }
    else
    {
        [_docWindow orderFront:nil];
        _docMenuItem.state = NSControlStateValueOn;
    }
    [_window makeFirstResponder:[self activeRenderView]];
}

- (void)commitTopicBuffer
{
    if (_topicInputBuffer.length == 0)
    {
        return;
    }

    NSInteger value = _topicInputBuffer.integerValue;
    [_topicInputBuffer setString:@""];
    [_topicInputTimer invalidate];
    _topicInputTimer = nil;

    if (value >= 1 && value <= 15)
    {
        [self switchToTopic:(MetalDemoTopic)value];
    }
}

- (void)handleDemoKeyEvent:(NSEvent *)event
{
    NSString *characters = event.charactersIgnoringModifiers;
    if (characters.length == 0)
    {
        return;
    }

    unichar c = [characters characterAtIndex:0];
    if (c == 'm' || c == 'M')
    {
        [self switchRenderBackend:DemoRenderBackendMetal];
        return;
    }

    if (c == 'o' || c == 'O')
    {
        [self switchRenderBackend:DemoRenderBackendOpenGLTriangle];
        return;
    }

    if (c == 'p' || c == 'P')
    {
        [self switchRenderBackend:DemoRenderBackendOpenGLCube];
        return;
    }

    if (c == 'e' || c == 'E')
    {
        [self toggleErrorExample:nil];
        return;
    }

    if (c == 'h' || c == 'H')
    {
        [self toggleDocumentationWindow:nil];
        return;
    }

    if (c == 'c' || c == 'C')
    {
        if (_activeBackend == DemoRenderBackendMetal)
        {
            [_renderer requestOneFrameCapture];
        }
        return;
    }

    if (c >= '0' && c <= '9')
    {
        if (_topicInputBuffer.length == 0)
        {
            [_topicInputBuffer appendFormat:@"%c", c];

            // Fast path: 2..9 are single-digit topics, switch immediately.
            if (c >= '2' && c <= '9')
            {
                [self commitTopicBuffer];
                return;
            }

            // Topic 1 can also be a prefix of 10..15, so wait briefly for next digit.
            [_topicInputTimer invalidate];
            _topicInputTimer = [NSTimer scheduledTimerWithTimeInterval:0.24
                                                                 target:self
                                                               selector:@selector(commitTopicBuffer)
                                                               userInfo:nil
                                                                repeats:NO];
            return;
        }

        [_topicInputBuffer appendFormat:@"%c", c];
        if (_topicInputBuffer.length >= 2)
        {
            [self commitTopicBuffer];
            return;
        }
        return;
    }

    if (c == 0x0d || c == 0x03)
    {
        [self commitTopicBuffer];
        return;
    }

    if (c == 0x1b)
    {
        [_topicInputBuffer setString:@""];
        [_topicInputTimer invalidate];
        _topicInputTimer = nil;
        return;
    }
}

- (void)selectDemoTopicFromMenu:(NSMenuItem *)sender
{
    NSInteger topic = sender.tag;
    [self switchToTopic:(MetalDemoTopic)topic];
}

- (BOOL)startDisplayLink
{
    if (_displayLink)
    {
        return YES;
    }

    // On macOS, CADisplayLink must be created via NSScreen (available since macOS 12).
    // This correctly ties the link to the display the window is on.
    NSScreen *screen = _window.screen ?: [NSScreen mainScreen];
    _displayLink = [screen displayLinkWithTarget:self
                                        selector:@selector(handleDisplayLink:)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                       forMode:NSRunLoopCommonModes];
    return (_displayLink != nil);
}

- (void)stopDisplayLink
{
    [_displayLink invalidate];
    _displayLink = nil;
}

- (void)handleDisplayLink:(CADisplayLink *)displayLink
{
    (void)displayLink;
    [self drawFrame];
}

- (void)drawFrame
{
    if (_activeBackend != DemoRenderBackendMetal)
    {
        if (_openGLRenderer)
        {
            [_openGLRenderer render];
        }

        if (++_hudRefreshCounter >= 12)
        {
            _hudRefreshCounter = 0;
            [self refreshRuntimePanel];
        }
        return;
    }

    if (![_metalView.layer isKindOfClass:[CAMetalLayer class]])
    {
        return;
    }

    CAMetalLayer *metalLayer = (CAMetalLayer *)_metalView.layer;
    metalLayer.frame = _metalView.bounds;
    CGFloat scale = [_window backingScaleFactor];
    metalLayer.contentsScale = scale;
    // Only update drawableSize when the window actually resizes — avoids a
    // CALayer property write and potential implicit synchronization every frame.
    CGSize newDrawableSize = CGSizeMake(_metalView.bounds.size.width  * scale,
                                        _metalView.bounds.size.height * scale);
    if (!CGSizeEqualToSize(newDrawableSize, _lastDrawableSize))
    {
        metalLayer.drawableSize = newDrawableSize;
        _lastDrawableSize = newDrawableSize;
    }
    [_renderer render];

    // Throttle HUD refresh to ~5 fps; interactive changes call refreshRuntimePanel directly.
    if (++_hudRefreshCounter >= 12)
    {
        _hudRefreshCounter = 0;
        [self refreshRuntimePanel];
    }
}

- (NSView *)activeRenderView
{
    if (_activeBackend != DemoRenderBackendMetal && _openGLView)
    {
        return _openGLView;
    }
    return _metalView;
}

- (void)applyBackendControlState
{
    BOOL isMetal = (_activeBackend == DemoRenderBackendMetal);

    _backendSegmentedControl.enabled = (_openGLRenderer != nil);
    if (isMetal)
    {
        _backendSegmentedControl.selectedSegment = 0;
    }
    else if (_activeBackend == DemoRenderBackendOpenGLCube)
    {
        _backendSegmentedControl.selectedSegment = 2;
    }
    else
    {
        _backendSegmentedControl.selectedSegment = 1;
    }

    _metalBackendMenuItem.state = isMetal ? NSControlStateValueOn : NSControlStateValueOff;
    _openGLTriangleBackendMenuItem.state = (_activeBackend == DemoRenderBackendOpenGLTriangle) ? NSControlStateValueOn : NSControlStateValueOff;
    _openGLCubeBackendMenuItem.state = (_activeBackend == DemoRenderBackendOpenGLCube) ? NSControlStateValueOn : NSControlStateValueOff;
    _openGLTriangleBackendMenuItem.enabled = (_openGLRenderer != nil);
    _openGLCubeBackendMenuItem.enabled = (_openGLRenderer != nil);

    _timeScaleSlider.enabled = YES;
    _edgeGainSlider.enabled = YES;
    _exposureGainSlider.enabled = YES;

    BOOL topic9TuningEnabled = (_activeBackend != DemoRenderBackendMetal) &&
                               (_openGLRenderer != nil) &&
                               ([_openGLRenderer renderMode] == OpenGLRenderModeCube) &&
                               ([_openGLRenderer demoTopic] == MetalDemoTopicHDRBloomTAA);
    _topic9ThresholdASlider.enabled = topic9TuningEnabled;
    _topic9ThresholdBSlider.enabled = topic9TuningEnabled;
    _topic9BlurPassSlider.enabled = topic9TuningEnabled;

    _errorToggleButton.enabled = YES;
    _errorMenuItem.enabled = YES;
}

- (void)switchRenderBackend:(DemoRenderBackend)backend
{
    if (backend != DemoRenderBackendMetal && !_openGLRenderer)
    {
        NSBeep();
        backend = DemoRenderBackendMetal;
    }

    if (_openGLRenderer)
    {
        OpenGLRenderMode mode = (backend == DemoRenderBackendOpenGLCube)
                              ? OpenGLRenderModeCube
                              : OpenGLRenderModeTriangle;
        [_openGLRenderer setRenderMode:mode];
    }

    _activeBackend = backend;
    BOOL isMetal = (_activeBackend == DemoRenderBackendMetal);
    _metalView.hidden = !isMetal;
    _openGLView.hidden = isMetal;
    _lastDrawableSize = CGSizeZero;

    [self applyBackendControlState];
    [self updateWindowTitle];
    [self updateDocumentationPage];
    [self refreshRuntimePanel];
    [_window makeFirstResponder:[self activeRenderView]];
}

- (void)selectRenderBackendFromPanel:(id)sender
{
    (void)sender;
    NSInteger selected = _backendSegmentedControl.selectedSegment;
    if (selected == 0)
    {
        [self switchRenderBackend:DemoRenderBackendMetal];
    }
    else if (selected == 2)
    {
        [self switchRenderBackend:DemoRenderBackendOpenGLCube];
    }
    else
    {
        [self switchRenderBackend:DemoRenderBackendOpenGLTriangle];
    }
}

- (void)selectMetalBackend:(id)sender
{
    (void)sender;
    [self switchRenderBackend:DemoRenderBackendMetal];
}

- (void)selectOpenGLTriangleBackend:(id)sender
{
    (void)sender;
    [self switchRenderBackend:DemoRenderBackendOpenGLTriangle];
}

- (void)selectOpenGLCubeBackend:(id)sender
{
    (void)sender;
    [self switchRenderBackend:DemoRenderBackendOpenGLCube];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    (void)sender;
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    (void)notification;
    [_topicInputTimer invalidate];
    _topicInputTimer = nil;
    [self stopDisplayLink];
}

@end