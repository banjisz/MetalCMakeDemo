#import "AppDelegate.h"
#import "Renderer.h"
#import <QuartzCore/CAMetalLayer.h>
#import <CoreVideo/CoreVideo.h>

static CVReturn DisplayLinkOutputCallback(CVDisplayLinkRef displayLink,
                                          const CVTimeStamp *now,
                                          const CVTimeStamp *outputTime,
                                          CVOptionFlags flagsIn,
                                          CVOptionFlags *flagsOut,
                                          void *displayLinkContext)
{
    (void)displayLink;
    (void)now;
    (void)outputTime;
    (void)flagsIn;
    (void)flagsOut;

    AppDelegate *delegate = (__bridge AppDelegate *)displayLinkContext;
    if (!delegate)
    {
        return kCVReturnError;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate drawFrame];
    });

    return kCVReturnSuccess;
}

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

@interface AppDelegate ()
{
    NSWindow *_window;
    MetalView *_metalView;
    Renderer *_renderer;
    CVDisplayLinkRef _displayLink;
    NSMutableString *_topicInputBuffer;
    NSTimer *_topicInputTimer;

    NSVisualEffectView *_runtimePanel;
    NSTextField *_metricsLabel;
    NSTextField *_parameterLabel;
    NSTextField *_errorHintLabel;
    NSSlider *_timeScaleSlider;
    NSSlider *_edgeGainSlider;
    NSSlider *_exposureGainSlider;
    NSTextField *_timeScaleValueLabel;
    NSTextField *_edgeGainValueLabel;
    NSTextField *_exposureGainValueLabel;
    NSButton *_errorToggleButton;

    NSWindow *_docWindow;
    NSTextView *_docTextView;

    NSMenuItem *_errorMenuItem;
    NSMenuItem *_docMenuItem;
}

- (BOOL)startDisplayLink;
- (void)stopDisplayLink;
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
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    NSRect frame = NSMakeRect(100, 100, 800, 600);

    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:(NSWindowStyleMaskTitled |
                                                     NSWindowStyleMaskClosable |
                                                     NSWindowStyleMaskResizable)
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    [_window setTitle:@"Metal CMake Advanced Demo"];
    [_window setRestorable:NO];
    [_window makeKeyAndOrderFront:nil];

    _metalView = [[MetalView alloc] initWithFrame:frame];
    _metalView.keyEventTarget = self;
    [_metalView setWantsLayer:YES];
    [_window setContentView:_metalView];
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

    _topicInputBuffer = [NSMutableString string];
    [self switchToTopic:MetalDemoTopicResourceMemory];
    [self installDemoMenu];
    [self installRuntimePanel];
    [self installDocumentationWindow];
    [self applyUserParametersFromPanel];
    [self refreshRuntimePanel];
    [self updateDocumentationPage];

    if (![self startDisplayLink])
    {
        NSLog(@"Failed to start CVDisplayLink.");
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
}

- (void)updateWindowTitle
{
    NSString *title = [NSString stringWithFormat:@"Metal Learning Demo - %ld. %@",
                       (long)_renderer.demoTopic,
                       [_renderer demoTopicTitle]];
    [_window setTitle:title];
}

