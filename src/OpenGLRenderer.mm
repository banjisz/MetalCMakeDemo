#import "OpenGLRenderer.h"

#import <OpenGL/gl3.h>

#include <math.h>
#include <stdlib.h>

typedef struct
{
    float baseTimeScale;
    float baseEdge;
    float baseExposure;
    float baseBloom;
    float baseParticle;
    float baseTemporal;
    const char *scenePath;
    const char *postPath;
    const char *upscalePath;
    const char *fallback;
} OpenGLThemeConfig;

static float clampf_local(float x, float lo, float hi)
{
    if (x < lo)
    {
        return lo;
    }
    if (x > hi)
    {
        return hi;
    }
    return x;
}

static OpenGLThemeConfig ThemeConfigForTopic(MetalDemoTopic topic)
{
    switch (topic)
    {
        case MetalDemoTopicResourceMemory:
            return (OpenGLThemeConfig){1.00f, 0.95f, 1.00f, 0.28f, 0.12f, 0.08f,
                                       "Core Buffer Lifecycle", "Light Post Mix", "Off", "No"};
        case MetalDemoTopicArgumentBuffer:
            return (OpenGLThemeConfig){1.00f, 1.00f, 1.00f, 0.30f, 0.10f, 0.10f,
                                       "Uniform Block Binding", "Palette Packing", "Off", "No"};
        case MetalDemoTopicFunctionConstants:
            return (OpenGLThemeConfig){1.00f, 1.05f, 1.02f, 0.30f, 0.12f, 0.12f,
                                       "Variant Branch Selection", "Mode Mix", "Off", "No"};
        case MetalDemoTopicIndirectCommandBuffer:
            return (OpenGLThemeConfig){1.04f, 1.05f, 1.05f, 0.32f, 0.16f, 0.12f,
                                       "Indirect-like Multi Draw", "Edge Assist", "Off", "No"};
        case MetalDemoTopicParallelEncoding:
            return (OpenGLThemeConfig){1.08f, 1.08f, 1.05f, 0.36f, 0.18f, 0.15f,
                                       "Layered Multi Pass", "Parallel-style Composite", "Off", "No"};
        case MetalDemoTopicDeferredLike:
            return (OpenGLThemeConfig){1.00f, 1.24f, 1.06f, 0.42f, 0.18f, 0.15f,
                                       "GBuffer-like Approx", "Edge + Composite", "Off", "No"};
        case MetalDemoTopicShadowing:
            return (OpenGLThemeConfig){1.00f, 1.00f, 0.94f, 0.26f, 0.10f, 0.10f,
                                       "Shadow Approx", "Visibility Modulation", "Off", "No"};
        case MetalDemoTopicPBR:
            return (OpenGLThemeConfig){1.00f, 1.04f, 1.08f, 0.34f, 0.08f, 0.12f,
                                       "PBR Fragment Approx", "Specular Tone", "Off", "No"};
        case MetalDemoTopicHDRBloomTAA:
            return (OpenGLThemeConfig){1.00f, 1.10f, 1.20f, 0.78f, 0.14f, 0.42f,
                                       "HDR Scene", "Bloom + Temporal", "Off", "No"};
        case MetalDemoTopicComputeParticles:
            return (OpenGLThemeConfig){1.00f, 1.10f, 1.08f, 0.44f, 0.82f, 0.28f,
                                       "Particle Emit Approx", "Particle Overlay", "Off", "No"};
        case MetalDemoTopicTextureAdvanced:
            return (OpenGLThemeConfig){1.00f, 1.20f, 1.06f, 0.38f, 0.10f, 0.14f,
                                       "Sampling Mode Approx", "Mipmap-like Pattern", "Off", "No"};
        case MetalDemoTopicSyncAndScheduling:
            return (OpenGLThemeConfig){0.96f, 1.00f, 1.00f, 0.30f, 0.08f, 0.60f,
                                       "Frame Pacing Step", "Temporal Cadence", "Off", "CPU Schedule Quantized"};
        case MetalDemoTopicRayTracing:
            return (OpenGLThemeConfig){1.00f, 1.08f, 1.06f, 0.40f, 0.12f, 0.18f,
                                       "Raster Reflection Approx", "Fallback Lighting", "Off", "Ray Query Fallback"};
        case MetalDemoTopicMetalFXLike:
            return (OpenGLThemeConfig){1.00f, 1.10f, 1.10f, 0.48f, 0.10f, 0.40f,
                                       "Half-res Emulation", "Reconstruction Blend", "Linear Upscale Approx", "No"};
        case MetalDemoTopicProfiling:
            return (OpenGLThemeConfig){1.00f, 1.12f, 1.02f, 0.34f, 0.26f, 0.20f,
                                       "Debug Marker Heatmap", "Instrumentation Overlay", "Off", "No"};
    }

    return (OpenGLThemeConfig){1.0f, 1.0f, 1.0f, 0.3f, 0.1f, 0.1f,
                               "Core Scene", "Post", "Off", "No"};
}

