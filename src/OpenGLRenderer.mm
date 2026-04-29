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

typedef struct
{
    float m[16];
} Mat4;

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

static Mat4 Mat4Identity(void)
{
    Mat4 r = {{
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f
    }};
    return r;
}

static Mat4 Mat4Multiply(Mat4 a, Mat4 b)
{
    Mat4 r = {{0.0f}};
    for (int c = 0; c < 4; ++c)
    {
        for (int row = 0; row < 4; ++row)
        {
            float v = 0.0f;
            for (int k = 0; k < 4; ++k)
            {
                v += a.m[k * 4 + row] * b.m[c * 4 + k];
            }
            r.m[c * 4 + row] = v;
        }
    }
    return r;
}

static Mat4 Mat4Translation(float tx, float ty, float tz)
{
    Mat4 r = Mat4Identity();
    r.m[12] = tx;
    r.m[13] = ty;
    r.m[14] = tz;
    return r;
}

static Mat4 Mat4Scale(float sx, float sy, float sz)
{
    Mat4 r = {{
        sx,   0.0f, 0.0f, 0.0f,
        0.0f, sy,   0.0f, 0.0f,
        0.0f, 0.0f, sz,   0.0f,
        0.0f, 0.0f, 0.0f, 1.0f
    }};
    return r;
}

static Mat4 Mat4RotationX(float angle)
{
    float c = cosf(angle);
    float s = sinf(angle);
    Mat4 r = {{
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, c,    s,    0.0f,
        0.0f, -s,   c,    0.0f,
        0.0f, 0.0f, 0.0f, 1.0f
    }};
    return r;
}

static Mat4 Mat4RotationY(float angle)
{
    float c = cosf(angle);
    float s = sinf(angle);
    Mat4 r = {{
         c,   0.0f, -s,   0.0f,
         0.0f,1.0f, 0.0f, 0.0f,
         s,   0.0f, c,    0.0f,
         0.0f,0.0f, 0.0f, 1.0f
    }};
    return r;
}

static Mat4 Mat4Perspective(float fovYRadians, float aspect, float nearZ, float farZ)
{
    float f = 1.0f / tanf(fovYRadians * 0.5f);
    float nf = 1.0f / (nearZ - farZ);
    Mat4 r = {{
        f / aspect, 0.0f, 0.0f,                          0.0f,
        0.0f,       f,    0.0f,                          0.0f,
        0.0f,       0.0f, (farZ + nearZ) * nf,         -1.0f,
        0.0f,       0.0f, (2.0f * farZ * nearZ) * nf,   0.0f
    }};
    return r;
}

static Mat4 Mat4Ortho(float left, float right, float bottom, float top, float nearZ, float farZ)
{
    float rl = right - left;
    float tb = top - bottom;
    float fn = farZ - nearZ;
    if (fabsf(rl) < 1e-5f || fabsf(tb) < 1e-5f || fabsf(fn) < 1e-5f)
    {
        return Mat4Identity();
    }

    Mat4 r = {{
        2.0f / rl, 0.0f,      0.0f,       0.0f,
        0.0f,      2.0f / tb, 0.0f,       0.0f,
        0.0f,      0.0f,     -2.0f / fn,  0.0f,
        -(right + left) / rl,
        -(top + bottom) / tb,
        -(farZ + nearZ) / fn,
        1.0f
    }};
    return r;
}

static void Vec3Normalize(float *x, float *y, float *z)
{
    float len = sqrtf((*x) * (*x) + (*y) * (*y) + (*z) * (*z));
    if (len < 1e-6f)
    {
        *x = 0.0f;
        *y = 0.0f;
        *z = 1.0f;
        return;
    }
    float inv = 1.0f / len;
    *x *= inv;
    *y *= inv;
    *z *= inv;
}

static Mat4 Mat4LookAt(float eyeX,
                       float eyeY,
                       float eyeZ,
                       float centerX,
                       float centerY,
                       float centerZ,
                       float upX,
                       float upY,
                       float upZ)
{
    float fx = centerX - eyeX;
    float fy = centerY - eyeY;
    float fz = centerZ - eyeZ;
    Vec3Normalize(&fx, &fy, &fz);

    float upnx = upX;
    float upny = upY;
    float upnz = upZ;
    Vec3Normalize(&upnx, &upny, &upnz);

    float sx = fy * upnz - fz * upny;
    float sy = fz * upnx - fx * upnz;
    float sz = fx * upny - fy * upnx;
    Vec3Normalize(&sx, &sy, &sz);

    float ux = sy * fz - sz * fy;
    float uy = sz * fx - sx * fz;
    float uz = sx * fy - sy * fx;

    Mat4 r = {{
        sx,  ux,  -fx, 0.0f,
        sy,  uy,  -fy, 0.0f,
        sz,  uz,  -fz, 0.0f,
        0.0f,0.0f,0.0f,1.0f
    }};

    Mat4 t = Mat4Translation(-eyeX, -eyeY, -eyeZ);
    return Mat4Multiply(r, t);
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

    GLuint _cubeProgram;
    GLuint _cubeVAO;
    GLuint _cubeVBO;
    GLuint _cubeEBO;

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

    GLint _cubeTimeUniform;
    GLint _cubeTopicUniform;
    GLint _cubeErrorUniform;
    GLint _cubeEdgeGainUniform;
    GLint _cubeExposureGainUniform;
    GLint _cubeTintUniform;
    GLint _cubeAlphaUniform;
    GLint _cubeMVPUniform;
    GLint _cubeModelUniform;
    GLint _cubeBloomUniform;
    GLint _cubeParticleUniform;
    GLint _cubeTemporalUniform;
    GLint _cubeLightMVPUniform;
    GLint _cubeShadowMapUniform;
    GLint _cubeUseShadowUniform;
    GLint _cubeShadowStrengthUniform;
    GLint _cubeShadowBiasUniform;
    GLint _cubeShadowPCFRadiusUniform;
    GLint _cubeHeatThresholdUniform;
    GLint _cubeHeatCoolUniform;
    GLint _cubeHeatMidUniform;
    GLint _cubeHeatHotUniform;
    GLint _cubeHeatPeakUniform;

    GLuint _shadowProgram;
    GLint _shadowMVPUniform;
    GLuint _shadowFBO;
    GLuint _shadowDepthTex;
    int _shadowMapSize;

    GLuint _quadVAO;
    GLuint _quadVBO;

    GLuint _sceneFBO;
    GLuint _sceneColorTex;
    GLuint _sceneDepthRBO;
    GLuint _bloomFBO[2];
    GLuint _bloomTex[2];
    GLuint _historyTex;
    GLsizei _postWidth;
    GLsizei _postHeight;

    GLuint _postExtractProgram;
    GLint _postExtractSceneUniform;
    GLint _postExtractThresholdAUniform;
    GLint _postExtractThresholdBUniform;

    GLuint _postBlurProgram;
    GLint _postBlurSourceUniform;
    GLint _postBlurDirectionUniform;
    GLint _postBlurTexelSizeUniform;

    GLuint _postCompositeProgram;
    GLint _postCompositeSceneUniform;
    GLint _postCompositeBloomUniform;
    GLint _postCompositeHistoryUniform;
    GLint _postCompositeBloomStrengthUniform;
    GLint _postCompositeTemporalUniform;
    GLint _postCompositeUseTemporalUniform;

    GLuint _legendProgram;
    GLint _legendResolutionUniform;
    GLint _legendTimeUniform;

    BOOL _ready;
    CFAbsoluteTime _startTime;
    CFAbsoluteTime _lastFrameTime;

    MetalDemoTopic _demoTopic;
    OpenGLRenderMode _renderMode;
    BOOL _errorExampleEnabled;
    float _userTimeScaleGain;
    float _userEdgeGain;
    float _userExposureGain;
    float _userTopic9ThresholdA;
    float _userTopic9ThresholdB;
    NSInteger _userTopic9BlurPassCount;

    NSString *_scenePathSummary;
    NSString *_postPathSummary;
    NSString *_upscalePathSummary;
    NSString *_runtimeFallbackSummary;

    OpenGLRuntimeStats _stats;
}

- (void)renderTriangleWithTime:(float)t
                    topicConfig:(OpenGLThemeConfig)cfg
                   edgeStrength:(float)edgeStrength
                       exposure:(float)exposure;
- (void)renderCubeWithTime:(float)t
                topicConfig:(OpenGLThemeConfig)cfg
               edgeStrength:(float)edgeStrength
                   exposure:(float)exposure
                  bloomStrength:(float)bloomStrength
              particleStrength:(float)particleStrength
                  temporalBlend:(float)temporalBlend
                shadowBias:(float)shadowBias
            shadowPCFRadius:(float)shadowPCFRadius
            bloomThresholdA:(float)bloomThresholdA
            bloomThresholdB:(float)bloomThresholdB
              bloomBlurPasses:(NSInteger)bloomBlurPasses
             heatThreshold1:(float)heatThreshold1
             heatThreshold2:(float)heatThreshold2
             heatThreshold3:(float)heatThreshold3
                      width:(GLsizei)width
                     height:(GLsizei)height;