- (void)switchToTopic:(MetalDemoTopic)topic
{
    if (topic < MetalDemoTopicResourceMemory || topic > MetalDemoTopicProfiling)
    {
        return;
    }

    [_renderer setDemoTopic:topic];
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

    NSRect frame = NSMakeRect(14, 14, 370, 360);
    _runtimePanel = [[NSVisualEffectView alloc] initWithFrame:frame];
    _runtimePanel.material = NSVisualEffectMaterialHUDWindow;
    _runtimePanel.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    _runtimePanel.state = NSVisualEffectStateActive;
    _runtimePanel.wantsLayer = YES;
    _runtimePanel.layer.cornerRadius = 10.0;
    _runtimePanel.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;

    NSTextField *title = MakeHUDLabel(NSMakeRect(12, 330, 346, 20), 12.0, NSColor.whiteColor, YES);
    title.stringValue = @"实时参数面板";
    [_runtimePanel addSubview:title];

    _metricsLabel = MakeHUDLabel(NSMakeRect(12, 262, 346, 60), 11.0, NSColor.whiteColor, NO);
    [_runtimePanel addSubview:_metricsLabel];

    _parameterLabel = MakeHUDLabel(NSMakeRect(12, 206, 346, 52), 11.0, [NSColor colorWithWhite:0.92 alpha:1.0], NO);
    [_runtimePanel addSubview:_parameterLabel];

    NSTextField *timeLabel = MakeHUDLabel(NSMakeRect(12, 184, 170, 16), 11.0, [NSColor colorWithWhite:0.9 alpha:1.0], NO);
    timeLabel.stringValue = @"时间倍率";
    [_runtimePanel addSubview:timeLabel];

    _timeScaleValueLabel = MakeHUDLabel(NSMakeRect(300, 184, 58, 16), 11.0, NSColor.whiteColor, NO);
    _timeScaleValueLabel.alignment = NSTextAlignmentRight;
    [_runtimePanel addSubview:_timeScaleValueLabel];

    _timeScaleSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(12, 163, 346, 20)];
    _timeScaleSlider.minValue = 0.5;
    _timeScaleSlider.maxValue = 2.0;
    _timeScaleSlider.doubleValue = 1.0;
    _timeScaleSlider.target = self;
    _timeScaleSlider.action = @selector(handleParameterSliderChanged:);
    [_runtimePanel addSubview:_timeScaleSlider];

    NSTextField *edgeLabel = MakeHUDLabel(NSMakeRect(12, 143, 170, 16), 11.0, [NSColor colorWithWhite:0.9 alpha:1.0], NO);
    edgeLabel.stringValue = @"边缘强度倍率";
    [_runtimePanel addSubview:edgeLabel];

    _edgeGainValueLabel = MakeHUDLabel(NSMakeRect(300, 143, 58, 16), 11.0, NSColor.whiteColor, NO);
    _edgeGainValueLabel.alignment = NSTextAlignmentRight;
    [_runtimePanel addSubview:_edgeGainValueLabel];

    _edgeGainSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(12, 122, 346, 20)];
    _edgeGainSlider.minValue = 0.5;
    _edgeGainSlider.maxValue = 2.5;
    _edgeGainSlider.doubleValue = 1.0;
    _edgeGainSlider.target = self;
    _edgeGainSlider.action = @selector(handleParameterSliderChanged:);
    [_runtimePanel addSubview:_edgeGainSlider];

    NSTextField *exposureLabel = MakeHUDLabel(NSMakeRect(12, 102, 170, 16), 11.0, [NSColor colorWithWhite:0.9 alpha:1.0], NO);
    exposureLabel.stringValue = @"曝光倍率";
    [_runtimePanel addSubview:exposureLabel];

    _exposureGainValueLabel = MakeHUDLabel(NSMakeRect(300, 102, 58, 16), 11.0, NSColor.whiteColor, NO);
    _exposureGainValueLabel.alignment = NSTextAlignmentRight;
    [_runtimePanel addSubview:_exposureGainValueLabel];

    _exposureGainSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(12, 81, 346, 20)];
    _exposureGainSlider.minValue = 0.5;
    _exposureGainSlider.maxValue = 2.5;
    _exposureGainSlider.doubleValue = 1.0;
    _exposureGainSlider.target = self;
    _exposureGainSlider.action = @selector(handleParameterSliderChanged:);
    [_runtimePanel addSubview:_exposureGainSlider];

    _errorToggleButton = [[NSButton alloc] initWithFrame:NSMakeRect(12, 56, 220, 20)];
    _errorToggleButton.buttonType = NSButtonTypeSwitch;
    _errorToggleButton.title = @"错误示例开关 (E)";
    _errorToggleButton.state = NSControlStateValueOff;
    _errorToggleButton.target = self;
    _errorToggleButton.action = @selector(toggleErrorExample:);
    [_runtimePanel addSubview:_errorToggleButton];

    _errorHintLabel = MakeHUDLabel(NSMakeRect(12, 12, 346, 42), 10.5, [NSColor colorWithRed:1.0 green:0.84 blue:0.35 alpha:1.0], NO);
    [_runtimePanel addSubview:_errorHintLabel];

    [_metalView addSubview:_runtimePanel];
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
}

