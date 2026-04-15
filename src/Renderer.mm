#import "Renderer.h"
#include <simd/simd.h>

static const NSUInteger kMaxFramesInFlight = 3;
static const NSUInteger kSampleCount = 4;

typedef struct
{
    simd_float3 position;
    simd_float3 normal;
    simd_float3 color;
    simd_float2 uv;
} Vertex;

typedef struct
{
    matrix_float4x4 modelViewProjectionMatrix;
    matrix_float4x4 modelMatrix;
    simd_float3 lightDirection;
    float time;
    float exposure;
    float bloomStrength;
    uint32_t demoTopic;
    uint32_t featureFlags;
} Uniforms;

typedef struct
{
    float edgeStrength;
    float sceneMix;
    float bloomStrength;
    float particleStrength;
    float temporalBlend;
    float exposure;
    simd_float2 texelSize;
} PostProcessParams;

static matrix_float4x4 matrix_identity()
{
    matrix_float4x4 m;
    m.columns[0] = (vector_float4){1.0f, 0.0f, 0.0f, 0.0f};
    m.columns[1] = (vector_float4){0.0f, 1.0f, 0.0f, 0.0f};
    m.columns[2] = (vector_float4){0.0f, 0.0f, 1.0f, 0.0f};
    m.columns[3] = (vector_float4){0.0f, 0.0f, 0.0f, 1.0f};
    return m;
}

static matrix_float4x4 matrix_translation(float tx, float ty, float tz)
{
    matrix_float4x4 m = matrix_identity();
    m.columns[3] = (vector_float4){tx, ty, tz, 1.0f};
    return m;
}

static matrix_float4x4 matrix_rotation(float angle, vector_float3 axis)
{
    vector_float3 nAxis = simd_normalize(axis);
    float x = nAxis.x;
    float y = nAxis.y;
    float z = nAxis.z;
    float c = cosf(angle);
    float s = sinf(angle);
    float t = 1.0f - c;

    matrix_float4x4 m;
    m.columns[0] = (vector_float4){t * x * x + c,     t * x * y - s * z, t * x * z + s * y, 0.0f};
    m.columns[1] = (vector_float4){t * x * y + s * z, t * y * y + c,     t * y * z - s * x, 0.0f};
    m.columns[2] = (vector_float4){t * x * z - s * y, t * y * z + s * x, t * z * z + c,     0.0f};
    m.columns[3] = (vector_float4){0.0f,              0.0f,              0.0f,              1.0f};
    return m;
}

static matrix_float4x4 matrix_perspective(float fovYRadians, float aspect, float nearZ, float farZ)
{
    float ys = 1.0f / tanf(fovYRadians * 0.5f);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);

    matrix_float4x4 m;
    m.columns[0] = (vector_float4){xs,   0.0f, 0.0f,             0.0f};
    m.columns[1] = (vector_float4){0.0f, ys,   0.0f,             0.0f};
    m.columns[2] = (vector_float4){0.0f, 0.0f, zs,              -1.0f};
    m.columns[3] = (vector_float4){0.0f, 0.0f, zs * nearZ,       0.0f};
    return m;
}

static NSUInteger bytes_per_pixel(MTLPixelFormat format)
{
    switch (format)
    {
        case MTLPixelFormatBGRA8Unorm:
        case MTLPixelFormatRGBA8Unorm:
        case MTLPixelFormatDepth32Float:
            return 4;
        case MTLPixelFormatRGBA16Float:
            return 8;
        default:
            return 0;
    }
}

static uint64_t estimated_texture_bytes(id<MTLTexture> texture)
{
    if (!texture)
    {
        return 0;
    }

    NSUInteger bpp = bytes_per_pixel(texture.pixelFormat);
    if (bpp == 0)
    {
        return 0;
    }

    uint64_t total = 0;
    NSUInteger sampleCount = MAX((NSUInteger)1, texture.sampleCount);
    NSUInteger levelCount = MAX((NSUInteger)1, texture.mipmapLevelCount);
    for (NSUInteger level = 0; level < levelCount; ++level)
    {
        uint64_t w = MAX((uint64_t)1, (uint64_t)texture.width >> level);
        uint64_t h = MAX((uint64_t)1, (uint64_t)texture.height >> level);
        total += w * h * (uint64_t)bpp * (uint64_t)sampleCount;
    }

    return total;
}

@interface Renderer ()
{
    CAMetalLayer *_metalLayer;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;

    id<MTLRenderPipelineState> _scenePipelineState;
    id<MTLRenderPipelineState> _scenePBRPipelineState;
    id<MTLRenderPipelineState> _sceneShadowPipelineState;
    id<MTLRenderPipelineState> _sceneArgumentBufferPipelineState;
    id<MTLRenderPipelineState> _postPipelineState;
    id<MTLComputePipelineState> _edgeComputePipelineState;
    id<MTLComputePipelineState> _brightExtractPipelineState;
    id<MTLComputePipelineState> _blurPipelineState;
    id<MTLComputePipelineState> _particlePipelineState;
    id<MTLComputePipelineState> _downsamplePipelineState;
    id<MTLComputePipelineState> _upscalePipelineState;
    id<MTLDepthStencilState> _depthState;
    id<MTLSamplerState> _samplerState;
    id<MTLSamplerState> _anisoSamplerState;

    id<MTLArgumentEncoder> _materialArgumentEncoder;
    id<MTLBuffer> _materialArgumentBuffer;

    id<MTLIndirectCommandBuffer> _indirectCommandBuffer;
    id<MTLSharedEvent> _sharedEvent;

    id<MTLBuffer> _vertexBuffer;
    id<MTLBuffer> _indexBuffer;
    NSUInteger _indexCount;
    id<MTLBuffer> _uniformBuffers[kMaxFramesInFlight];

    id<MTLTexture> _albedoTexture;
    id<MTLTexture> _normalTexture;

    id<MTLTexture> _sceneMSAATexture;
    id<MTLTexture> _sceneResolveTexture;
    id<MTLTexture> _sceneDepthTexture;
    id<MTLTexture> _edgeTexture;
    id<MTLTexture> _postMSAATexture;
    id<MTLTexture> _bloomTextureA;
    id<MTLTexture> _bloomTextureB;
    id<MTLTexture> _particleTexture;
    id<MTLTexture> _historyTexture;
    id<MTLTexture> _halfResTexture;
    id<MTLTexture> _upscaledTexture;