- (void)drawFullscreenQuad;
- (BOOL)ensurePostProcessResourcesWithWidth:(GLsizei)width height:(GLsizei)height;
- (BOOL)ensureShadowResources;
- (void)renderCubeShadowPassWithLightVP:(Mat4)lightVP
                                  instanceCount:(NSUInteger)instanceCount
                                      layerCount:(NSUInteger)layerCount
                                              time:(float)t;
- (void)renderCubeScenePassWithProjection:(Mat4)projection
                                                  view:(Mat4)view
                                              lightVP:(Mat4)lightVP
                                     instanceCount:(NSUInteger)instanceCount
                                         layerCount:(NSUInteger)layerCount
                                                 time:(float)t
                                      edgeStrength:(float)edgeStrength
                                            exposure:(float)exposure
                                     bloomStrength:(float)bloomStrength
                                 particleStrength:(float)particleStrength
                                     temporalBlend:(float)temporalBlend
                                        shadowBias:(float)shadowBias
                                  shadowPCFRadius:(float)shadowPCFRadius
                                  heatThreshold1:(float)heatThreshold1
                                  heatThreshold2:(float)heatThreshold2
                                  heatThreshold3:(float)heatThreshold3;
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

    static const char *kCubeVertexSource =
        "#version 150 core\n"
        "in vec3 aPosition;\n"
        "in vec3 aColor;\n"
        "out vec3 vColor;\n"
        "out vec3 vWorldPos;\n"
        "out vec3 vWorldNormal;\n"
        "uniform mat4 uMVP;\n"
        "uniform mat4 uModel;\n"
        "void main()\n"
        "{\n"
        "    vec4 wp = uModel * vec4(aPosition, 1.0);\n"
        "    vWorldPos = wp.xyz;\n"
        "    vWorldNormal = normalize(mat3(uModel) * normalize(aPosition));\n"
        "    vColor = aColor;\n"
        "    gl_Position = uMVP * vec4(aPosition, 1.0);\n"
        "}\n";

    static const char *kCubeFragmentSource =
        "#version 150 core\n"
        "in vec3 vColor;\n"
        "in vec3 vWorldPos;\n"
        "in vec3 vWorldNormal;\n"
        "out vec4 fragColor;\n"
        "uniform float uTime;\n"
        "uniform int uTopic;\n"
        "uniform int uError;\n"
        "uniform float uEdgeGain;\n"
        "uniform float uExposureGain;\n"
        "uniform float uBloomStrength;\n"
        "uniform float uParticleStrength;\n"
        "uniform float uTemporalBlend;\n"
        "uniform vec3 uTint;\n"
        "uniform float uAlpha;\n"
        "uniform mat4 uLightMVP;\n"
        "uniform sampler2D uShadowMap;\n"
        "uniform int uUseShadowMap;\n"
        "uniform float uShadowStrength;\n"
        "uniform float uShadowBias;\n"
        "uniform float uShadowPCFRadius;\n"
        "uniform vec3 uHeatThresholds;\n"
        "uniform vec3 uHeatCool;\n"
        "uniform vec3 uHeatMid;\n"
        "uniform vec3 uHeatHot;\n"
        "uniform vec3 uHeatPeak;\n"
        "float saturate(float x)\n"
        "{\n"
        "    return clamp(x, 0.0, 1.0);\n"
        "}\n"
        "float hash(vec2 p)\n"
        "{\n"
        "    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);\n"
        "}\n"
        "vec3 heatmapLayered(float t)\n"
        "{\n"
        "    float h0 = clamp(uHeatThresholds.x, 0.05, 0.85);\n"
        "    float h1 = clamp(max(h0 + 0.03, uHeatThresholds.y), h0 + 0.03, 0.95);\n"
        "    float h2 = clamp(max(h1 + 0.03, uHeatThresholds.z), h1 + 0.03, 0.99);\n"
        "    vec3 c = mix(uHeatCool, uHeatMid, smoothstep(0.0, h0, t));\n"
        "    c = mix(c, uHeatHot, smoothstep(h0, h1, t));\n"
        "    c = mix(c, uHeatPeak, smoothstep(h1, h2, t));\n"
        "    return c;\n"
        "}\n"
        "vec3 toneMap(vec3 c)\n"
        "{\n"
        "    return vec3(1.0) - exp(-c);\n"
        "}\n"
        "float shadowVisibility(vec3 worldPos, vec3 normal, vec3 lightDir)\n"
        "{\n"
        "    if (uUseShadowMap == 0)\n"
        "    {\n"
        "        return 1.0;\n"
        "    }\n"
        "    vec4 ls = uLightMVP * vec4(worldPos, 1.0);\n"
        "    vec3 ndc = ls.xyz / max(ls.w, 1e-4);\n"
        "    vec2 uv = ndc.xy * 0.5 + 0.5;\n"
        "    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)\n"
        "    {\n"
        "        return 1.0;\n"
        "    }\n"
        "    float receiver = ndc.z * 0.5 + 0.5;\n"
        "    float baseBias = max(uShadowBias, 0.00005);\n"
        "    float bias = max(baseBias, baseBias * 2.2 * (1.0 - max(dot(normal, lightDir), 0.0)));\n"
        "    int radius = int(clamp(floor(uShadowPCFRadius + 0.5), 1.0, 3.0));\n"
        "    vec2 texel = 1.0 / vec2(textureSize(uShadowMap, 0));\n"
        "    float vis = 0.0;\n"
        "    float count = 0.0;\n"
        "    for (int y = -3; y <= 3; ++y)\n"
        "    {\n"
        "        for (int x = -3; x <= 3; ++x)\n"
        "        {\n"
        "            if (abs(x) > radius || abs(y) > radius)\n"
        "            {\n"
        "                continue;\n"
        "            }\n"
        "            float depth = texture(uShadowMap, uv + vec2(x, y) * texel).r;\n"
        "            vis += (receiver - bias <= depth) ? 1.0 : 0.0;\n"
        "            count += 1.0;\n"
        "        }\n"
        "    }\n"
        "    return (count > 0.0) ? (vis / count) : 1.0;\n"
        "}\n"
        "void main()\n"
        "{\n"
        "    vec3 p = abs(vWorldPos);\n"
        "    float edge = max(max(p.x, p.y), p.z);\n"
        "    vec3 baseColor = vColor * uTint;\n"
        "    vec3 N = normalize(vWorldNormal);\n"
        "    vec3 V = normalize(vec3(0.0, 0.0, 1.0));\n"
        "    vec3 L = normalize(vec3(-0.42, 0.68, 0.59));\n"
        "    vec3 H = normalize(L + V);\n"
        "    float ndl = max(dot(N, L), 0.0);\n"
        "    float ndv = max(dot(N, V), 0.0);\n"
        "    float ndh = max(dot(N, H), 0.0);\n"
        "    float vdh = max(dot(V, H), 0.0);\n"
        "    float roughness = 0.56;\n"
        "    float metallic = 0.06;\n"
        "    if (uTopic == 8)\n"
        "    {\n"
        "        roughness = 0.28;\n"
        "        metallic = 0.80;\n"
        "    }\n"
        "    float a = max(0.04, roughness * roughness);\n"
        "    float a2 = a * a;\n"
        "    float denom = ndh * ndh * (a2 - 1.0) + 1.0;\n"
        "    float D = a2 / (3.1415926 * denom * denom + 1e-4);\n"
        "    float k = (roughness + 1.0);\n"
        "    k = k * k * 0.125;\n"
        "    float Gv = ndv / (ndv * (1.0 - k) + k + 1e-4);\n"
        "    float Gl = ndl / (ndl * (1.0 - k) + k + 1e-4);\n"
        "    float G = Gv * Gl;\n"
        "    vec3 F0 = mix(vec3(0.04), baseColor, metallic);\n"
        "    vec3 F = F0 + (1.0 - F0) * pow(1.0 - vdh, 5.0);\n"
        "    vec3 specular = (D * G) * F / max(4.0 * ndv * ndl, 1e-3);\n"
        "    vec3 diffuse = (1.0 - metallic) * baseColor / 3.1415926;\n"
        "    vec3 color = (diffuse + specular) * ndl + baseColor * 0.16;\n"
        "    color *= 0.78 + 0.22 * edge * uEdgeGain;\n"
        "    if (uTopic == 1)\n"
        "    {\n"
        "        color *= vec3(1.03, 1.0, 0.96);\n"
        "    }\n"
        "    if (uTopic == 2)\n"
        "    {\n"
        "        color = mix(color, color.bgr, 0.28);\n"
        "    }\n"
        "    else if (uTopic == 3)\n"
        "    {\n"
        "        float variant = floor(fract(uTime * 0.35) * 3.0);\n"
        "        if (variant < 0.5)\n"
        "        {\n"
        "            color = pow(max(color, vec3(0.0)), vec3(0.92, 1.08, 1.18));\n"
        "        }\n"
        "        else if (variant < 1.5)\n"
        "        {\n"
        "            color = color.bgr * vec3(1.0, 0.95, 1.05);\n"
        "        }\n"
        "        else\n"
        "        {\n"
        "            color *= 1.08;\n"
        "        }\n"
        "    }\n"
        "    else if (uTopic == 4)\n"
        "    {\n"
        "        color *= 1.06 + 0.07 * sin(uTime * 1.6 + vWorldPos.x * 4.0);\n"
        "    }\n"
        "    else if (uTopic == 5)\n"
        "    {\n"
        "        color += 0.08 * sin(vec3(1.0, 1.3, 1.7) * (uTime + vWorldPos.y * 5.0));\n"
        "    }\n"
        "    else if (uTopic == 6)\n"
        "    {\n"
        "        float seam = smoothstep(0.35, 0.50, edge);\n"
        "        color += vec3(seam * 0.24 * uEdgeGain);\n"
        "        color += vec3(0.04, 0.06, 0.08) * (0.5 + 0.5 * sin(uTime * 2.0));\n"
        "    }\n"
        "    else if (uTopic == 7)\n"
        "    {\n"
        "        float vis = shadowVisibility(vWorldPos, N, L);\n"
        "        vis = mix(1.0 - uShadowStrength, 1.0, vis);\n"
        "        color *= vis;\n"
        "        color += vec3(0.02, 0.03, 0.05) * (1.0 - vis);\n"
        "    }\n"
        "    else if (uTopic == 8)\n"
        "    {\n"
        "        color += specular * 0.6;\n"
        "        color = mix(color, color * vec3(1.03, 0.98, 0.94), 0.25);\n"
        "    }\n"
        "    else if (uTopic == 9)\n"
        "    {\n"
        "        float glow = exp(-6.0 * length(vWorldPos));\n"
        "        vec3 hdr = color + glow * vec3(1.15, 0.84, 0.48) * (1.1 + uBloomStrength);\n"
        "        float taaPhase = 0.5 + 0.5 * sin(uTime * 2.2 + vWorldPos.x * 5.0 + vWorldPos.y * 3.0);\n"
        "        hdr = mix(hdr, hdr * vec3(0.9, 1.05, 1.1), taaPhase * uTemporalBlend * 0.38);\n"
        "        color = hdr;\n"
        "    }\n"
        "    else if (uTopic == 10)\n"
        "    {\n"
        "        float sparkle = step(0.975, hash(floor(vWorldPos.xy * 34.0 + vec2(uTime * 7.0, -uTime * 5.0))));\n"
        "        color += vec3(1.0, 0.85, 0.4) * sparkle * (0.6 + uParticleStrength);\n"
        "    }\n"
        "    else if (uTopic == 11)\n"
        "    {\n"
        "        vec2 uv = vWorldPos.xz * 3.8;\n"
        "        float checker = step(0.5, fract(uv.x)) * step(0.5, fract(uv.y));\n"
        "        color = mix(color, color * vec3(0.78, 1.1, 0.92), checker * 0.4);\n"
        "    }\n"
        "    else if (uTopic == 12)\n"
        "    {\n"
        "        float stepped = floor(uTime * 9.0) / 9.0;\n"
        "        color *= 0.9 + 0.1 * sin(stepped * 6.0);\n"
        "    }\n"
        "    else if (uTopic == 13)\n"
        "    {\n"
        "        vec3 R = reflect(-V, N);\n"
        "        float refl = pow(1.0 - max(dot(N, V), 0.0), 3.0);\n"
        "        vec3 env = vec3(0.22, 0.45, 0.78) * (0.4 + 0.6 * (R.y * 0.5 + 0.5));\n"
        "        color = mix(color, color + env * 0.75, refl * 0.65);\n"
        "    }\n"
        "    else if (uTopic == 14)\n"
        "    {\n"
        "        vec3 q = floor((vWorldPos + 1.2) * 8.0) / 8.0;\n"
        "        vec3 recon = abs(q);\n"
        "        color = mix(color, recon, 0.24 + 0.35 * uTemporalBlend);\n"
        "    }\n"
        "    else if (uTopic == 15)\n"
        "    {\n"
        "        float hot = abs(sin(uTime * 2.6 + vWorldPos.x * 6.0 + vWorldPos.y * 4.0 + vWorldPos.z * 5.0));\n"
        "        float zone = 0.0;\n"
        "        zone += step(uHeatThresholds.x, hot) * 0.3333;\n"
        "        zone += step(uHeatThresholds.y, hot) * 0.3333;\n"
        "        zone += step(uHeatThresholds.z, hot) * 0.3334;\n"
        "        zone = clamp(zone, 0.0, 1.0);\n"
        "        vec3 heat = heatmapLayered(zone);\n"
        "        vec3 fine = heatmapLayered(hot);\n"
        "        float contour = smoothstep(0.45, 0.55, fract(hot * 10.0));\n"
        "        color = mix(color, heat, 0.58);\n"
        "        color = mix(color, fine, 0.22);\n"
        "        color += mix(uHeatHot, uHeatPeak, contour) * (0.08 + 0.05 * contour);\n"
        "    }\n"
        "    if (uError != 0)\n"
        "    {\n"
        "        float pulse = 0.85 + 0.42 * abs(sin(uTime * 2.5 + edge * 10.0));\n"
        "        color = pow(max(color * pulse, vec3(0.0)), vec3(0.78));\n"
        "        if (uTopic == 9 || uTopic == 14)\n"
        "        {\n"
        "            color += vec3(0.30, 0.12, 0.06);\n"
        "        }\n"
        "    }\n"
        "    color = toneMap(color * uExposureGain);\n"
        "    fragColor = vec4(clamp(color, 0.0, 1.0), clamp(uAlpha, 0.08, 1.0));\n"
        "}\n";

    _cubeProgram = BuildProgram(kCubeVertexSource, kCubeFragmentSource);
    if (_cubeProgram == 0)
    {
        return self;
    }

    _cubeTimeUniform = glGetUniformLocation(_cubeProgram, "uTime");
    _cubeTopicUniform = glGetUniformLocation(_cubeProgram, "uTopic");
    _cubeErrorUniform = glGetUniformLocation(_cubeProgram, "uError");
    _cubeEdgeGainUniform = glGetUniformLocation(_cubeProgram, "uEdgeGain");
    _cubeExposureGainUniform = glGetUniformLocation(_cubeProgram, "uExposureGain");
    _cubeBloomUniform = glGetUniformLocation(_cubeProgram, "uBloomStrength");
    _cubeParticleUniform = glGetUniformLocation(_cubeProgram, "uParticleStrength");
    _cubeTemporalUniform = glGetUniformLocation(_cubeProgram, "uTemporalBlend");
    _cubeTintUniform = glGetUniformLocation(_cubeProgram, "uTint");
    _cubeAlphaUniform = glGetUniformLocation(_cubeProgram, "uAlpha");
    _cubeMVPUniform = glGetUniformLocation(_cubeProgram, "uMVP");
    _cubeModelUniform = glGetUniformLocation(_cubeProgram, "uModel");
    _cubeLightMVPUniform = glGetUniformLocation(_cubeProgram, "uLightMVP");
    _cubeShadowMapUniform = glGetUniformLocation(_cubeProgram, "uShadowMap");
    _cubeUseShadowUniform = glGetUniformLocation(_cubeProgram, "uUseShadowMap");
    _cubeShadowStrengthUniform = glGetUniformLocation(_cubeProgram, "uShadowStrength");
    _cubeShadowBiasUniform = glGetUniformLocation(_cubeProgram, "uShadowBias");
    _cubeShadowPCFRadiusUniform = glGetUniformLocation(_cubeProgram, "uShadowPCFRadius");
    _cubeHeatThresholdUniform = glGetUniformLocation(_cubeProgram, "uHeatThresholds");
    _cubeHeatCoolUniform = glGetUniformLocation(_cubeProgram, "uHeatCool");
    _cubeHeatMidUniform = glGetUniformLocation(_cubeProgram, "uHeatMid");
    _cubeHeatHotUniform = glGetUniformLocation(_cubeProgram, "uHeatHot");
    _cubeHeatPeakUniform = glGetUniformLocation(_cubeProgram, "uHeatPeak");

    static const float kCubeVertices[] = {
        -0.5f, -0.5f, -0.5f, 1.0f, 0.35f, 0.20f,
         0.5f, -0.5f, -0.5f, 0.2f, 0.75f, 1.0f,
         0.5f,  0.5f, -0.5f, 0.3f, 1.0f, 0.45f,
        -0.5f,  0.5f, -0.5f, 1.0f, 0.9f, 0.35f,
        -0.5f, -0.5f,  0.5f, 0.8f, 0.45f, 1.0f,
         0.5f, -0.5f,  0.5f, 0.2f, 1.0f, 0.7f,
         0.5f,  0.5f,  0.5f, 1.0f, 0.55f, 0.35f,
        -0.5f,  0.5f,  0.5f, 0.55f, 0.9f, 1.0f
    };

    static const GLushort kCubeIndices[] = {
        0, 1, 2, 2, 3, 0,
        4, 5, 6, 6, 7, 4,
        0, 4, 7, 7, 3, 0,
        1, 5, 6, 6, 2, 1,
        3, 2, 6, 6, 7, 3,
        0, 1, 5, 5, 4, 0
    };

    glGenVertexArrays(1, &_cubeVAO);
    glGenBuffers(1, &_cubeVBO);
    glGenBuffers(1, &_cubeEBO);
    glBindVertexArray(_cubeVAO);
    glBindBuffer(GL_ARRAY_BUFFER, _cubeVBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(kCubeVertices), kCubeVertices, GL_STATIC_DRAW);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, _cubeEBO);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(kCubeIndices), kCubeIndices, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, (GLsizei)(6 * sizeof(float)), (const GLvoid *)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, (GLsizei)(6 * sizeof(float)), (const GLvoid *)(3 * sizeof(float)));
    glBindVertexArray(0);

    static const float kQuadVertices[] = {
        -1.0f, -1.0f,
         1.0f, -1.0f,
        -1.0f,  1.0f,
         1.0f,  1.0f
    };

    glGenVertexArrays(1, &_quadVAO);
    glGenBuffers(1, &_quadVBO);
    glBindVertexArray(_quadVAO);
    glBindBuffer(GL_ARRAY_BUFFER, _quadVBO);
    glBufferData(GL_ARRAY_BUFFER, sizeof(kQuadVertices), kQuadVertices, GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, (GLsizei)(2 * sizeof(float)), (const GLvoid *)0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);

    static const char *kFullscreenVertexSource =
        "#version 150 core\n"
        "in vec2 aPosition;\n"
        "out vec2 vUV;\n"
        "void main()\n"
        "{\n"
        "    vUV = aPosition * 0.5 + 0.5;\n"
        "    gl_Position = vec4(aPosition, 0.0, 1.0);\n"
        "}\n";

    static const char *kShadowVertexSource =
        "#version 150 core\n"
        "in vec3 aPosition;\n"
        "uniform mat4 uMVP;\n"
        "void main()\n"
        "{\n"
        "    gl_Position = uMVP * vec4(aPosition, 1.0);\n"
        "}\n";

    static const char *kShadowFragmentSource =
        "#version 150 core\n"
        "void main()\n"
        "{\n"
        "}\n";

    _shadowProgram = BuildProgram(kShadowVertexSource, kShadowFragmentSource);
    if (_shadowProgram == 0)
    {
        return self;
    }
    _shadowMVPUniform = glGetUniformLocation(_shadowProgram, "uMVP");

    static const char *kBloomExtractFragmentSource =
        "#version 150 core\n"
        "in vec2 vUV;\n"
        "out vec4 fragColor;\n"
        "uniform sampler2D uSceneTex;\n"
        "uniform float uThresholdA;\n"
        "uniform float uThresholdB;\n"
        "void main()\n"
        "{\n"
        "    vec3 c = texture(uSceneTex, vUV).rgb;\n"
        "    float l = max(max(c.r, c.g), c.b);\n"
        "    float a = smoothstep(uThresholdA, uThresholdA + 0.25, l);\n"
        "    float b = smoothstep(uThresholdB, uThresholdB + 0.20, l);\n"
        "    vec3 bloom = c * (0.55 * a + 0.90 * b);\n"
        "    fragColor = vec4(bloom, 1.0);\n"
        "}\n";

    _postExtractProgram = BuildProgram(kFullscreenVertexSource, kBloomExtractFragmentSource);
    if (_postExtractProgram == 0)
    {
        return self;
    }
    _postExtractSceneUniform = glGetUniformLocation(_postExtractProgram, "uSceneTex");
    _postExtractThresholdAUniform = glGetUniformLocation(_postExtractProgram, "uThresholdA");
    _postExtractThresholdBUniform = glGetUniformLocation(_postExtractProgram, "uThresholdB");

    static const char *kBloomBlurFragmentSource =
        "#version 150 core\n"
        "in vec2 vUV;\n"
        "out vec4 fragColor;\n"
        "uniform sampler2D uSourceTex;\n"
        "uniform vec2 uDirection;\n"
        "uniform vec2 uTexelSize;\n"
        "void main()\n"
        "{\n"
        "    vec2 stepVec = uDirection * uTexelSize;\n"
        "    vec3 c = texture(uSourceTex, vUV).rgb * 0.227027;\n"
        "    c += texture(uSourceTex, vUV + stepVec * 1.384615).rgb * 0.316216;\n"
        "    c += texture(uSourceTex, vUV - stepVec * 1.384615).rgb * 0.316216;\n"
        "    c += texture(uSourceTex, vUV + stepVec * 3.230769).rgb * 0.070270;\n"
        "    c += texture(uSourceTex, vUV - stepVec * 3.230769).rgb * 0.070270;\n"
        "    fragColor = vec4(c, 1.0);\n"
        "}\n";

    _postBlurProgram = BuildProgram(kFullscreenVertexSource, kBloomBlurFragmentSource);
    if (_postBlurProgram == 0)
    {
        return self;
    }
    _postBlurSourceUniform = glGetUniformLocation(_postBlurProgram, "uSourceTex");
    _postBlurDirectionUniform = glGetUniformLocation(_postBlurProgram, "uDirection");
    _postBlurTexelSizeUniform = glGetUniformLocation(_postBlurProgram, "uTexelSize");

    static const char *kBloomCompositeFragmentSource =
        "#version 150 core\n"
        "in vec2 vUV;\n"
        "out vec4 fragColor;\n"
        "uniform sampler2D uSceneTex;\n"
        "uniform sampler2D uBloomTex;\n"
        "uniform sampler2D uHistoryTex;\n"
        "uniform float uBloomStrength;\n"
        "uniform float uTemporalBlend;\n"
        "uniform int uUseTemporal;\n"
        "void main()\n"
        "{\n"
        "    vec3 scene = texture(uSceneTex, vUV).rgb;\n"
        "    vec3 bloom = texture(uBloomTex, vUV).rgb;\n"
        "    vec3 c = scene + bloom * uBloomStrength;\n"
        "    if (uUseTemporal != 0)\n"
        "    {\n"
        "        vec3 hist = texture(uHistoryTex, vUV).rgb;\n"
        "        float t = clamp(uTemporalBlend, 0.0, 0.85) * 0.45;\n"
        "        c = mix(c, hist, t);\n"
        "    }\n"
        "    fragColor = vec4(clamp(c, 0.0, 1.0), 1.0);\n"
        "}\n";

    _postCompositeProgram = BuildProgram(kFullscreenVertexSource, kBloomCompositeFragmentSource);
    if (_postCompositeProgram == 0)
    {
        return self;
    }
    _postCompositeSceneUniform = glGetUniformLocation(_postCompositeProgram, "uSceneTex");
    _postCompositeBloomUniform = glGetUniformLocation(_postCompositeProgram, "uBloomTex");
    _postCompositeHistoryUniform = glGetUniformLocation(_postCompositeProgram, "uHistoryTex");
    _postCompositeBloomStrengthUniform = glGetUniformLocation(_postCompositeProgram, "uBloomStrength");
    _postCompositeTemporalUniform = glGetUniformLocation(_postCompositeProgram, "uTemporalBlend");
    _postCompositeUseTemporalUniform = glGetUniformLocation(_postCompositeProgram, "uUseTemporal");

    static const char *kLegendFragmentSource =
        "#version 150 core\n"
        "out vec4 fragColor;\n"
        "uniform vec2 uResolution;\n"
        "uniform float uTime;\n"
        "float saturate(float x)\n"
        "{\n"
        "    return clamp(x, 0.0, 1.0);\n"
        "}\n"
        "vec3 heat(float t)\n"
        "{\n"
        "    float r = saturate(1.9 - abs(2.5 * t - 1.3));\n"
        "    float g = saturate(1.7 - abs(2.5 * t - 0.7));\n"
        "    float b = saturate(1.5 - abs(2.5 * t - 0.2));\n"
        "    return vec3(r, g, b);\n"
        "}\n"
        "void main()\n"
        "{\n"
        "    vec2 uv = gl_FragCoord.xy / max(uResolution, vec2(1.0));\n"
        "    vec2 p0 = vec2(0.025, 0.035);\n"
        "    vec2 p1 = vec2(0.290, 0.245);\n"
        "    if (uv.x < p0.x || uv.x > p1.x || uv.y < p0.y || uv.y > p1.y)\n"
        "    {\n"
        "        fragColor = vec4(0.0);\n"
        "        return;\n"
        "    }\n"
        "    vec2 lv = (uv - p0) / (p1 - p0);\n"
        "    vec3 bg = vec3(0.06, 0.07, 0.08);\n"
        "    vec3 c = bg;\n"
        "    float border = step(lv.x, 0.02) + step(0.98, lv.x) + step(lv.y, 0.02) + step(0.98, lv.y);\n"
        "    if (border > 0.0)\n"
        "    {\n"
        "        c = vec3(0.45, 0.50, 0.55);\n"
        "    }\n"
        "    float barMask = step(0.18, lv.y) * step(lv.y, 0.42);\n"
        "    if (barMask > 0.0)\n"
        "    {\n"
        "        float z = floor(lv.x * 4.0) / 3.0;\n"
        "        c = mix(c, heat(z), 0.88);\n"
        "    }\n"
        "    float laneMask = step(0.56, lv.y) * step(lv.y, 0.88);\n"
        "    if (laneMask > 0.0)\n"
        "    {\n"
        "        float lane = floor((1.0 - lv.x) * 4.0);\n"
        "        float pulse = 0.58 + 0.42 * abs(sin(uTime * 2.2 + lane * 1.7));\n"
        "        c = mix(c, heat(lane / 3.0) * pulse, 0.80);\n"
        "    }\n"
        "    fragColor = vec4(c, 0.78);\n"
        "}\n";

    _legendProgram = BuildProgram(kFullscreenVertexSource, kLegendFragmentSource);
    if (_legendProgram == 0)
    {
        return self;
    }
    _legendResolutionUniform = glGetUniformLocation(_legendProgram, "uResolution");
    _legendTimeUniform = glGetUniformLocation(_legendProgram, "uTime");

    _shadowMapSize = 1536;
    _postWidth = 0;
    _postHeight = 0;

    _stats.cpuFrameTimeMs = 0.0;
    _stats.fpsEstimate = 0.0;
    _stats.frameIndex = 0;

    _demoTopic = MetalDemoTopicResourceMemory;
    _renderMode = OpenGLRenderModeTriangle;
    _errorExampleEnabled = NO;
    _userTimeScaleGain = 1.0f;
    _userEdgeGain = 1.0f;
    _userExposureGain = 1.0f;
    _userTopic9ThresholdA = 0.56f;
    _userTopic9ThresholdB = 0.88f;
    _userTopic9BlurPassCount = 6;

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
    _stats.shadowBias = 0.0012f;
    _stats.shadowPCFRadius = 2.0f;
    _stats.topic9ThresholdA = _userTopic9ThresholdA;
    _stats.topic9ThresholdB = _userTopic9ThresholdB;
    _stats.topic9BlurPassCount = _userTopic9BlurPassCount;
    _stats.heatThreshold1 = 0.28f;
    _stats.heatThreshold2 = 0.56f;
    _stats.heatThreshold3 = 0.82f;
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
    if (_cubeEBO != 0)
    {
        glDeleteBuffers(1, &_cubeEBO);
        _cubeEBO = 0;
    }
    if (_cubeVBO != 0)
    {
        glDeleteBuffers(1, &_cubeVBO);
        _cubeVBO = 0;
    }
    if (_cubeVAO != 0)
    {
        glDeleteVertexArrays(1, &_cubeVAO);
        _cubeVAO = 0;
    }
    if (_cubeProgram != 0)
    {
        glDeleteProgram(_cubeProgram);
        _cubeProgram = 0;
    }

    if (_sceneDepthRBO != 0)
    {
        glDeleteRenderbuffers(1, &_sceneDepthRBO);
        _sceneDepthRBO = 0;
    }
    if (_sceneColorTex != 0)
    {
        glDeleteTextures(1, &_sceneColorTex);
        _sceneColorTex = 0;
    }
    if (_sceneFBO != 0)
    {
        glDeleteFramebuffers(1, &_sceneFBO);
        _sceneFBO = 0;
    }
    if (_bloomTex[0] != 0 || _bloomTex[1] != 0)
    {
        glDeleteTextures(2, _bloomTex);
        _bloomTex[0] = 0;
        _bloomTex[1] = 0;
    }
    if (_bloomFBO[0] != 0 || _bloomFBO[1] != 0)
    {
        glDeleteFramebuffers(2, _bloomFBO);
        _bloomFBO[0] = 0;
        _bloomFBO[1] = 0;
    }
    if (_historyTex != 0)
    {
        glDeleteTextures(1, &_historyTex);
        _historyTex = 0;
    }

    if (_shadowDepthTex != 0)
    {
        glDeleteTextures(1, &_shadowDepthTex);
        _shadowDepthTex = 0;
    }
    if (_shadowFBO != 0)
    {
        glDeleteFramebuffers(1, &_shadowFBO);
        _shadowFBO = 0;
    }
    if (_shadowProgram != 0)
    {
        glDeleteProgram(_shadowProgram);
        _shadowProgram = 0;
    }

    if (_postExtractProgram != 0)
    {
        glDeleteProgram(_postExtractProgram);
        _postExtractProgram = 0;
    }
    if (_postBlurProgram != 0)
    {
        glDeleteProgram(_postBlurProgram);
        _postBlurProgram = 0;
    }
    if (_postCompositeProgram != 0)
    {
        glDeleteProgram(_postCompositeProgram);
        _postCompositeProgram = 0;
    }
    if (_legendProgram != 0)
    {
        glDeleteProgram(_legendProgram);
        _legendProgram = 0;
    }

    if (_quadVBO != 0)
    {
        glDeleteBuffers(1, &_quadVBO);
        _quadVBO = 0;
    }
    if (_quadVAO != 0)
    {
        glDeleteVertexArrays(1, &_quadVAO);
        _quadVAO = 0;
    }
}