- (void)refreshRuntimePanel
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

    _parameterLabel.stringValue = [NSString stringWithFormat:@"实时参数\nTimeScale %.2f   Edge %.2f\nExposure %.2f   Bloom %.2f   Particle %.2f",
                                   stats.timeScale,
                                   stats.edgeStrength,
                                   stats.exposure,
                                   stats.bloomStrength,
                                   stats.particleStrength];

    _timeScaleValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", _timeScaleSlider.doubleValue];
    _edgeGainValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", _edgeGainSlider.doubleValue];
    _exposureGainValueLabel.stringValue = [NSString stringWithFormat:@"%.2f", _exposureGainSlider.doubleValue];

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

- (void)updateDocumentationPage
{
    if (!_docTextView)
    {
        return;
    }

    NSString *doc = TopicDocumentation(_renderer.demoTopic);
    NSString *errorPart = _renderer.errorExampleEnabled
                          ? [_renderer errorExampleSummary]
                          : @"错误示例关闭时显示标准实现路径。";
    _docTextView.string = [NSString stringWithFormat:@"主题 %ld: %@\n\n%@\n\n错误示例开关说明:\n%@",
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
        enabled = ![_renderer errorExampleEnabled];
    }

    [_renderer setErrorExampleEnabled:enabled];
    _errorToggleButton.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
    _errorMenuItem.state = _errorToggleButton.state;
    [self updateDocumentationPage];
    [self refreshRuntimePanel];
    [_window makeFirstResponder:_metalView];
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
    [_window makeFirstResponder:_metalView];
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

    CVReturn status = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    if (status != kCVReturnSuccess || !_displayLink)
    {
        return NO;
    }

    NSScreen *screen = _window.screen ?: [NSScreen mainScreen];
    NSNumber *screenNumber = screen.deviceDescription[@"NSScreenNumber"];
    if (screenNumber)
    {
        CVDisplayLinkSetCurrentCGDisplay(_displayLink, (CGDirectDisplayID)screenNumber.unsignedIntValue);
    }

    status = CVDisplayLinkSetOutputCallback(_displayLink, DisplayLinkOutputCallback, (__bridge void *)self);
    if (status != kCVReturnSuccess)
    {
        CVDisplayLinkRelease(_displayLink);
        _displayLink = NULL;
        return NO;
    }

    status = CVDisplayLinkStart(_displayLink);
    if (status != kCVReturnSuccess)
    {
        CVDisplayLinkRelease(_displayLink);
        _displayLink = NULL;
        return NO;
    }

    return YES;
}

- (void)stopDisplayLink
{
    if (!_displayLink)
    {
        return;
    }

    CVDisplayLinkStop(_displayLink);
    CVDisplayLinkRelease(_displayLink);
    _displayLink = NULL;
}

- (void)drawFrame
{
    if (![_metalView.layer isKindOfClass:[CAMetalLayer class]])
    {
        return;
    }

    CAMetalLayer *metalLayer = (CAMetalLayer *)_metalView.layer;
    metalLayer.frame = _metalView.bounds;
    metalLayer.contentsScale = [_window backingScaleFactor];
    metalLayer.drawableSize = CGSizeMake(_metalView.bounds.size.width * metalLayer.contentsScale,
                                         _metalView.bounds.size.height * metalLayer.contentsScale);
    [_renderer render];
    [self refreshRuntimePanel];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
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