    NSUInteger _frameIndex;
    dispatch_semaphore_t _inFlightSemaphore;
    CFAbsoluteTime _startTime;
    MetalDemoTopic _demoTopic;
    BOOL _historyValid;
    BOOL _supportsRayTracing;

    BOOL _errorExampleEnabled;
    float _userTimeScaleGain;
    float _userEdgeGain;
    float _userExposureGain;

    double _lastCPUFrameTimeMs;
    double _lastGPUFrameTimeMs;
    double _lastEstimatedMemoryMB;
    float _lastTimeScale;
    float _lastEdgeStrength;
    float _lastExposure;
    float _lastBloomStrength;
    float _lastParticleStrength;
    float _lastTemporalBlend;
}

- (uint64_t)estimatedVideoMemoryBytes;
@end

@implementation Renderer

+ (NSArray<NSString *> *)allDemoTopicTitles
{
    return @[
        @"Resource And Memory Modes",
        @"Argument Buffer Binding",
        @"Function Constants",
        @"Indirect Command Buffer",
        @"Parallel Render Encoding",
        @"Deferred Style Composition",
        @"Shadowing Techniques",
        @"PBR Shading",
        @"HDR Bloom And Temporal",
        @"Compute Particles",
        @"Advanced Texture Sampling",
        @"Synchronization And Scheduling",
        @"Ray Tracing Fallback",
        @"MetalFX Style Upscaling",
        @"Profiling And Debug Markers"
    ];
}

- (void)setDemoTopic:(MetalDemoTopic)topic
{
    if (topic < MetalDemoTopicResourceMemory || topic > MetalDemoTopicProfiling)
    {
        return;
    }

    _demoTopic = topic;
}

- (MetalDemoTopic)demoTopic
{
    return _demoTopic;
}

- (void)setErrorExampleEnabled:(BOOL)enabled
{
    _errorExampleEnabled = enabled;
}

- (BOOL)errorExampleEnabled
{
    return _errorExampleEnabled;
}

- (void)setUserParameterTimeScale:(float)timeScale edgeGain:(float)edgeGain exposureGain:(float)exposureGain
{
    _userTimeScaleGain = fmaxf(0.25f, fminf(timeScale, 3.0f));
    _userEdgeGain = fmaxf(0.1f, fminf(edgeGain, 3.0f));
    _userExposureGain = fmaxf(0.25f, fminf(exposureGain, 3.0f));
}

- (MetalDemoRuntimeStats)runtimeStats
{
    MetalDemoRuntimeStats stats;
    @synchronized (self)
    {
        stats.cpuFrameTimeMs = _lastCPUFrameTimeMs;
        stats.gpuFrameTimeMs = _lastGPUFrameTimeMs;
        stats.estimatedMemoryMB = _lastEstimatedMemoryMB;
        stats.timeScale = _lastTimeScale;
        stats.edgeStrength = _lastEdgeStrength;
        stats.exposure = _lastExposure;
        stats.bloomStrength = _lastBloomStrength;
        stats.particleStrength = _lastParticleStrength;
        stats.temporalBlend = _lastTemporalBlend;
        stats.errorExampleEnabled = _errorExampleEnabled;
    }
    return stats;
}

- (NSString *)errorExampleSummary
{
    switch (_demoTopic)
    {
        case MetalDemoTopicResourceMemory:
            return @"每帧强制重建渲染目标，模拟资源抖动导致的卡顿。";
        case MetalDemoTopicArgumentBuffer:
            return @"故意放大后期混合参数，观察绑定/合成配置错误导致的画面过曝。";
        case MetalDemoTopicFunctionConstants:
            return @"缩短变体切换周期，观察频繁路径切换导致的视觉不稳定。";
        case MetalDemoTopicIndirectCommandBuffer:
            return @"增加额外边缘计算轮次，模拟间接命令组织不当造成的 GPU 压力。";
        case MetalDemoTopicParallelEncoding:
            return @"提升时间缩放与计算负载，观察 CPU 编码与 GPU 并发失衡。";
        case MetalDemoTopicDeferredLike:
            return @"边缘权重过高，演示 deferred 合成参数失衡带来的伪影。";
        case MetalDemoTopicShadowing:
            return @"阴影混合过重，展示可见性计算错误对暗部层次的破坏。";
        case MetalDemoTopicPBR:
            return @"曝光和高光增强过量，展示 BRDF 参数超界导致的能量不守恒。";
        case MetalDemoTopicHDRBloomTAA:
            return @"高 bloom + 高 temporal，演示拖影和过亮 bloom 的典型错误。";
        case MetalDemoTopicComputeParticles:
            return @"提升粒子强度并增加计算轮次，观察填充率与合成瓶颈。";
        case MetalDemoTopicTextureAdvanced:
            return @"纹理边缘权重拉高，演示采样过滤配置不合理造成的锯齿。";
        case MetalDemoTopicSyncAndScheduling:
            return @"增加 GPU 压力，观察调度节奏不匹配时的帧时抖动。";
        case MetalDemoTopicRayTracing:
            return @"在回退路径上叠加负载，演示能力探测与降级策略不足的问题。";
        case MetalDemoTopicMetalFXLike:
            return @"提升 temporal 与曝光，演示上采样链路中的鬼影和光晕。";
        case MetalDemoTopicProfiling:
            return @"增加冗余 compute 轮次，便于在 capture 中观察热点阶段。";
    }

    return @"错误示例未定义。";
}

- (NSString *)demoTopicTitle
{
    NSArray<NSString *> *titles = [Renderer allDemoTopicTitles];
    NSInteger idx = _demoTopic - 1;
    if (idx < 0 || idx >= (NSInteger)titles.count)
    {
        return @"Unknown";
    }

    return titles[idx];
}