- (void)drawFullscreenQuad
{
    glBindVertexArray(_quadVAO);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glBindVertexArray(0);
}

- (BOOL)ensurePostProcessResourcesWithWidth:(GLsizei)width height:(GLsizei)height
{
    if (width <= 0 || height <= 0)
    {
        return NO;
    }

    if (_postWidth == width && _postHeight == height && _sceneFBO != 0 && _historyTex != 0)
    {
        return YES;
    }

    if (_sceneDepthRBO != 0)
    {
        glDeleteRenderbuffers(1, &_sceneDepthRBO);
        _sceneDepthRBO = 0;
    }
    if (_sceneColorTex != 0)
    {
        glDeleteTextures(1, &_sceneColorTex);
        _sceneColorTex = 0;
    }
    if (_sceneFBO != 0)
    {
        glDeleteFramebuffers(1, &_sceneFBO);
        _sceneFBO = 0;
    }
    if (_bloomTex[0] != 0 || _bloomTex[1] != 0)
    {
        glDeleteTextures(2, _bloomTex);
        _bloomTex[0] = 0;
        _bloomTex[1] = 0;
    }
    if (_bloomFBO[0] != 0 || _bloomFBO[1] != 0)
    {
        glDeleteFramebuffers(2, _bloomFBO);
        _bloomFBO[0] = 0;
        _bloomFBO[1] = 0;
    }
    if (_historyTex != 0)
    {
        glDeleteTextures(1, &_historyTex);
        _historyTex = 0;
    }

    glGenTextures(1, &_sceneColorTex);
    glBindTexture(GL_TEXTURE_2D, _sceneColorTex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glGenRenderbuffers(1, &_sceneDepthRBO);
    glBindRenderbuffer(GL_RENDERBUFFER, _sceneDepthRBO);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, width, height);

    glGenFramebuffers(1, &_sceneFBO);
    glBindFramebuffer(GL_FRAMEBUFFER, _sceneFBO);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _sceneColorTex, 0);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, _sceneDepthRBO);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        NSLog(@"OpenGL scene framebuffer incomplete.");
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        return NO;
    }

    glGenTextures(2, _bloomTex);
    glGenFramebuffers(2, _bloomFBO);
    for (int i = 0; i < 2; ++i)
    {
        glBindTexture(GL_TEXTURE_2D, _bloomTex[i]);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, NULL);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

        glBindFramebuffer(GL_FRAMEBUFFER, _bloomFBO[i]);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _bloomTex[i], 0);
        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
        {
            NSLog(@"OpenGL bloom framebuffer %d incomplete.", i);
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            return NO;
        }
    }

    glGenTextures(1, &_historyTex);
    glBindTexture(GL_TEXTURE_2D, _historyTex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA16F, width, height, 0, GL_RGBA, GL_FLOAT, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    GLuint clearFBO = 0;
    glGenFramebuffers(1, &clearFBO);
    glBindFramebuffer(GL_FRAMEBUFFER, clearFBO);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _historyTex, 0);
    glViewport(0, 0, width, height);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    if (clearFBO != 0)
    {
        glDeleteFramebuffers(1, &clearFBO);
    }

    glBindTexture(GL_TEXTURE_2D, 0);
    _postWidth = width;
    _postHeight = height;
    return YES;
}