static GLuint CompileShader(GLenum type, const char *source)
{
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);

    GLint ok = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (ok == GL_TRUE)
    {
        return shader;
    }

    GLint logLength = 0;
    glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 1)
    {
        GLchar *log = (GLchar *)malloc((size_t)logLength);
        if (log)
        {
            glGetShaderInfoLog(shader, logLength, NULL, log);
            NSLog(@"OpenGL shader compile error: %s", log);
            free(log);
        }
    }

    glDeleteShader(shader);
    return 0;
}

static GLuint BuildProgram(const char *vertexSource, const char *fragmentSource)
{
    GLuint vs = CompileShader(GL_VERTEX_SHADER, vertexSource);
    GLuint fs = CompileShader(GL_FRAGMENT_SHADER, fragmentSource);
    if (vs == 0 || fs == 0)
    {
        if (vs != 0)
        {
            glDeleteShader(vs);
        }
        if (fs != 0)
        {
            glDeleteShader(fs);
        }
        return 0;
    }

    GLuint program = glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, fs);
    glBindAttribLocation(program, 0, "aPosition");
    glBindAttribLocation(program, 1, "aColor");
    glLinkProgram(program);

    glDeleteShader(vs);
    glDeleteShader(fs);

    GLint ok = GL_FALSE;
    glGetProgramiv(program, GL_LINK_STATUS, &ok);
    if (ok == GL_TRUE)
    {
        return program;
    }

    GLint logLength = 0;
    glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 1)
    {
        GLchar *log = (GLchar *)malloc((size_t)logLength);
        if (log)
        {
            glGetProgramInfoLog(program, logLength, NULL, log);
            NSLog(@"OpenGL program link error: %s", log);
            free(log);
        }
    }

    glDeleteProgram(program);
    return 0;
}

@interface OpenGLRenderer ()
{
    __weak NSOpenGLView *_view;

    GLuint _program;
    GLuint _vao;
    GLuint _vbo;

    GLint _timeUniform;
    GLint _topicUniform;
    GLint _errorUniform;
    GLint _edgeGainUniform;
    GLint _exposureGainUniform;
    GLint _tintUniform;
    GLint _offsetUniform;
    GLint _scaleUniform;
    GLint _twistUniform;
    GLint _resolutionUniform;
    GLint _alphaUniform;

    BOOL _ready;
    CFAbsoluteTime _startTime;
    CFAbsoluteTime _lastFrameTime;

    MetalDemoTopic _demoTopic;
    BOOL _errorExampleEnabled;
    float _userTimeScaleGain;
    float _userEdgeGain;
    float _userExposureGain;

    NSString *_scenePathSummary;
    NSString *_postPathSummary;
    NSString *_upscalePathSummary;
    NSString *_runtimeFallbackSummary;

    OpenGLRuntimeStats _stats;
}
@end

@implementation OpenGLRenderer