- (id<MTLTexture>)createAlbedoTexture
{
    const NSUInteger size = 256;
    MTLTextureDescriptor *descriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                           width:size
                                                          height:size
                                                       mipmapped:YES];
    descriptor.usage = MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModeShared;

    id<MTLTexture> texture = [_device newTextureWithDescriptor:descriptor];
    if (!texture)
    {
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:size * size * 4];
    uint8_t *pixels = (uint8_t *)data.mutableBytes;

    for (NSUInteger y = 0; y < size; ++y)
    {
        for (NSUInteger x = 0; x < size; ++x)
        {
            bool checker = (((x / 32) + (y / 32)) % 2) == 0;
            float u = (float)x / (float)(size - 1);
            float v = (float)y / (float)(size - 1);

            float r = checker ? (0.2f + 0.7f * u) : (0.1f + 0.3f * v);
            float g = checker ? (0.4f + 0.4f * v) : (0.2f + 0.5f * u);
            float b = checker ? (0.8f - 0.5f * u) : (0.15f + 0.45f * v);

            NSUInteger i = (y * size + x) * 4;
            pixels[i + 0] = (uint8_t)(fminf(fmaxf(r, 0.0f), 1.0f) * 255.0f);
            pixels[i + 1] = (uint8_t)(fminf(fmaxf(g, 0.0f), 1.0f) * 255.0f);
            pixels[i + 2] = (uint8_t)(fminf(fmaxf(b, 0.0f), 1.0f) * 255.0f);
            pixels[i + 3] = 255;
        }
    }

    MTLRegion region = MTLRegionMake2D(0, 0, size, size);
    [texture replaceRegion:region mipmapLevel:0 withBytes:pixels bytesPerRow:size * 4];
    return texture;
}

- (id<MTLTexture>)createNormalTexture
{
    const NSUInteger size = 256;
    MTLTextureDescriptor *descriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                           width:size
                                                          height:size
                                                       mipmapped:YES];
    descriptor.usage = MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModeShared;

    id<MTLTexture> texture = [_device newTextureWithDescriptor:descriptor];
    if (!texture)
    {
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:size * size * 4];
    uint8_t *pixels = (uint8_t *)data.mutableBytes;

    for (NSUInteger y = 0; y < size; ++y)
    {
        for (NSUInteger x = 0; x < size; ++x)
        {
            float u = ((float)x / (float)(size - 1)) * 2.0f - 1.0f;
            float v = ((float)y / (float)(size - 1)) * 2.0f - 1.0f;

            float nx = sinf(u * 9.0f) * 0.35f;
            float ny = cosf(v * 9.0f) * 0.35f;
            float nz = sqrtf(fmaxf(1.0f - nx * nx - ny * ny, 0.0f));

            float ex = nx * 0.5f + 0.5f;
            float ey = ny * 0.5f + 0.5f;
            float ez = nz * 0.5f + 0.5f;

            NSUInteger i = (y * size + x) * 4;
            pixels[i + 0] = (uint8_t)(fminf(fmaxf(ex, 0.0f), 1.0f) * 255.0f);
            pixels[i + 1] = (uint8_t)(fminf(fmaxf(ey, 0.0f), 1.0f) * 255.0f);
            pixels[i + 2] = (uint8_t)(fminf(fmaxf(ez, 0.0f), 1.0f) * 255.0f);
            pixels[i + 3] = 255;
        }
    }

    MTLRegion region = MTLRegionMake2D(0, 0, size, size);
    [texture replaceRegion:region mipmapLevel:0 withBytes:pixels bytesPerRow:size * 4];
    return texture;
}

- (void)ensureRenderTargetsForDrawable:(id<CAMetalDrawable>)drawable
{
    NSUInteger width = drawable.texture.width;
    NSUInteger height = drawable.texture.height;

    if (_sceneResolveTexture &&
        _sceneResolveTexture.width == width &&
        _sceneResolveTexture.height == height)
    {
        return;
    }

    MTLTextureDescriptor *sceneMSAADescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    sceneMSAADescriptor.textureType = MTLTextureType2DMultisample;
    sceneMSAADescriptor.sampleCount = kSampleCount;
    sceneMSAADescriptor.storageMode = MTLStorageModePrivate;
    sceneMSAADescriptor.usage = MTLTextureUsageRenderTarget;
    _sceneMSAATexture = [_device newTextureWithDescriptor:sceneMSAADescriptor];

    MTLTextureDescriptor *sceneResolveDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    sceneResolveDescriptor.storageMode = MTLStorageModePrivate;
    sceneResolveDescriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    _sceneResolveTexture = [_device newTextureWithDescriptor:sceneResolveDescriptor];

    MTLTextureDescriptor *depthDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    depthDescriptor.textureType = MTLTextureType2DMultisample;
    depthDescriptor.sampleCount = kSampleCount;
    depthDescriptor.storageMode = MTLStorageModePrivate;
    depthDescriptor.usage = MTLTextureUsageRenderTarget;
    _sceneDepthTexture = [_device newTextureWithDescriptor:depthDescriptor];

    MTLTextureDescriptor *edgeDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    edgeDescriptor.storageMode = MTLStorageModePrivate;
    edgeDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    _edgeTexture = [_device newTextureWithDescriptor:edgeDescriptor];

    MTLTextureDescriptor *postMSAADescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    postMSAADescriptor.textureType = MTLTextureType2DMultisample;
    postMSAADescriptor.sampleCount = kSampleCount;
    postMSAADescriptor.storageMode = MTLStorageModePrivate;
    postMSAADescriptor.usage = MTLTextureUsageRenderTarget;
    _postMSAATexture = [_device newTextureWithDescriptor:postMSAADescriptor];

    MTLTextureDescriptor *bloomDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    bloomDescriptor.storageMode = MTLStorageModePrivate;
    bloomDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    _bloomTextureA = [_device newTextureWithDescriptor:bloomDescriptor];
    _bloomTextureB = [_device newTextureWithDescriptor:bloomDescriptor];

    MTLTextureDescriptor *particleDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    particleDescriptor.storageMode = MTLStorageModePrivate;
    particleDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    _particleTexture = [_device newTextureWithDescriptor:particleDescriptor];

    MTLTextureDescriptor *historyDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    historyDescriptor.storageMode = MTLStorageModePrivate;
    historyDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget;
    _historyTexture = [_device newTextureWithDescriptor:historyDescriptor];

    NSUInteger halfWidth = MAX((NSUInteger)1, width / 2);
    NSUInteger halfHeight = MAX((NSUInteger)1, height / 2);
    MTLTextureDescriptor *halfDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                           width:halfWidth
                                                          height:halfHeight
                                                       mipmapped:NO];
    halfDescriptor.storageMode = MTLStorageModePrivate;
    halfDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    _halfResTexture = [_device newTextureWithDescriptor:halfDescriptor];

    MTLTextureDescriptor *upscaledDescriptor =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    upscaledDescriptor.storageMode = MTLStorageModePrivate;
    upscaledDescriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    _upscaledTexture = [_device newTextureWithDescriptor:upscaledDescriptor];

    _historyValid = NO;
}