- (BOOL)ensureShadowResources
{
    if (_shadowFBO != 0 && _shadowDepthTex != 0)
    {
        return YES;
    }

    if (_shadowMapSize <= 0)
    {
        _shadowMapSize = 1536;
    }

    glGenTextures(1, &_shadowDepthTex);
    glBindTexture(GL_TEXTURE_2D, _shadowDepthTex);
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_DEPTH_COMPONENT24,
                 _shadowMapSize,
                 _shadowMapSize,
                 0,
                 GL_DEPTH_COMPONENT,
                 GL_FLOAT,
                 NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glGenFramebuffers(1, &_shadowFBO);
    glBindFramebuffer(GL_FRAMEBUFFER, _shadowFBO);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, _shadowDepthTex, 0);
    glDrawBuffer(GL_NONE);
    glReadBuffer(GL_NONE);

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
    {
        NSLog(@"OpenGL shadow framebuffer incomplete.");
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        return NO;
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    return YES;
}

- (void)renderCubeShadowPassWithLightVP:(Mat4)lightVP
                          instanceCount:(NSUInteger)instanceCount
                             layerCount:(NSUInteger)layerCount
                                   time:(float)t
{
    if (_shadowProgram == 0 || _shadowFBO == 0)
    {
        return;
    }

    glBindFramebuffer(GL_FRAMEBUFFER, _shadowFBO);
    glViewport(0, 0, _shadowMapSize, _shadowMapSize);
    glEnable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);
    glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
    glDepthMask(GL_TRUE);
    glClear(GL_DEPTH_BUFFER_BIT);

    glUseProgram(_shadowProgram);
    glBindVertexArray(_cubeVAO);

    for (NSUInteger layer = 0; layer < layerCount; ++layer)
    {
        float zBias = (layerCount > 1) ? ((layer == 0) ? 0.0f : -0.75f) : 0.0f;
        for (NSUInteger i = 0; i < instanceCount; ++i)
        {
            float fi = (float)i;
            float spread = (instanceCount > 1) ? (fi / (float)(instanceCount - 1) - 0.5f) : 0.0f;

            float tx = spread * 2.2f;
            float ty = 0.0f;
            float tz = zBias;

            if (_demoTopic == MetalDemoTopicComputeParticles)
            {
                tx = 1.6f * sinf(t * 0.9f + fi * 0.51f);
                ty = 1.0f * cosf(t * 1.1f + fi * 0.35f);
                tz += -0.6f + 0.8f * sinf(t * 0.7f + fi * 0.27f);
            }
            else if (_demoTopic == MetalDemoTopicParallelEncoding || _demoTopic == MetalDemoTopicProfiling)
            {
                ty = spread * 0.8f + (layerCount > 1 ? ((layer == 0) ? 0.1f : -0.1f) : 0.0f);
            }

            float sx = 0.78f;
            if (instanceCount > 1)
            {
                sx = 0.42f + 0.05f * (float)(i % 3);
            }
            if (_demoTopic == MetalDemoTopicComputeParticles)
            {
                sx = 0.22f + 0.04f * (float)(i % 4);
            }

            float rotX = t * (0.60f + 0.05f * (float)(i % 4)) + fi * 0.37f;
            float rotY = t * (0.90f + 0.07f * (float)(i % 5)) + fi * 0.51f;

            Mat4 model = Mat4Identity();
            model = Mat4Multiply(model, Mat4Translation(tx, ty, tz));
            model = Mat4Multiply(model, Mat4RotationY(rotY));
            model = Mat4Multiply(model, Mat4RotationX(rotX));
            model = Mat4Multiply(model, Mat4Scale(sx, sx, sx));

            Mat4 shadowMVP = Mat4Multiply(lightVP, model);
            if (_shadowMVPUniform >= 0)
            {
                glUniformMatrix4fv(_shadowMVPUniform, 1, GL_FALSE, shadowMVP.m);
            }

            glDrawElements(GL_TRIANGLES, 36, GL_UNSIGNED_SHORT, (const GLvoid *)0);
        }
    }

    glBindVertexArray(0);
    glUseProgram(0);
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