- (instancetype)initWithOpenGLView:(NSOpenGLView *)view
{
    self = [super init];
    if (!self)
    {
        return nil;
    }

    _view = view;
    if (!_view.openGLContext)
    {
        NSLog(@"OpenGL context is unavailable.");
        return self;
    }

    [_view.openGLContext makeCurrentContext];

    static const char *kVertexSource =
        "#version 150 core\n"
        "in vec2 aPosition;\n"
        "in vec3 aColor;\n"
        "out vec3 vColor;\n"
        "out vec2 vLocalPos;\n"
        "uniform float uTime;\n"
        "uniform vec2 uOffset;\n"
        "uniform float uScale;\n"
        "uniform float uTwist;\n"
        "void main()\n"
        "{\n"
        "    float angle = uTime * (0.65 + uTwist);\n"
        "    float c = cos(angle);\n"
        "    float s = sin(angle);\n"
        "    mat2 rot = mat2(c, -s, s, c);\n"
        "    vec2 p = rot * (aPosition * uScale);\n"
        "    p.x += 0.12 * sin(uTime * 0.6 + uOffset.y * 3.0);\n"
        "    vec2 finalPos = p + uOffset;\n"
        "    gl_Position = vec4(finalPos, 0.0, 1.0);\n"
        "    vColor = aColor;\n"
        "    vLocalPos = aPosition;\n"
        "}\n";

    static const char *kFragmentSource =
        "#version 150 core\n"
        "in vec3 vColor;\n"
        "in vec2 vLocalPos;\n"
        "out vec4 fragColor;\n"
        "uniform float uTime;\n"
        "uniform int uTopic;\n"
        "uniform int uError;\n"
        "uniform float uEdgeGain;\n"
        "uniform float uExposureGain;\n"
        "uniform vec3 uTint;\n"
        "uniform vec2 uResolution;\n"
        "uniform float uAlpha;\n"
        "float hash(vec2 p)\n"
        "{\n"
        "    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);\n"
        "}\n"
        "void main()\n"
        "{\n"
        "    float radius = length(vLocalPos);\n"
        "    vec3 color = vColor * uTint;\n"
        "    color *= 1.0 - 0.35 * radius;\n"
        "    if (uTopic == 1)\n"
        "    {\n"
        "        color *= vec3(1.05, 1.00, 0.95);\n"
        "    }\n"
        "    else if (uTopic == 2)\n"
        "    {\n"
        "        vec3 swizzled = vec3(color.b, color.r, color.g);\n"
        "        color = mix(color, swizzled, 0.35 + 0.25 * sin(uTime * 1.3));\n"
        "    }\n"
        "    else if (uTopic == 3)\n"
        "    {\n"
        "        color = pow(max(color, vec3(0.0)), vec3(0.90, 1.10, 1.20));\n"
        "    }\n"
        "    else if (uTopic == 4)\n"
        "    {\n"
        "        color *= 1.12;\n"
        "    }\n"
        "    else if (uTopic == 5)\n"
        "    {\n"
        "        color += vec3(0.08 * sin(uTime + vLocalPos.x * 8.0));\n"
        "    }\n"
        "    else if (uTopic == 6)\n"
        "    {\n"
        "        float edge = pow(clamp(1.0 - abs(vLocalPos.x * vLocalPos.y * 2.0), 0.0, 1.0), 4.0);\n"
        "        color += vec3(edge * 0.25 * uEdgeGain);\n"
        "    }\n"
        "    else if (uTopic == 7)\n"
        "    {\n"
        "        float shadow = clamp(0.78 - (vLocalPos.y + 0.5) * 0.6, 0.22, 1.0);\n"
        "        color *= shadow;\n"
        "    }\n"
        "    else if (uTopic == 8)\n"
        "    {\n"
        "        vec3 N = normalize(vec3(vLocalPos, sqrt(max(0.0, 1.0 - dot(vLocalPos, vLocalPos)))));\n"
        "        vec3 L = normalize(vec3(-0.35, 0.6, 0.7));\n"
        "        vec3 V = vec3(0.0, 0.0, 1.0);\n"
        "        vec3 H = normalize(L + V);\n"
        "        float ndl = max(dot(N, L), 0.0);\n"
        "        float ndh = max(dot(N, H), 0.0);\n"
        "        float rough = 0.35;\n"
        "        float spec = pow(ndh, mix(16.0, 96.0, 1.0 - rough));\n"
        "        color = color * (0.25 + 0.75 * ndl) + vec3(spec * 0.8);\n"
        "    }\n"
        "    else if (uTopic == 9)\n"
        "    {\n"
        "        float bloom = exp(-11.0 * radius);\n"
        "        color += bloom * vec3(0.9, 0.75, 0.45);\n"
        "        color = vec3(1.0) - exp(-color * (1.5 * uExposureGain));\n"
        "    }\n"
        "    else if (uTopic == 10)\n"
        "    {\n"
        "        vec2 p = vLocalPos * 22.0 + vec2(uTime * 3.0, -uTime * 1.7);\n"
        "        float spark = step(0.965, hash(floor(p)));\n"
        "        color += vec3(1.0, 0.8, 0.35) * spark * 0.9;\n"
        "    }\n"
        "    else if (uTopic == 11)\n"
        "    {\n"
        "        vec2 uv = vLocalPos * 0.5 + 0.5;\n"
        "        float c = step(0.5, fract(uv.x * 10.0)) * step(0.5, fract(uv.y * 10.0));\n"
        "        color = mix(color, color * vec3(0.75, 1.1, 0.9), c * 0.45);\n"
        "    }\n"
        "    else if (uTopic == 12)\n"
        "    {\n"
        "        float stepped = floor(uTime * 8.0) / 8.0;\n"
        "        color *= 0.88 + 0.12 * sin(stepped * 6.0);\n"
        "    }\n"
        "    else if (uTopic == 13)\n"
        "    {\n"
        "        float refl = smoothstep(1.0, 0.0, radius);\n"
        "        color = mix(color, vec3(0.35, 0.55, 0.85) * refl + color * 0.72, 0.4);\n"
        "    }\n"
        "    else if (uTopic == 14)\n"
        "    {\n"
        "        vec2 uv = vLocalPos * 0.5 + 0.5;\n"
        "        vec2 pix = floor(uv * vec2(24.0, 24.0)) / vec2(24.0, 24.0);\n"
        "        color = mix(color, vec3(pix.x, pix.y, 1.0 - pix.x) * 0.85, 0.38);\n"
        "    }\n"
        "    else if (uTopic == 15)\n"
        "    {\n"
        "        float heat = smoothstep(0.2, 1.0, abs(sin(uTime * 2.0 + vLocalPos.x * 7.0 + vLocalPos.y * 5.0)));\n"
        "        color = mix(color, vec3(heat, 0.18, 1.0 - heat), 0.42);\n"
        "    }\n"
        "    if (uError != 0)\n"
        "    {\n"
        "        float jitter = 0.92 + 0.35 * abs(sin(uTime * 2.7 + radius * 9.0));\n"
        "        color = pow(max(color * jitter, vec3(0.0)), vec3(0.78));\n"
        "        if (uTopic == 9 || uTopic == 14)\n"
        "        {\n"
        "            color += vec3(0.34, 0.16, 0.05);\n"
        "        }\n"
        "        if (uTopic == 12)\n"
        "        {\n"
        "            color *= 1.28;\n"
        "        }\n"
        "    }\n"
        "    color *= uExposureGain;\n"
        "    fragColor = vec4(clamp(color, 0.0, 1.0), clamp(uAlpha, 0.05, 1.0));\n"
        "}\n";

    _program = BuildProgram(kVertexSource, kFragmentSource);
    if (_program == 0)
    {
        return self;
    }

    _timeUniform = glGetUniformLocation(_program, "uTime");
    _topicUniform = glGetUniformLocation(_program, "uTopic");
    _errorUniform = glGetUniformLocation(_program, "uError");
    _edgeGainUniform = glGetUniformLocation(_program, "uEdgeGain");
    _exposureGainUniform = glGetUniformLocation(_program, "uExposureGain");
    _tintUniform = glGetUniformLocation(_program, "uTint");
    _offsetUniform = glGetUniformLocation(_program, "uOffset");
    _scaleUniform = glGetUniformLocation(_program, "uScale");
    _twistUniform = glGetUniformLocation(_program, "uTwist");
    _resolutionUniform = glGetUniformLocation(_program, "uResolution");
    _alphaUniform = glGetUniformLocation(_program, "uAlpha");

    static const float kTriangle[] = {
         0.0f,  0.70f, 1.0f, 0.35f, 0.20f,
        -0.75f, -0.55f, 0.20f, 0.75f, 1.0f,
         0.75f, -0.55f, 0.30f, 1.0f, 0.45f
    };

    glGenVertexArrays(1, &_vao);
    glGenBuffers(1, &_vbo);
    glBindVertexArray(_vao);
    glBindBuffer(GL_ARRAY_BUFFER, _vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(kTriangle), kTriangle, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, (GLsizei)(5 * sizeof(float)), (const GLvoid *)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, (GLsizei)(5 * sizeof(float)), (const GLvoid *)(2 * sizeof(float)));
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);

    _stats.cpuFrameTimeMs = 0.0;
    _stats.fpsEstimate = 0.0;
    _stats.frameIndex = 0;

    _demoTopic = MetalDemoTopicResourceMemory;
    _errorExampleEnabled = NO;
    _userTimeScaleGain = 1.0f;
    _userEdgeGain = 1.0f;
    _userExposureGain = 1.0f;

    _scenePathSummary = @"Core Scene";
    _postPathSummary = @"Post";
    _upscalePathSummary = @"Off";
    _runtimeFallbackSummary = @"No";

    _stats.timeScale = 1.0f;
    _stats.edgeStrength = 1.0f;
    _stats.exposure = 1.0f;
    _stats.bloomStrength = 0.3f;
    _stats.particleStrength = 0.1f;
    _stats.temporalBlend = 0.1f;
    _stats.errorExampleEnabled = NO;

    _startTime = CFAbsoluteTimeGetCurrent();
    _lastFrameTime = _startTime;
    _ready = YES;
    return self;
}