- (uint64_t)estimatedVideoMemoryBytes
{
    uint64_t total = 0;
    total += estimated_texture_bytes(_sceneMSAATexture);
    total += estimated_texture_bytes(_sceneResolveTexture);
    total += estimated_texture_bytes(_sceneDepthTexture);
    total += estimated_texture_bytes(_edgeTexture);
    total += estimated_texture_bytes(_postMSAATexture);
    total += estimated_texture_bytes(_bloomTextureA);
    total += estimated_texture_bytes(_bloomTextureB);
    total += estimated_texture_bytes(_particleTexture);
    total += estimated_texture_bytes(_historyTexture);
    total += estimated_texture_bytes(_halfResTexture);
    total += estimated_texture_bytes(_upscaledTexture);
    total += estimated_texture_bytes(_albedoTexture);
    total += estimated_texture_bytes(_normalTexture);

    total += _vertexBuffer ? _vertexBuffer.length : 0;
    total += _indexBuffer ? _indexBuffer.length : 0;
    total += _materialArgumentBuffer ? _materialArgumentBuffer.length : 0;
    for (NSUInteger i = 0; i < kMaxFramesInFlight; ++i)
    {
        total += _uniformBuffers[i] ? _uniformBuffers[i].length : 0;
    }

    return total;
}

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

        _metalLayer.device = _device;
        _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        _metalLayer.drawableSize = CGSizeMake(_metalLayer.bounds.size.width * _metalLayer.contentsScale,
                                              _metalLayer.bounds.size.height * _metalLayer.contentsScale);
        _metalLayer.framebufferOnly = YES;

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

        _commandQueue = [_device newCommandQueue];
        if (!_commandQueue)
        {
            NSLog(@"Failed to create command queue.");
            return nil;
        }

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

        id<MTLFunction> sceneVertex = [library newFunctionWithName:@"scene_vertex"];
        id<MTLFunction> postVertex = [library newFunctionWithName:@"post_vertex"];
        id<MTLFunction> postFragment = [library newFunctionWithName:@"post_fragment"];
        id<MTLFunction> edgeKernel = [library newFunctionWithName:@"edge_detect_kernel"];
        id<MTLFunction> brightKernel = [library newFunctionWithName:@"bright_extract_kernel"];
        id<MTLFunction> blurKernel = [library newFunctionWithName:@"blur_kernel"];
        id<MTLFunction> particleKernel = [library newFunctionWithName:@"particle_overlay_kernel"];
        id<MTLFunction> downsampleKernel = [library newFunctionWithName:@"downsample_half_kernel"];
        id<MTLFunction> upscaleKernel = [library newFunctionWithName:@"upscale_linear_kernel"];

        if (!sceneVertex || !postVertex || !postFragment || !edgeKernel || !brightKernel ||
            !blurKernel || !particleKernel || !downsampleKernel || !upscaleKernel)
        {
            NSLog(@"Failed to load one or more Metal shader functions.");
            return nil;
        }

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

        MTLRenderPipelineDescriptor *scenePipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        scenePipelineDescriptor.vertexFunction = sceneVertex;
        scenePipelineDescriptor.fragmentFunction = sceneFragmentBase;
        scenePipelineDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        scenePipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        scenePipelineDescriptor.rasterSampleCount = kSampleCount;

        _scenePipelineState = [_device newRenderPipelineStateWithDescriptor:scenePipelineDescriptor error:&error];
        if (!_scenePipelineState)
        {
            NSLog(@"Failed to create scene pipeline state: %@", error);
            return nil;
        }

        scenePipelineDescriptor.fragmentFunction = sceneFragmentPBR;
        _scenePBRPipelineState = [_device newRenderPipelineStateWithDescriptor:scenePipelineDescriptor error:&error];
        if (!_scenePBRPipelineState)
        {
            NSLog(@"Failed to create PBR pipeline state: %@", error);
            return nil;
        }

        scenePipelineDescriptor.fragmentFunction = sceneFragmentShadow;
        _sceneShadowPipelineState = [_device newRenderPipelineStateWithDescriptor:scenePipelineDescriptor error:&error];
        if (!_sceneShadowPipelineState)
        {
            NSLog(@"Failed to create shadow pipeline state: %@", error);
            return nil;
        }

        scenePipelineDescriptor.fragmentFunction = sceneFragmentArg;
        _sceneArgumentBufferPipelineState = [_device newRenderPipelineStateWithDescriptor:scenePipelineDescriptor error:&error];
        if (!_sceneArgumentBufferPipelineState)
        {
            NSLog(@"Failed to create argument-buffer pipeline state: %@", error);
            return nil;
        }

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

        _edgeComputePipelineState = [_device newComputePipelineStateWithFunction:edgeKernel error:&error];
        if (!_edgeComputePipelineState)
        {
            NSLog(@"Failed to create compute pipeline state: %@", error);
            return nil;
        }

        _brightExtractPipelineState = [_device newComputePipelineStateWithFunction:brightKernel error:&error];
        _blurPipelineState = [_device newComputePipelineStateWithFunction:blurKernel error:&error];
        _particlePipelineState = [_device newComputePipelineStateWithFunction:particleKernel error:&error];
        _downsamplePipelineState = [_device newComputePipelineStateWithFunction:downsampleKernel error:&error];
        _upscalePipelineState = [_device newComputePipelineStateWithFunction:upscaleKernel error:&error];
        if (!_brightExtractPipelineState || !_blurPipelineState || !_particlePipelineState ||
            !_downsamplePipelineState || !_upscalePipelineState)
        {
            NSLog(@"Failed to create one or more post compute pipelines: %@", error);
            return nil;
        }

        _materialArgumentEncoder = [sceneFragmentArg newArgumentEncoderWithBufferIndex:2];
        _materialArgumentBuffer = [_device newBufferWithLength:_materialArgumentEncoder.encodedLength
                                                       options:MTLResourceStorageModeShared];
        if (!_materialArgumentEncoder || !_materialArgumentBuffer)
        {
            NSLog(@"Failed to create argument buffer resources.");
            return nil;
        }

        MTLDepthStencilDescriptor *depthDescriptor = [[MTLDepthStencilDescriptor alloc] init];
        depthDescriptor.depthCompareFunction = MTLCompareFunctionLess;
        depthDescriptor.depthWriteEnabled = YES;
        _depthState = [_device newDepthStencilStateWithDescriptor:depthDescriptor];
        if (!_depthState)
        {
            NSLog(@"Failed to create depth state.");
            return nil;
        }

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

        if ([_device respondsToSelector:@selector(newSharedEvent)])
        {
            _sharedEvent = [_device newSharedEvent];
        }

        _supportsRayTracing = [_device supportsRaytracing];

        MTLIndirectCommandBufferDescriptor *icbDescriptor = [[MTLIndirectCommandBufferDescriptor alloc] init];
        icbDescriptor.commandTypes = MTLIndirectCommandTypeDrawIndexed;
        icbDescriptor.inheritPipelineState = YES;
        icbDescriptor.inheritBuffers = YES;
        icbDescriptor.maxVertexBufferBindCount = 0;
        icbDescriptor.maxFragmentBufferBindCount = 0;
        _indirectCommandBuffer = [_device newIndirectCommandBufferWithDescriptor:icbDescriptor
                                                                   maxCommandCount:1
                                                                           options:0];
        if (!_indirectCommandBuffer)
        {
            NSLog(@"Failed to create indirect command buffer.");
            return nil;
        }

        static const Vertex cubeVertices[] = {
            {{-1.0f, -1.0f,  1.0f}, { 0.0f,  0.0f,  1.0f}, {0.95f, 0.95f, 0.95f}, {0.0f, 0.0f}},
            {{ 1.0f, -1.0f,  1.0f}, { 0.0f,  0.0f,  1.0f}, {0.95f, 0.95f, 0.95f}, {1.0f, 0.0f}},
            {{ 1.0f,  1.0f,  1.0f}, { 0.0f,  0.0f,  1.0f}, {0.95f, 0.95f, 0.95f}, {1.0f, 1.0f}},
            {{-1.0f,  1.0f,  1.0f}, { 0.0f,  0.0f,  1.0f}, {0.95f, 0.95f, 0.95f}, {0.0f, 1.0f}},

            {{ 1.0f, -1.0f, -1.0f}, { 0.0f,  0.0f, -1.0f}, {0.95f, 0.95f, 0.95f}, {0.0f, 0.0f}},
            {{-1.0f, -1.0f, -1.0f}, { 0.0f,  0.0f, -1.0f}, {0.95f, 0.95f, 0.95f}, {1.0f, 0.0f}},
            {{-1.0f,  1.0f, -1.0f}, { 0.0f,  0.0f, -1.0f}, {0.95f, 0.95f, 0.95f}, {1.0f, 1.0f}},
            {{ 1.0f,  1.0f, -1.0f}, { 0.0f,  0.0f, -1.0f}, {0.95f, 0.95f, 0.95f}, {0.0f, 1.0f}},

            {{-1.0f, -1.0f, -1.0f}, {-1.0f,  0.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {0.0f, 0.0f}},
            {{-1.0f, -1.0f,  1.0f}, {-1.0f,  0.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {1.0f, 0.0f}},
            {{-1.0f,  1.0f,  1.0f}, {-1.0f,  0.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {1.0f, 1.0f}},
            {{-1.0f,  1.0f, -1.0f}, {-1.0f,  0.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {0.0f, 1.0f}},

            {{ 1.0f, -1.0f,  1.0f}, { 1.0f,  0.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {0.0f, 0.0f}},
            {{ 1.0f, -1.0f, -1.0f}, { 1.0f,  0.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {1.0f, 0.0f}},
            {{ 1.0f,  1.0f, -1.0f}, { 1.0f,  0.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {1.0f, 1.0f}},
            {{ 1.0f,  1.0f,  1.0f}, { 1.0f,  0.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {0.0f, 1.0f}},

            {{-1.0f,  1.0f,  1.0f}, { 0.0f,  1.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {0.0f, 0.0f}},
            {{ 1.0f,  1.0f,  1.0f}, { 0.0f,  1.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {1.0f, 0.0f}},
            {{ 1.0f,  1.0f, -1.0f}, { 0.0f,  1.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {1.0f, 1.0f}},
            {{-1.0f,  1.0f, -1.0f}, { 0.0f,  1.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {0.0f, 1.0f}},

            {{-1.0f, -1.0f, -1.0f}, { 0.0f, -1.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {0.0f, 0.0f}},
            {{ 1.0f, -1.0f, -1.0f}, { 0.0f, -1.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {1.0f, 0.0f}},
            {{ 1.0f, -1.0f,  1.0f}, { 0.0f, -1.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {1.0f, 1.0f}},
            {{-1.0f, -1.0f,  1.0f}, { 0.0f, -1.0f,  0.0f}, {0.95f, 0.95f, 0.95f}, {0.0f, 1.0f}}
        };

        static const uint16_t cubeIndices[] = {
            0, 1, 2, 2, 3, 0,
            4, 5, 6, 6, 7, 4,
            8, 9, 10, 10, 11, 8,
            12, 13, 14, 14, 15, 12,
            16, 17, 18, 18, 19, 16,
            20, 21, 22, 22, 23, 20
        };

        _vertexBuffer = [_device newBufferWithBytes:cubeVertices
                                              length:sizeof(cubeVertices)
                                             options:MTLResourceStorageModeShared];
        _indexBuffer = [_device newBufferWithBytes:cubeIndices
                                             length:sizeof(cubeIndices)
                                            options:MTLResourceStorageModeShared];
        _indexCount = sizeof(cubeIndices) / sizeof(cubeIndices[0]);
        if (!_vertexBuffer || !_indexBuffer)
        {
            NSLog(@"Failed to create mesh buffers.");
            return nil;
        }

                id<MTLIndirectRenderCommand> prebuiltICBCommand = [_indirectCommandBuffer indirectRenderCommandAtIndex:0];
                [prebuiltICBCommand drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                                                             indexCount:_indexCount
                                                                                indexType:MTLIndexTypeUInt16
                                                                            indexBuffer:_indexBuffer
                                                                indexBufferOffset:0
                                                                        instanceCount:1
                                                                             baseVertex:0
                                                                         baseInstance:0];

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

        _albedoTexture = [self createAlbedoTexture];
        _normalTexture = [self createNormalTexture];
        if (!_albedoTexture || !_normalTexture)
        {
            NSLog(@"Failed to create material textures.");
            return nil;
        }

        [_materialArgumentEncoder setArgumentBuffer:_materialArgumentBuffer offset:0];
        [_materialArgumentEncoder setTexture:_albedoTexture atIndex:0];
        [_materialArgumentEncoder setTexture:_normalTexture atIndex:1];

        id<MTLCommandBuffer> setupCommandBuffer = [_commandQueue commandBuffer];
        id<MTLBlitCommandEncoder> setupBlit = [setupCommandBuffer blitCommandEncoder];
        [setupBlit generateMipmapsForTexture:_albedoTexture];
        [setupBlit generateMipmapsForTexture:_normalTexture];
        [setupBlit endEncoding];
        [setupCommandBuffer commit];
        [setupCommandBuffer waitUntilCompleted];

        _historyValid = NO;
    }

    return self;
}

- (void)render
{
    @autoreleasepool
    {
        CFAbsoluteTime cpuFrameStart = CFAbsoluteTimeGetCurrent();
        dispatch_semaphore_wait(_inFlightSemaphore, DISPATCH_TIME_FOREVER);

        if (_errorExampleEnabled && _demoTopic == MetalDemoTopicResourceMemory)
        {
            _sceneResolveTexture = nil;
        }

        id<CAMetalDrawable> drawable = [_metalLayer nextDrawable];
        if (!drawable)
        {
            dispatch_semaphore_signal(_inFlightSemaphore);
            return;
        }

        [self ensureRenderTargetsForDrawable:drawable];
        if (!_sceneMSAATexture || !_sceneResolveTexture || !_sceneDepthTexture || !_edgeTexture || !_postMSAATexture)
        {
            dispatch_semaphore_signal(_inFlightSemaphore);
            return;
        }

        id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        if (!commandBuffer)
        {
            dispatch_semaphore_signal(_inFlightSemaphore);
            return;
        }

        __block dispatch_semaphore_t semaphore = _inFlightSemaphore;
        [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> _Nonnull buffer) {
            double gpuFrameMs = -1.0;
            if (buffer.GPUEndTime > buffer.GPUStartTime)
            {
                gpuFrameMs = (buffer.GPUEndTime - buffer.GPUStartTime) * 1000.0;
            }
            @synchronized (self)
            {
                _lastGPUFrameTimeMs = gpuFrameMs;
            }
            dispatch_semaphore_signal(semaphore);
        }];

        NSUInteger uniformIndex = _frameIndex % kMaxFramesInFlight;
        _frameIndex++;

        float elapsed = (float)(CFAbsoluteTimeGetCurrent() - _startTime);
        float timeScale = 1.0f;
        float edgeStrength = 0.9f;
        float sceneMix = 1.0f;
        float exposureBias = 1.0f;
        float bloomStrength = 0.0f;
        float particleStrength = 0.0f;
        float temporalBlend = 0.0f;
        MTLClearColor sceneClear = MTLClearColorMake(0.04, 0.05, 0.08, 1.0);

        BOOL useArgumentBuffer = (_demoTopic == MetalDemoTopicArgumentBuffer);
        // Keep argument buffer resources bound for learning, but use shader fallback for stability.
        BOOL useArgumentShader = NO;
        // ICB compatibility fallback: keep topic hooks but use direct draw path for stability.
        BOOL useICB = NO;
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

        if (_demoTopic == MetalDemoTopicFunctionConstants)
        {
            usePBR = fmodf(elapsed, 4.0f) > 2.0f;
            useShadow = !usePBR;
            edgeStrength = 0.25f;
        }

        switch (_demoTopic)
        {
            case MetalDemoTopicResourceMemory:
                sceneClear = MTLClearColorMake(0.03, 0.06, 0.10, 1.0);
                break;
            case MetalDemoTopicArgumentBuffer:
                sceneClear = MTLClearColorMake(0.08, 0.06, 0.03, 1.0);
                edgeStrength = 0.45f;
                break;
            case MetalDemoTopicFunctionConstants:
                edgeStrength = 0.25f;
                break;
            case MetalDemoTopicIndirectCommandBuffer:
                timeScale = 1.25f;
                sceneClear = MTLClearColorMake(0.02, 0.02, 0.05, 1.0);
                break;
            case MetalDemoTopicParallelEncoding:
                timeScale = 1.4f;
                sceneMix = 0.95f;
                break;
            case MetalDemoTopicDeferredLike:
                edgeStrength = 1.2f;
                sceneMix = 0.9f;
                break;
            case MetalDemoTopicShadowing:
                edgeStrength = 0.35f;
                sceneMix = 0.85f;
                break;
            case MetalDemoTopicPBR:
                exposureBias = 1.25f;
                break;
            case MetalDemoTopicHDRBloomTAA:
                edgeStrength = 0.02f;
                exposureBias = 1.0f;
                bloomStrength = 0.08f;
                temporalBlend = 0.0f;
                break;
            case MetalDemoTopicComputeParticles:
                edgeStrength = 0.65f;
                sceneMix = 0.95f;
                particleStrength = 0.45f;
                break;
            case MetalDemoTopicTextureAdvanced:
                sceneClear = MTLClearColorMake(0.02, 0.08, 0.07, 1.0);
                break;
            case MetalDemoTopicSyncAndScheduling:
                timeScale = 0.65f;
                break;
            case MetalDemoTopicRayTracing:
                edgeStrength = _supportsRayTracing ? 0.10f : 1.1f;
                exposureBias = _supportsRayTracing ? 1.3f : 1.0f;
                break;
            case MetalDemoTopicMetalFXLike:
                sceneMix = 0.82f;
                exposureBias = 1.3f;
                temporalBlend = _historyValid ? 0.6f : 0.0f;
                break;
            case MetalDemoTopicProfiling:
                edgeStrength = 1.0f;
                sceneMix = 0.96f;
                break;
        }

        if (_errorExampleEnabled)
        {
            switch (_demoTopic)
            {
                case MetalDemoTopicResourceMemory:
                    extraStressPasses = 1;
                    break;
                case MetalDemoTopicArgumentBuffer:
                    sceneMix = 1.25f;
                    edgeStrength = 1.8f;
                    break;
                case MetalDemoTopicFunctionConstants:
                    timeScale = 2.2f;
                    break;
                case MetalDemoTopicIndirectCommandBuffer:
                    extraStressPasses = 2;
                    break;
                case MetalDemoTopicParallelEncoding:
                    timeScale = 2.4f;
                    extraStressPasses = 2;
                    break;
                case MetalDemoTopicDeferredLike:
                    edgeStrength = 2.2f;
                    sceneMix = 0.75f;
                    break;
                case MetalDemoTopicShadowing:
                    sceneMix = 0.72f;
                    edgeStrength = 1.5f;
                    break;
                case MetalDemoTopicPBR:
                    exposureBias = 2.1f;
                    break;
                case MetalDemoTopicHDRBloomTAA:
                    bloomStrength = 0.7f;
                    temporalBlend = _historyValid ? 0.92f : 0.0f;
                    break;
                case MetalDemoTopicComputeParticles:
                    particleStrength = 1.2f;
                    extraStressPasses = 2;
                    break;
                case MetalDemoTopicTextureAdvanced:
                    edgeStrength = 1.4f;
                    break;
                case MetalDemoTopicSyncAndScheduling:
                    extraStressPasses = 3;
                    break;
                case MetalDemoTopicRayTracing:
                    exposureBias = _supportsRayTracing ? 1.9f : 1.2f;
                    edgeStrength = _supportsRayTracing ? 0.5f : 1.7f;
                    break;
                case MetalDemoTopicMetalFXLike:
                    temporalBlend = _historyValid ? 0.95f : 0.0f;
                    exposureBias = 1.75f;
                    break;
                case MetalDemoTopicProfiling:
                    extraStressPasses = 4;
                    break;
            }
        }

        timeScale = fmaxf(0.1f, timeScale * _userTimeScaleGain);
        edgeStrength = fmaxf(0.0f, edgeStrength * _userEdgeGain);
        exposureBias = fmaxf(0.1f, exposureBias * _userExposureGain);

        elapsed *= timeScale;
        Uniforms *uniforms = (Uniforms *)_uniformBuffers[uniformIndex].contents;

        float aspect = (float)_sceneResolveTexture.width / (float)MAX((NSUInteger)1, _sceneResolveTexture.height);
        matrix_float4x4 projection = matrix_perspective(65.0f * ((float)M_PI / 180.0f), aspect, 0.1f, 100.0f);
        matrix_float4x4 view = matrix_translation(0.0f, 0.0f, -5.2f);
        matrix_float4x4 rotationY = matrix_rotation(elapsed * 0.8f, (vector_float3){0.0f, 1.0f, 0.0f});
        matrix_float4x4 rotationX = matrix_rotation(elapsed * 0.5f, (vector_float3){1.0f, 0.0f, 0.0f});
        matrix_float4x4 model = matrix_multiply(rotationY, rotationX);
        matrix_float4x4 mv = matrix_multiply(view, model);

        uniforms->modelViewProjectionMatrix = matrix_multiply(projection, mv);
        uniforms->modelMatrix = model;
        uniforms->lightDirection = simd_normalize((vector_float3){0.5f, 0.8f, 0.4f});
        uniforms->time = elapsed;
        uniforms->exposure = exposureBias;
        uniforms->bloomStrength = bloomStrength;
        uniforms->demoTopic = (uint32_t)_demoTopic;
        uniforms->featureFlags = (useBloom ? 1u : 0u) | (useParticles ? 2u : 0u) |
                                 (useRayTraceMode ? 4u : 0u) | (useUpscale ? 8u : 0u);

        id<MTLRenderPipelineState> selectedScenePipeline = _scenePipelineState;
        if (useArgumentShader)
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

        if (useParallel)
        {
            id<MTLParallelRenderCommandEncoder> parallelEncoder =
                [commandBuffer parallelRenderCommandEncoderWithDescriptor:scenePass];
            if (!parallelEncoder)
            {
                dispatch_semaphore_signal(_inFlightSemaphore);
                return;
            }

            id<MTLRenderCommandEncoder> sceneEncoder = [parallelEncoder renderCommandEncoder];
            if (!sceneEncoder)
            {
                dispatch_semaphore_signal(_inFlightSemaphore);
                return;
            }

            [sceneEncoder setRenderPipelineState:selectedScenePipeline];
            [sceneEncoder setDepthStencilState:_depthState];
            [sceneEncoder setCullMode:MTLCullModeBack];
            [sceneEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
            [sceneEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
            [sceneEncoder setVertexBuffer:_uniformBuffers[uniformIndex] offset:0 atIndex:1];
            [sceneEncoder setFragmentBuffer:_uniformBuffers[uniformIndex] offset:0 atIndex:1];
            [sceneEncoder setFragmentBuffer:_materialArgumentBuffer offset:0 atIndex:2];
            [sceneEncoder setFragmentSamplerState:sceneSampler atIndex:0];
            if (useArgumentShader)
            {
                // Argument-buffer topic: resource fetches use buffer index 2.
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
            [sceneEncoder endEncoding];
            [parallelEncoder endEncoding];
        }
        else
        {
            id<MTLRenderCommandEncoder> sceneEncoder =
                [commandBuffer renderCommandEncoderWithDescriptor:scenePass];
            if (!sceneEncoder)
            {
                dispatch_semaphore_signal(_inFlightSemaphore);
                return;
            }

            if (useProfiling)
            {
                [sceneEncoder pushDebugGroup:@"ScenePass"]; 
            }

            [sceneEncoder setRenderPipelineState:selectedScenePipeline];
            [sceneEncoder setDepthStencilState:_depthState];
            [sceneEncoder setCullMode:MTLCullModeBack];
            [sceneEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
            if (useICB)
            {
                [sceneEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
                [sceneEncoder setVertexBuffer:_uniformBuffers[uniformIndex] offset:0 atIndex:1];
                [sceneEncoder setFragmentBuffer:_uniformBuffers[uniformIndex] offset:0 atIndex:1];
                [sceneEncoder setFragmentBuffer:_materialArgumentBuffer offset:0 atIndex:2];
                [sceneEncoder setFragmentSamplerState:sceneSampler atIndex:0];
                if (useArgumentShader)
                {
                    // Argument-buffer topic: resource fetches use buffer index 2.
                }
                else
                {
                    [sceneEncoder setFragmentTexture:_albedoTexture atIndex:0];
                    [sceneEncoder setFragmentTexture:_normalTexture atIndex:1];
                }

                [sceneEncoder executeCommandsInBuffer:_indirectCommandBuffer withRange:NSMakeRange(0, 1)];
            }
            else
            {
                [sceneEncoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
                [sceneEncoder setVertexBuffer:_uniformBuffers[uniformIndex] offset:0 atIndex:1];
                [sceneEncoder setFragmentBuffer:_uniformBuffers[uniformIndex] offset:0 atIndex:1];
                [sceneEncoder setFragmentBuffer:_materialArgumentBuffer offset:0 atIndex:2];
                [sceneEncoder setFragmentSamplerState:sceneSampler atIndex:0];
                if (useArgumentShader)
                {
                    // Argument-buffer topic: resource fetches use buffer index 2.
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

            if (useProfiling)
            {
                [sceneEncoder popDebugGroup];
            }

            [sceneEncoder endEncoding];
        }

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
        [computeEncoder dispatchThreads:grid threadsPerThreadgroup:tgSize];
        for (uint32_t i = 0; i < extraStressPasses; ++i)
        {
            [computeEncoder dispatchThreads:grid threadsPerThreadgroup:tgSize];
        }
        [computeEncoder endEncoding];

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

        if (useBloom)
        {
            id<MTLComputeCommandEncoder> brightEncoder = [commandBuffer computeCommandEncoder];
            float threshold = (_demoTopic == MetalDemoTopicHDRBloomTAA) ? 1.30f : 0.90f;
            [brightEncoder setTexture:_sceneResolveTexture atIndex:0];
            [brightEncoder setTexture:_bloomTextureA atIndex:1];
            [brightEncoder setBytes:&threshold length:sizeof(float) atIndex:0];
            dispatch2D(brightEncoder, _brightExtractPipelineState, _bloomTextureA.width, _bloomTextureA.height);
            [brightEncoder endEncoding];

            id<MTLComputeCommandEncoder> blurHEncoder = [commandBuffer computeCommandEncoder];
            uint32_t horizontal = 1;
            [blurHEncoder setTexture:_bloomTextureA atIndex:0];
            [blurHEncoder setTexture:_bloomTextureB atIndex:1];
            [blurHEncoder setBytes:&horizontal length:sizeof(uint32_t) atIndex:0];
            dispatch2D(blurHEncoder, _blurPipelineState, _bloomTextureB.width, _bloomTextureB.height);
            [blurHEncoder endEncoding];

            id<MTLComputeCommandEncoder> blurVEncoder = [commandBuffer computeCommandEncoder];
            horizontal = 0;
            [blurVEncoder setTexture:_bloomTextureB atIndex:0];
            [blurVEncoder setTexture:_bloomTextureA atIndex:1];
            [blurVEncoder setBytes:&horizontal length:sizeof(uint32_t) atIndex:0];
            dispatch2D(blurVEncoder, _blurPipelineState, _bloomTextureA.width, _bloomTextureA.height);
            [blurVEncoder endEncoding];

            if (_errorExampleEnabled && _demoTopic == MetalDemoTopicHDRBloomTAA)
            {
                id<MTLComputeCommandEncoder> extraBlur = [commandBuffer computeCommandEncoder];
                horizontal = 1;
                [extraBlur setTexture:_bloomTextureA atIndex:0];
                [extraBlur setTexture:_bloomTextureB atIndex:1];
                [extraBlur setBytes:&horizontal length:sizeof(uint32_t) atIndex:0];
                dispatch2D(extraBlur, _blurPipelineState, _bloomTextureB.width, _bloomTextureB.height);
                [extraBlur endEncoding];
            }
        }

        if (useParticles)
        {
            id<MTLComputeCommandEncoder> particleEncoder = [commandBuffer computeCommandEncoder];
            [particleEncoder setTexture:_particleTexture atIndex:0];
            [particleEncoder setBytes:&elapsed length:sizeof(float) atIndex:0];
            dispatch2D(particleEncoder, _particlePipelineState, _particleTexture.width, _particleTexture.height);
            [particleEncoder endEncoding];
        }

        id<MTLTexture> sceneForPost = _sceneResolveTexture;
        if (useUpscale)
        {
            id<MTLComputeCommandEncoder> downsampleEncoder = [commandBuffer computeCommandEncoder];
            [downsampleEncoder setTexture:_sceneResolveTexture atIndex:0];
            [downsampleEncoder setTexture:_halfResTexture atIndex:1];
            dispatch2D(downsampleEncoder, _downsamplePipelineState, _halfResTexture.width, _halfResTexture.height);
            [downsampleEncoder endEncoding];

            id<MTLComputeCommandEncoder> upscaleEncoder = [commandBuffer computeCommandEncoder];
            [upscaleEncoder setTexture:_halfResTexture atIndex:0];
            [upscaleEncoder setTexture:_upscaledTexture atIndex:1];
            dispatch2D(upscaleEncoder, _upscalePipelineState, _upscaledTexture.width, _upscaledTexture.height);
            [upscaleEncoder endEncoding];

            sceneForPost = _upscaledTexture;
        }

        MTLRenderPassDescriptor *postPass = [MTLRenderPassDescriptor renderPassDescriptor];
        postPass.colorAttachments[0].texture = _postMSAATexture;
        postPass.colorAttachments[0].resolveTexture = drawable.texture;
        postPass.colorAttachments[0].loadAction = MTLLoadActionClear;
        postPass.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
        postPass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);

        id<MTLRenderCommandEncoder> postEncoder =
            [commandBuffer renderCommandEncoderWithDescriptor:postPass];
        if (!postEncoder)
        {
            dispatch_semaphore_signal(_inFlightSemaphore);
            return;
        }

        PostProcessParams params;
        params.edgeStrength = edgeStrength;
        params.sceneMix = sceneMix;
        params.bloomStrength = bloomStrength;
        params.particleStrength = particleStrength;
        params.temporalBlend = temporalBlend;
        params.exposure = exposureBias;
        params.texelSize = (simd_float2){1.0f / (float)_sceneResolveTexture.width,
                                         1.0f / (float)_sceneResolveTexture.height};

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

        if (temporalBlend > 0.0f || useBloom || useUpscale)
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

        if (useSyncScheduling)
        {
            if (_sharedEvent)
            {
                [commandBuffer encodeSignalEvent:_sharedEvent value:(uint64_t)_frameIndex];
            }
        }

        if (useProfiling)
        {
            [commandBuffer pushDebugGroup:@"FrameCommit"]; 
            [commandBuffer popDebugGroup];
        }

        double cpuFrameMs = (CFAbsoluteTimeGetCurrent() - cpuFrameStart) * 1000.0;
        double memoryMB = (double)[self estimatedVideoMemoryBytes] / (1024.0 * 1024.0);
        @synchronized (self)
        {
            _lastCPUFrameTimeMs = cpuFrameMs;
            _lastEstimatedMemoryMB = memoryMB;
            _lastTimeScale = timeScale;
            _lastEdgeStrength = edgeStrength;
            _lastExposure = exposureBias;
            _lastBloomStrength = bloomStrength;
            _lastParticleStrength = particleStrength;
            _lastTemporalBlend = temporalBlend;
        }

        [commandBuffer presentDrawable:drawable];
        [commandBuffer commit];
    }
}

@end