- (void)renderCubeScenePassWithProjection:(Mat4)projection
                                      view:(Mat4)view
                                   lightVP:(Mat4)lightVP
                            instanceCount:(NSUInteger)instanceCount
                               layerCount:(NSUInteger)layerCount
                                     time:(float)t
                             edgeStrength:(float)edgeStrength
                                 exposure:(float)exposure
                            bloomStrength:(float)bloomStrength
                         particleStrength:(float)particleStrength
                                     temporalBlend:(float)temporalBlend
                                        shadowBias:(float)shadowBias
                                  shadowPCFRadius:(float)shadowPCFRadius
                                  heatThreshold1:(float)heatThreshold1
                                  heatThreshold2:(float)heatThreshold2
                                  heatThreshold3:(float)heatThreshold3
{
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glUseProgram(_cubeProgram);
    if (_cubeTimeUniform >= 0)
    {
        glUniform1f(_cubeTimeUniform, t);
    }
    if (_cubeTopicUniform >= 0)
    {
        glUniform1i(_cubeTopicUniform, (GLint)_demoTopic);
    }
    if (_cubeErrorUniform >= 0)
    {
        glUniform1i(_cubeErrorUniform, _errorExampleEnabled ? 1 : 0);
    }
    if (_cubeEdgeGainUniform >= 0)
    {
        glUniform1f(_cubeEdgeGainUniform, edgeStrength);
    }
    if (_cubeExposureGainUniform >= 0)
    {
        glUniform1f(_cubeExposureGainUniform, exposure);
    }
    if (_cubeBloomUniform >= 0)
    {
        glUniform1f(_cubeBloomUniform, bloomStrength);
    }
    if (_cubeParticleUniform >= 0)
    {
        glUniform1f(_cubeParticleUniform, particleStrength);
    }
    if (_cubeTemporalUniform >= 0)
    {
        glUniform1f(_cubeTemporalUniform, temporalBlend);
    }

    BOOL useShadow = (_demoTopic == MetalDemoTopicShadowing && _shadowDepthTex != 0);
    if (_cubeUseShadowUniform >= 0)
    {
        glUniform1i(_cubeUseShadowUniform, useShadow ? 1 : 0);
    }
    if (_cubeShadowStrengthUniform >= 0)
    {
        glUniform1f(_cubeShadowStrengthUniform, 0.78f);
    }
    if (_cubeShadowBiasUniform >= 0)
    {
        glUniform1f(_cubeShadowBiasUniform, shadowBias);
    }
    if (_cubeShadowPCFRadiusUniform >= 0)
    {
        glUniform1f(_cubeShadowPCFRadiusUniform, shadowPCFRadius);
    }
    if (_cubeShadowMapUniform >= 0)
    {
        glActiveTexture(GL_TEXTURE3);
        glBindTexture(GL_TEXTURE_2D, _shadowDepthTex);
        glUniform1i(_cubeShadowMapUniform, 3);
        glActiveTexture(GL_TEXTURE0);
    }

    float heatT1 = clampf_local(heatThreshold1, 0.05f, 0.90f);
    float heatT2 = clampf_local(fmaxf(heatT1 + 0.03f, heatThreshold2), heatT1 + 0.03f, 0.95f);
    float heatT3 = clampf_local(fmaxf(heatT2 + 0.03f, heatThreshold3), heatT2 + 0.03f, 0.99f);
    if (_cubeHeatThresholdUniform >= 0)
    {
        glUniform3f(_cubeHeatThresholdUniform, heatT1, heatT2, heatT3);
    }

    const float heatCool[3] = {0.10f, 0.32f, 0.92f};
    const float heatMid[3] = {0.05f, 0.82f, 0.46f};
    const float heatHot[3] = {1.00f, 0.74f, 0.20f};
    const float heatPeak[3] = {0.98f, 0.20f, 0.12f};
    if (_cubeHeatCoolUniform >= 0)
    {
        glUniform3f(_cubeHeatCoolUniform, heatCool[0], heatCool[1], heatCool[2]);
    }
    if (_cubeHeatMidUniform >= 0)
    {
        glUniform3f(_cubeHeatMidUniform, heatMid[0], heatMid[1], heatMid[2]);
    }
    if (_cubeHeatHotUniform >= 0)
    {
        glUniform3f(_cubeHeatHotUniform, heatHot[0], heatHot[1], heatHot[2]);
    }
    if (_cubeHeatPeakUniform >= 0)
    {
        glUniform3f(_cubeHeatPeakUniform, heatPeak[0], heatPeak[1], heatPeak[2]);
    }

    glBindVertexArray(_cubeVAO);
    for (NSUInteger layer = 0; layer < layerCount; ++layer)
    {
        float layerAlpha = (layerCount > 1) ? ((layer == 0) ? 0.95f : 0.55f) : 1.0f;
        float zBias = (layerCount > 1) ? ((layer == 0) ? 0.0f : -0.75f) : 0.0f;

        for (NSUInteger i = 0; i < instanceCount; ++i)
        {
            float fi = (float)i;
            float spread = (instanceCount > 1) ? (fi / (float)(instanceCount - 1) - 0.5f) : 0.0f;

            float tx = spread * 2.2f;
            float ty = 0.0f;
            float tz = zBias;

            if (_demoTopic == MetalDemoTopicComputeParticles)
            {
                tx = 1.6f * sinf(t * 0.9f + fi * 0.51f);
                ty = 1.0f * cosf(t * 1.1f + fi * 0.35f);
                tz += -0.6f + 0.8f * sinf(t * 0.7f + fi * 0.27f);
            }
            else if (_demoTopic == MetalDemoTopicParallelEncoding || _demoTopic == MetalDemoTopicProfiling)
            {
                ty = spread * 0.8f + (layerCount > 1 ? ((layer == 0) ? 0.1f : -0.1f) : 0.0f);
            }

            float sx = 0.78f;
            if (instanceCount > 1)
            {
                sx = 0.42f + 0.05f * (float)(i % 3);
            }
            if (_demoTopic == MetalDemoTopicComputeParticles)
            {
                sx = 0.22f + 0.04f * (float)(i % 4);
            }

            float rotX = t * (0.60f + 0.05f * (float)(i % 4)) + fi * 0.37f;
            float rotY = t * (0.90f + 0.07f * (float)(i % 5)) + fi * 0.51f;

            Mat4 model = Mat4Identity();
            model = Mat4Multiply(model, Mat4Translation(tx, ty, tz));
            model = Mat4Multiply(model, Mat4RotationY(rotY));
            model = Mat4Multiply(model, Mat4RotationX(rotX));
            model = Mat4Multiply(model, Mat4Scale(sx, sx, sx));

            Mat4 vp = Mat4Multiply(projection, view);
            Mat4 mvp = Mat4Multiply(vp, model);
            Mat4 lightMVP = Mat4Multiply(lightVP, model);

            float tintR = 0.68f + 0.32f * sinf(t * 0.7f + fi * 0.65f + (float)_demoTopic * 0.1f);
            float tintG = 0.68f + 0.32f * sinf(t * 0.6f + fi * 0.85f + 1.1f);
            float tintB = 0.68f + 0.32f * sinf(t * 0.8f + fi * 0.45f + 2.4f);

            if (_cubeMVPUniform >= 0)
            {
                glUniformMatrix4fv(_cubeMVPUniform, 1, GL_FALSE, mvp.m);
            }
            if (_cubeModelUniform >= 0)
            {
                glUniformMatrix4fv(_cubeModelUniform, 1, GL_FALSE, model.m);
            }
            if (_cubeLightMVPUniform >= 0)
            {
                glUniformMatrix4fv(_cubeLightMVPUniform, 1, GL_FALSE, lightMVP.m);
            }
            if (_cubeTintUniform >= 0)
            {
                glUniform3f(_cubeTintUniform,
                            clampf_local(tintR, 0.0f, 1.0f),
                            clampf_local(tintG, 0.0f, 1.0f),
                            clampf_local(tintB, 0.0f, 1.0f));
            }
            if (_cubeAlphaUniform >= 0)
            {
                float alpha = layerAlpha;
                if (_demoTopic == MetalDemoTopicComputeParticles)
                {
                    alpha = 0.25f + 0.06f * (float)(i % 4);
                }
                glUniform1f(_cubeAlphaUniform, clampf_local(alpha, 0.10f, 1.0f));
            }

            glDrawElements(GL_TRIANGLES, 36, GL_UNSIGNED_SHORT, (const GLvoid *)0);
        }
    }

    glBindVertexArray(0);
    glUseProgram(0);
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
    float shadowBias = 0.0012f;
    float shadowPCFRadius = 2.0f;
    float bloomThresholdA = clampf_local(_userTopic9ThresholdA, 0.20f, 1.60f);
    float bloomThresholdB = clampf_local(_userTopic9ThresholdB, 0.30f, 2.20f);
    if (bloomThresholdB < bloomThresholdA + 0.05f)
    {
        bloomThresholdB = bloomThresholdA + 0.05f;
    }
    NSInteger bloomBlurPasses = _userTopic9BlurPassCount;
    if (bloomBlurPasses < 2)
    {
        bloomBlurPasses = 2;
    }
    if (bloomBlurPasses > 16)
    {
        bloomBlurPasses = 16;
    }
    float heatThreshold1 = 0.28f;
    float heatThreshold2 = 0.56f;
    float heatThreshold3 = 0.82f;

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

    if (_demoTopic == MetalDemoTopicShadowing)
    {
        shadowBias = _errorExampleEnabled ? 0.0020f : 0.0012f;
        shadowPCFRadius = _errorExampleEnabled ? 1.0f : 2.0f;
    }

    if (_demoTopic == MetalDemoTopicHDRBloomTAA)
    {
        // Metal topic 9 uses a high bright-pass threshold in HDR domain; OpenGL path maps it to LDR-like range.
        bloomThresholdA = clampf_local(bloomThresholdA, 0.35f, 1.40f);
        bloomThresholdB = clampf_local(bloomThresholdB, bloomThresholdA + 0.05f, 1.95f);
        if (_errorExampleEnabled)
        {
            bloomThresholdA *= 0.85f;
            bloomThresholdB *= 0.90f;
            bloomBlurPasses = (NSInteger)MIN((NSInteger)16, bloomBlurPasses + 2);
        }
    }

    if (_demoTopic == MetalDemoTopicProfiling)
    {
        heatThreshold1 = 0.24f;
        heatThreshold2 = 0.50f;
        heatThreshold3 = 0.78f;
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
    GLbitfield clearMask = GL_COLOR_BUFFER_BIT;
    if (_renderMode == OpenGLRenderModeCube)
    {
        clearMask |= GL_DEPTH_BUFFER_BIT;
    }
    glClear(clearMask);

    if (_renderMode == OpenGLRenderModeTriangle)
    {
        [self renderTriangleWithTime:t
                         topicConfig:cfg
                        edgeStrength:edgeStrength
                            exposure:exposure];
    }
    else
    {
        [self renderCubeWithTime:t
                     topicConfig:cfg
                    edgeStrength:edgeStrength
                        exposure:exposure
                         bloomStrength:bloomStrength
                     particleStrength:particleStrength
                         temporalBlend:temporalBlend
                                                 shadowBias:shadowBias
                                         shadowPCFRadius:shadowPCFRadius
                                         bloomThresholdA:bloomThresholdA
                                         bloomThresholdB:bloomThresholdB
                                             bloomBlurPasses:bloomBlurPasses
                                            heatThreshold1:heatThreshold1
                                            heatThreshold2:heatThreshold2
                                            heatThreshold3:heatThreshold3
                           width:width
                          height:height];
    }

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

    NSString *baseScenePath = [NSString stringWithUTF8String:cfg.scenePath ?: "OpenGL Scene"];
    NSString *geometryPath = (_renderMode == OpenGLRenderModeTriangle)
                           ? @"Triangle Geometry"
                           : @"Cube Geometry";
    _scenePathSummary = [NSString stringWithFormat:@"%@ + %@", baseScenePath, geometryPath];
    _postPathSummary = [NSString stringWithUTF8String:cfg.postPath ?: "Post"];
    _upscalePathSummary = [NSString stringWithUTF8String:cfg.upscalePath ?: "Off"];
    _runtimeFallbackSummary = [NSString stringWithUTF8String:cfg.fallback ?: "No"];

    _stats.timeScale = timeScale;
    _stats.edgeStrength = edgeStrength;
    _stats.exposure = exposure;
    _stats.bloomStrength = bloomStrength;
    _stats.particleStrength = particleStrength;
    _stats.temporalBlend = temporalBlend;
    _stats.shadowBias = shadowBias;
    _stats.shadowPCFRadius = shadowPCFRadius;
    _stats.topic9ThresholdA = bloomThresholdA;
    _stats.topic9ThresholdB = bloomThresholdB;
    _stats.topic9BlurPassCount = bloomBlurPasses;
    _stats.heatThreshold1 = heatThreshold1;
    _stats.heatThreshold2 = heatThreshold2;
    _stats.heatThreshold3 = heatThreshold3;
    _stats.errorExampleEnabled = _errorExampleEnabled;
    _stats.frameIndex += 1;
}

- (void)renderTriangleWithTime:(float)t
                    topicConfig:(OpenGLThemeConfig)cfg
                   edgeStrength:(float)edgeStrength
                       exposure:(float)exposure
{
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
    (void)cfg;
}

- (void)renderCubeWithTime:(float)t
                topicConfig:(OpenGLThemeConfig)cfg
               edgeStrength:(float)edgeStrength
                   exposure:(float)exposure
                  bloomStrength:(float)bloomStrength
              particleStrength:(float)particleStrength
                  temporalBlend:(float)temporalBlend
                shadowBias:(float)shadowBias
            shadowPCFRadius:(float)shadowPCFRadius
            bloomThresholdA:(float)bloomThresholdA
            bloomThresholdB:(float)bloomThresholdB
              bloomBlurPasses:(NSInteger)bloomBlurPasses
             heatThreshold1:(float)heatThreshold1
             heatThreshold2:(float)heatThreshold2
             heatThreshold3:(float)heatThreshold3
                      width:(GLsizei)width
                     height:(GLsizei)height
{
    NSUInteger instanceCount = 1;
    NSUInteger layerCount = 1;
    switch (_demoTopic)
    {
        case MetalDemoTopicIndirectCommandBuffer:
            instanceCount = 3;
            break;
        case MetalDemoTopicParallelEncoding:
            instanceCount = 6;
            layerCount = 2;
            break;
        case MetalDemoTopicComputeParticles:
            instanceCount = 10;
            break;
        case MetalDemoTopicMetalFXLike:
            layerCount = 2;
            break;
        case MetalDemoTopicProfiling:
            instanceCount = 4;
            layerCount = 2;
            break;
        default:
            break;
    }

    float aspect = (height > 0) ? ((float)width / (float)height) : 1.0f;
    const float kPi = 3.1415926535f;
    Mat4 projection = Mat4Perspective(60.0f * kPi / 180.0f, aspect, 0.1f, 80.0f);
    Mat4 view = Mat4Translation(0.0f, 0.0f, -4.8f);

    Mat4 lightView = Mat4LookAt(2.8f, 4.4f, 2.5f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f);
    Mat4 lightProj = Mat4Ortho(-5.0f, 5.0f, -5.0f, 5.0f, 0.1f, 14.0f);
    Mat4 lightVP = Mat4Multiply(lightProj, lightView);

    if (![self ensurePostProcessResourcesWithWidth:width height:height])
    {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, width, height);
        if (_demoTopic == MetalDemoTopicShadowing && [self ensureShadowResources])
        {
            [self renderCubeShadowPassWithLightVP:lightVP instanceCount:instanceCount layerCount:layerCount time:t];
        }
        [self renderCubeScenePassWithProjection:projection
                                          view:view
                                       lightVP:lightVP
                                instanceCount:instanceCount
                                   layerCount:layerCount
                                         time:t
                                 edgeStrength:edgeStrength
                                     exposure:exposure
                                bloomStrength:bloomStrength
                             particleStrength:particleStrength
                                          temporalBlend:temporalBlend
                                             shadowBias:shadowBias
                                        shadowPCFRadius:shadowPCFRadius
                                        heatThreshold1:heatThreshold1
                                        heatThreshold2:heatThreshold2
                                        heatThreshold3:heatThreshold3];
        if (_demoTopic == MetalDemoTopicProfiling)
        {
            glDisable(GL_DEPTH_TEST);
            glEnable(GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            glUseProgram(_legendProgram);
            if (_legendResolutionUniform >= 0)
            {
                glUniform2f(_legendResolutionUniform, (float)width, (float)height);
            }
            if (_legendTimeUniform >= 0)
            {
                glUniform1f(_legendTimeUniform, t);
            }
            [self drawFullscreenQuad];
        }
        (void)cfg;
        return;
    }

    if (_demoTopic == MetalDemoTopicShadowing && [self ensureShadowResources])
    {
        [self renderCubeShadowPassWithLightVP:lightVP instanceCount:instanceCount layerCount:layerCount time:t];
    }

    glBindFramebuffer(GL_FRAMEBUFFER, _sceneFBO);
    glViewport(0, 0, width, height);
    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    [self renderCubeScenePassWithProjection:projection
                                      view:view
                                   lightVP:lightVP
                            instanceCount:instanceCount
                               layerCount:layerCount
                                     time:t
                             edgeStrength:edgeStrength
                                 exposure:exposure
                            bloomStrength:bloomStrength
                         particleStrength:particleStrength
                                     temporalBlend:temporalBlend
                                        shadowBias:shadowBias
                                  shadowPCFRadius:shadowPCFRadius
                                  heatThreshold1:heatThreshold1
                                  heatThreshold2:heatThreshold2
                                  heatThreshold3:heatThreshold3];

    glDisable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);

    if (_demoTopic == MetalDemoTopicHDRBloomTAA)
    {
        glBindFramebuffer(GL_FRAMEBUFFER, _bloomFBO[0]);
        glViewport(0, 0, width, height);
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        glUseProgram(_postExtractProgram);
        if (_postExtractSceneUniform >= 0)
        {
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, _sceneColorTex);
            glUniform1i(_postExtractSceneUniform, 0);
        }
        if (_postExtractThresholdAUniform >= 0)
        {
            glUniform1f(_postExtractThresholdAUniform, bloomThresholdA);
        }
        if (_postExtractThresholdBUniform >= 0)
        {
            glUniform1f(_postExtractThresholdBUniform, bloomThresholdB);
        }
        [self drawFullscreenQuad];

        int src = 0;
        int dst = 1;
        int blurPasses = (int)bloomBlurPasses;
        if (blurPasses < 2)
        {
            blurPasses = 2;
        }
        if (blurPasses > 16)
        {
            blurPasses = 16;
        }
        for (int p = 0; p < blurPasses; ++p)
        {
            BOOL horizontal = ((p % 2) == 0);
            glBindFramebuffer(GL_FRAMEBUFFER, _bloomFBO[dst]);
            glViewport(0, 0, width, height);
            glUseProgram(_postBlurProgram);

            if (_postBlurSourceUniform >= 0)
            {
                glActiveTexture(GL_TEXTURE0);
                glBindTexture(GL_TEXTURE_2D, _bloomTex[src]);
                glUniform1i(_postBlurSourceUniform, 0);
            }
            if (_postBlurDirectionUniform >= 0)
            {
                glUniform2f(_postBlurDirectionUniform, horizontal ? 1.0f : 0.0f, horizontal ? 0.0f : 1.0f);
            }
            if (_postBlurTexelSizeUniform >= 0)
            {
                glUniform2f(_postBlurTexelSizeUniform, 1.0f / (float)width, 1.0f / (float)height);
            }
            [self drawFullscreenQuad];

            int tmp = src;
            src = dst;
            dst = tmp;
        }

        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, width, height);
        glUseProgram(_postCompositeProgram);

        if (_postCompositeSceneUniform >= 0)
        {
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, _sceneColorTex);
            glUniform1i(_postCompositeSceneUniform, 0);
        }
        if (_postCompositeBloomUniform >= 0)
        {
            glActiveTexture(GL_TEXTURE1);
            glBindTexture(GL_TEXTURE_2D, _bloomTex[src]);
            glUniform1i(_postCompositeBloomUniform, 1);
        }
        if (_postCompositeHistoryUniform >= 0)
        {
            glActiveTexture(GL_TEXTURE2);
            glBindTexture(GL_TEXTURE_2D, _historyTex);
            glUniform1i(_postCompositeHistoryUniform, 2);
        }
        if (_postCompositeBloomStrengthUniform >= 0)
        {
            glUniform1f(_postCompositeBloomStrengthUniform, bloomStrength * 1.25f);
        }
        if (_postCompositeTemporalUniform >= 0)
        {
            glUniform1f(_postCompositeTemporalUniform, temporalBlend);
        }
        if (_postCompositeUseTemporalUniform >= 0)
        {
            glUniform1i(_postCompositeUseTemporalUniform, 1);
        }
        [self drawFullscreenQuad];

        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, _historyTex);
        glCopyTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 0, 0, width, height);
    }
    else
    {
        glBindFramebuffer(GL_READ_FRAMEBUFFER, _sceneFBO);
        glBindFramebuffer(GL_DRAW_FRAMEBUFFER, 0);
        glBlitFramebuffer(0, 0, width, height, 0, 0, width, height, GL_COLOR_BUFFER_BIT, GL_LINEAR);
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
    }

    if (_demoTopic == MetalDemoTopicProfiling)
    {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, width, height);
        glDisable(GL_DEPTH_TEST);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glUseProgram(_legendProgram);
        if (_legendResolutionUniform >= 0)
        {
            glUniform2f(_legendResolutionUniform, (float)width, (float)height);
        }
        if (_legendTimeUniform >= 0)
        {
            glUniform1f(_legendTimeUniform, t);
        }
        [self drawFullscreenQuad];
    }

    glUseProgram(0);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, 0);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    (void)cfg;
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

- (void)setTopic9BloomThresholdA:(float)thresholdA thresholdB:(float)thresholdB blurPassCount:(NSInteger)blurPassCount
{
    _userTopic9ThresholdA = clampf_local(thresholdA, 0.20f, 1.60f);
    _userTopic9ThresholdB = clampf_local(thresholdB, 0.30f, 2.20f);
    if (_userTopic9ThresholdB < _userTopic9ThresholdA + 0.05f)
    {
        _userTopic9ThresholdB = _userTopic9ThresholdA + 0.05f;
    }

    if (blurPassCount < 2)
    {
        blurPassCount = 2;
    }
    if (blurPassCount > 16)
    {
        blurPassCount = 16;
    }
    _userTopic9BlurPassCount = blurPassCount;
}

- (void)setRenderMode:(OpenGLRenderMode)mode
{
    _renderMode = (mode == OpenGLRenderModeCube) ? OpenGLRenderModeCube : OpenGLRenderModeTriangle;
}

- (OpenGLRenderMode)renderMode
{
    return _renderMode;
}

- (NSString *)renderModeTitle
{
    return (_renderMode == OpenGLRenderModeCube) ? @"OpenGL Cube" : @"OpenGL Triangle";
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