- (BOOL)isReady
{
    return _ready;
}

- (void)dealloc
{
    if (!_ready || !_view.openGLContext)
    {
        return;
    }

    [_view.openGLContext makeCurrentContext];
    if (_vbo != 0)
    {
        glDeleteBuffers(1, &_vbo);
        _vbo = 0;
    }
    if (_vao != 0)
    {
        glDeleteVertexArrays(1, &_vao);
        _vao = 0;
    }
    if (_program != 0)
    {
        glDeleteProgram(_program);
        _program = 0;
    }
}

- (void)render
{
    if (!_ready || !_view || !_view.openGLContext)
    {
        return;
    }

    CFAbsoluteTime begin = CFAbsoluteTimeGetCurrent();

    [_view.openGLContext makeCurrentContext];
    [_view.openGLContext update];

    NSRect bounds = _view.bounds;
    CGFloat scale = _view.window ? _view.window.backingScaleFactor : 1.0;
    GLsizei width = (GLsizei)lrint(bounds.size.width * scale);
    GLsizei height = (GLsizei)lrint(bounds.size.height * scale);
    if (width <= 0 || height <= 0)
    {
        return;
    }

    glViewport(0, 0, width, height);
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    OpenGLThemeConfig cfg = ThemeConfigForTopic(_demoTopic);

    float timeScale = cfg.baseTimeScale * _userTimeScaleGain;
    float edgeStrength = cfg.baseEdge * _userEdgeGain;
    float exposure = cfg.baseExposure * _userExposureGain;
    float bloomStrength = cfg.baseBloom;
    float particleStrength = cfg.baseParticle;
    float temporalBlend = cfg.baseTemporal;

    if (_errorExampleEnabled)
    {
        switch (_demoTopic)
        {
            case MetalDemoTopicIndirectCommandBuffer:
                timeScale *= 1.18f;
                break;
            case MetalDemoTopicHDRBloomTAA:
            case MetalDemoTopicMetalFXLike:
                exposure *= 1.22f;
                bloomStrength *= 1.30f;
                temporalBlend *= 1.35f;
                break;
            case MetalDemoTopicComputeParticles:
                particleStrength *= 1.35f;
                break;
            case MetalDemoTopicSyncAndScheduling:
                temporalBlend *= 1.30f;
                break;
            default:
                exposure *= 1.10f;
                break;
        }
    }

    float t = (float)(CFAbsoluteTimeGetCurrent() - _startTime) * timeScale;

    float clearBias = (float)_demoTopic * 0.17f;
    float r = 0.07f + 0.05f * sinf(t * 0.60f + clearBias);
    float g = 0.10f + 0.05f * cosf(t * 0.45f + clearBias * 0.7f);
    float b = 0.16f + 0.05f * sinf(t * 0.33f + 1.2f + clearBias * 0.5f);
    if (_errorExampleEnabled)
    {
        r *= 1.18f;
        g *= 0.92f;
        b *= 0.86f;
    }

    r = clampf_local(r, 0.0f, 1.0f);
    g = clampf_local(g, 0.0f, 1.0f);
    b = clampf_local(b, 0.0f, 1.0f);

    glClearColor(r, g, b, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    NSUInteger instanceCount = 1;
    NSUInteger passCount = 1;
    switch (_demoTopic)
    {
        case MetalDemoTopicIndirectCommandBuffer:
            instanceCount = 3;
            break;
        case MetalDemoTopicParallelEncoding:
            instanceCount = 5;
            passCount = 2;
            break;
        case MetalDemoTopicComputeParticles:
            instanceCount = 12;
            break;
        case MetalDemoTopicMetalFXLike:
            passCount = 2;
            break;
        case MetalDemoTopicProfiling:
            instanceCount = 4;
            passCount = 2;
            break;
        default:
            break;
    }

    glUseProgram(_program);
    if (_timeUniform >= 0)
    {
        glUniform1f(_timeUniform, t);
    }
    if (_topicUniform >= 0)
    {
        glUniform1i(_topicUniform, (GLint)_demoTopic);
    }
    if (_errorUniform >= 0)
    {
        glUniform1i(_errorUniform, _errorExampleEnabled ? 1 : 0);
    }
    if (_edgeGainUniform >= 0)
    {
        glUniform1f(_edgeGainUniform, edgeStrength);
    }
    if (_exposureGainUniform >= 0)
    {
        glUniform1f(_exposureGainUniform, exposure);
    }
    if (_resolutionUniform >= 0)
    {
        glUniform2f(_resolutionUniform, (float)width, (float)height);
    }

    glBindVertexArray(_vao);

    for (NSUInteger pass = 0; pass < passCount; ++pass)
    {
        float passBlend = (passCount > 1) ? ((pass == 0) ? 0.70f : 0.45f) : 1.0f;
        float passShift = (passCount > 1) ? ((pass == 0) ? 0.0f : 0.06f) : 0.0f;

        for (NSUInteger i = 0; i < instanceCount; ++i)
        {
            float spread = (instanceCount > 1) ? ((float)i / (float)(instanceCount - 1) - 0.5f) : 0.0f;
            float offsetX = spread * 0.90f;
            float offsetY = 0.0f;

            if (_demoTopic == MetalDemoTopicComputeParticles)
            {
                float fi = (float)i;
                offsetX = 0.75f * sinf(t * 0.7f + fi * 0.55f);
                offsetY = 0.45f * cosf(t * 0.9f + fi * 0.37f);
            }
            else if (_demoTopic == MetalDemoTopicParallelEncoding || _demoTopic == MetalDemoTopicProfiling)
            {
                offsetY = spread * 0.45f + passShift;
            }
            else
            {
                offsetY = passShift;
            }

            float scale = 0.82f;
            if (_demoTopic == MetalDemoTopicComputeParticles)
            {
                scale = 0.16f + 0.02f * (float)(i % 4);
            }
            else if (instanceCount > 1)
            {
                scale = 0.58f + 0.04f * (float)(i % 3);
            }

            float twist = 0.04f * (float)(i + 1) + 0.06f * (float)(pass + 1);
            float tintR = 0.65f + 0.35f * sinf(t * 0.8f + (float)i * 0.7f + (float)_demoTopic * 0.1f);
            float tintG = 0.65f + 0.35f * sinf(t * 0.6f + (float)i * 0.9f + 1.5f);
            float tintB = 0.65f + 0.35f * sinf(t * 0.7f + (float)i * 0.5f + 2.8f);

            if (_offsetUniform >= 0)
            {
                glUniform2f(_offsetUniform, offsetX, offsetY);
            }
            if (_scaleUniform >= 0)
            {
                glUniform1f(_scaleUniform, scale);
            }
            if (_twistUniform >= 0)
            {
                glUniform1f(_twistUniform, twist);
            }
            if (_tintUniform >= 0)
            {
                glUniform3f(_tintUniform,
                            clampf_local(tintR, 0.0f, 1.0f),
                            clampf_local(tintG, 0.0f, 1.0f),
                            clampf_local(tintB, 0.0f, 1.0f));
            }
            if (_alphaUniform >= 0)
            {
                float alpha = passBlend;
                if (_demoTopic == MetalDemoTopicComputeParticles)
                {
                    alpha = 0.22f + 0.05f * (float)(i % 4);
                }
                glUniform1f(_alphaUniform, clampf_local(alpha, 0.08f, 1.0f));
            }

            glDrawArrays(GL_TRIANGLES, 0, 3);
        }
    }

    glBindVertexArray(0);
    glUseProgram(0);

    [_view.openGLContext flushBuffer];

    CFAbsoluteTime end = CFAbsoluteTimeGetCurrent();
    double frameMs = (end - begin) * 1000.0;
    double dt = end - _lastFrameTime;
    _lastFrameTime = end;

    _stats.cpuFrameTimeMs = frameMs;
    if (dt > 0.0001)
    {
        _stats.fpsEstimate = 1.0 / dt;
    }

    _scenePathSummary = [NSString stringWithUTF8String:cfg.scenePath ?: "OpenGL Scene"];
    _postPathSummary = [NSString stringWithUTF8String:cfg.postPath ?: "Post"];
    _upscalePathSummary = [NSString stringWithUTF8String:cfg.upscalePath ?: "Off"];
    _runtimeFallbackSummary = [NSString stringWithUTF8String:cfg.fallback ?: "No"];

    _stats.timeScale = timeScale;
    _stats.edgeStrength = edgeStrength;
    _stats.exposure = exposure;
    _stats.bloomStrength = bloomStrength;
    _stats.particleStrength = particleStrength;
    _stats.temporalBlend = temporalBlend;
    _stats.errorExampleEnabled = _errorExampleEnabled;
    _stats.frameIndex += 1;
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
    _userTimeScaleGain = clampf_local(timeScale, 0.25f, 3.0f);
    _userEdgeGain = clampf_local(edgeGain, 0.10f, 3.0f);
    _userExposureGain = clampf_local(exposureGain, 0.25f, 3.0f);
}

- (OpenGLRuntimeStats)runtimeStats
{
    return _stats;
}

- (NSString *)scenePathSummary
{
    return _scenePathSummary ?: @"OpenGL Scene";
}

- (NSString *)postPathSummary
{
    return _postPathSummary ?: @"Post";
}

- (NSString *)upscalePathSummary
{
    return _upscalePathSummary ?: @"Off";
}

- (NSString *)runtimePathSummary
{
    return [NSString stringWithFormat:@"%@ / %@ / %@",
            [self scenePathSummary],
            [self postPathSummary],
            [self upscalePathSummary]];
}

- (NSString *)runtimeFallbackSummary
{
    return _runtimeFallbackSummary ?: @"No";
}

- (NSString *)errorExampleSummary
{
    switch (_demoTopic)
    {
        case MetalDemoTopicResourceMemory:
            return @"放大缓冲重绑定频率，模拟资源抖动。";
        case MetalDemoTopicArgumentBuffer:
            return @"故意打乱颜色绑定映射，观察绑定错误。";
        case MetalDemoTopicFunctionConstants:
            return @"频繁切换分支模式，模拟变体抖动。";
        case MetalDemoTopicIndirectCommandBuffer:
            return @"提高多实例提交负载，模拟命令组织不佳。";
        case MetalDemoTopicParallelEncoding:
            return @"叠加 pass 过量，观察合成压力。";
        case MetalDemoTopicDeferredLike:
            return @"边缘参数过高，出现明显伪影。";
        case MetalDemoTopicShadowing:
            return @"阴影强度超界，暗部层次被压扁。";
        case MetalDemoTopicPBR:
            return @"高光能量过大，材质失真。";
        case MetalDemoTopicHDRBloomTAA:
            return @"Bloom 与 temporal 过强，产生拖影与过曝。";
        case MetalDemoTopicComputeParticles:
            return @"粒子层数过多，导致画面拥挤和抖动。";
        case MetalDemoTopicTextureAdvanced:
            return @"采样强化过度，纹理边缘闪烁。";
        case MetalDemoTopicSyncAndScheduling:
            return @"时间步长离散化过强，节奏不稳定。";
        case MetalDemoTopicRayTracing:
            return @"反射近似过亮，暴露回退路径缺陷。";
        case MetalDemoTopicMetalFXLike:
            return @"重建权重过大，出现锐化与光晕。";
        case MetalDemoTopicProfiling:
            return @"热力覆盖过多，掩盖真实画面信息。";
    }

    return @"错误示例未定义。";
}

@end
