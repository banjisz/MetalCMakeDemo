#include <metal_stdlib>
using namespace metal;

constant bool kUsePBR [[function_constant(0)]];
constant bool kUseShadow [[function_constant(1)]];
constant bool kUseArgumentBuffer [[function_constant(2)]];

struct Vertex
{
    float3 position;
    float3 normal;
    float3 color;
    float2 uv;
};

struct Uniforms
{
    float4x4 viewProjectionMatrix;
    float4x4 modelViewProjectionMatrix;
    float4x4 modelMatrix;
    float3 lightDirection;
    float time;
    float exposure;
    float bloomStrength;
    uint demoTopic;
    uint featureFlags;
};

struct InstanceData
{
    float4x4 modelMatrix;
    float3 tint;
    float pad;
};

struct MaterialArguments
{
    texture2d<float> albedo [[id(0)]];
    texture2d<float> normal [[id(1)]];
};

struct SceneVertexOut
{
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float3 color;
    float2 uv;
};

struct PostProcessParams
{
    float edgeStrength;
    float sceneMix;
    float bloomStrength;
    float particleStrength;
    float temporalBlend;
    float exposure;
    float2 texelSize;
};

struct PostVertexOut
{
    float4 position [[position]];
    float2 uv;
};

static inline float3 fresnel_schlick(float cosTheta, float3 F0);
static inline float3 fresnel_schlick_roughness(float cosTheta, float3 F0, float roughness);

vertex SceneVertexOut scene_vertex(const device Vertex *vertices [[buffer(0)]],
                                   constant Uniforms &uniforms [[buffer(1)]],
                                   const device InstanceData *instances [[buffer(2)]],
                                   uint vertexID [[vertex_id]],
                                   uint instanceID [[instance_id]])
{
    Vertex v = vertices[vertexID];
    float4 modelPos = float4(v.position, 1.0);

    SceneVertexOut out;
    if (uniforms.demoTopic == 4u)
    {
        InstanceData instance = instances[instanceID];
        float4 worldPos = instance.modelMatrix * modelPos;
        out.position = uniforms.viewProjectionMatrix * worldPos;
        out.worldPosition = worldPos.xyz;
        out.worldNormal = normalize((instance.modelMatrix * float4(v.normal, 0.0)).xyz);
        out.color = v.color * instance.tint;
    }
    else
    {
        out.position = uniforms.modelViewProjectionMatrix * modelPos;
        out.worldPosition = (uniforms.modelMatrix * modelPos).xyz;
        out.worldNormal = normalize((uniforms.modelMatrix * float4(v.normal, 0.0)).xyz);
        out.color = v.color;
    }
    out.uv = v.uv;
    return out;
}

fragment float4 scene_fragment(SceneVertexOut in [[stage_in]],
                               constant Uniforms &uniforms [[buffer(1)]],
                               constant MaterialArguments &materialArgs [[buffer(2)]],
                               texture2d<float> albedoTexture [[texture(0)]],
                               texture2d<float> normalTexture [[texture(1)]],
                               sampler materialSampler [[sampler(0)]])
{
    float3 L = normalize(-uniforms.lightDirection);

    float3 albedoSample;
    float3 normalSample;
    if (kUseArgumentBuffer)
    {
        albedoSample = materialArgs.albedo.sample(materialSampler, in.uv).rgb;
        normalSample = materialArgs.normal.sample(materialSampler, in.uv).xyz * 2.0 - 1.0;
    }
    else
    {
        albedoSample = albedoTexture.sample(materialSampler, in.uv).rgb;
        normalSample = normalTexture.sample(materialSampler, in.uv).xyz * 2.0 - 1.0;
    }

    float3 baseColor = albedoSample * in.color;

    // Axis-aligned cube faces: build a tangent basis from geometric normal.
    float3 Ngeo = normalize(in.worldNormal);
    float3 upRef = abs(Ngeo.y) < 0.99 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
    float3 T = normalize(cross(upRef, Ngeo));
    float3 B = normalize(cross(Ngeo, T));
    float3 Nmap = normalize(T * normalSample.x + B * normalSample.y + Ngeo * normalSample.z);

    float NdotL = saturate(dot(Nmap, L));
    float3 V = normalize(float3(0.0, 0.0, 5.0) - in.worldPosition);
    float3 H = normalize(L + V);
    float specular = pow(saturate(dot(Nmap, H)), 64.0);

    if (kUsePBR)
    {
        float roughness = clamp(0.35, 0.045, 1.0);
        float metallic  = clamp(0.20, 0.0,   1.0);
        float ao        = 1.0;
        float3 F0 = mix(float3(0.04), baseColor, metallic);

        float NdotV = max(dot(Nmap, V), 0.0);
        float NdotL = max(dot(Nmap, L), 0.0);
        float NdotH = max(dot(Nmap, H), 0.0);
        float VdotH = max(dot(V, H), 0.0);

        float a  = roughness * roughness;
        float a2 = a * a;
        float dDenom = (NdotH * NdotH) * (a2 - 1.0) + 1.0;
        float D = a2 / max(M_PI_F * dDenom * dDenom, 1e-5);

        float k = ((roughness + 1.0) * (roughness + 1.0)) * 0.125;
        float Gv = NdotV / max(NdotV * (1.0 - k) + k, 1e-5);
        float Gl = NdotL / max(NdotL * (1.0 - k) + k, 1e-5);
        float G = Gv * Gl;

        float3 F = fresnel_schlick(VdotH, F0);
        float3 specBRDF = (D * G * F) / max(4.0 * NdotV * NdotL, 1e-5);
        float3 kS = F;
        float3 kD = (1.0 - kS) * (1.0 - metallic);
        float3 diffuse = kD * baseColor / M_PI_F;

        float3 radiance = float3(1.0);
        float3 lit = (diffuse + specBRDF) * radiance * NdotL;

        float3 F_amb = fresnel_schlick_roughness(NdotV, F0, roughness);
        float3 kS_amb = F_amb;
        float3 kD_amb = (1.0 - kS_amb) * (1.0 - metallic);
        float3 ambient = (kD_amb * baseColor * 0.12) * ao;

        float shadow = 1.0;
        if (kUseShadow)
        {
            float fakeShadow = smoothstep(0.0, 1.0, in.worldPosition.y * 0.5 + 0.5);
            shadow = mix(0.35, 1.0, fakeShadow);
        }
        return float4((ambient + lit) * shadow, 1.0);
    }

    float pulse = 0.08 * sin(uniforms.time * 2.1);
    float3 ambient = baseColor * (0.18 + pulse);
    float3 diffuse = baseColor * (0.20 + 0.80 * NdotL);
    float3 spec = float3(0.45) * specular;

    float shadow = 1.0;
    if (kUseShadow)
    {
        float fakeShadow = smoothstep(0.0, 1.0, in.worldPosition.y * 0.5 + 0.5);
        shadow = mix(0.4, 1.0, fakeShadow);
    }

    return float4((ambient + diffuse + spec) * shadow, 1.0);
}

// ICB-compatible variant: no fragment buffers/textures/samplers.
// This is deliberately conservative because many devices/drivers reject
// more complex fragment signatures on ICB-enabled render pipelines.
fragment float4 scene_fragment_icb(SceneVertexOut in [[stage_in]])
{
    float3 lightDir = normalize(float3(0.5, 0.8, 0.4));
    float3 baseColor = in.color;
    float3 Ngeo = normalize(in.worldNormal);
    float NdotL = saturate(dot(Ngeo, lightDir));
    float3 V = normalize(float3(0.0, 0.0, 5.0) - in.worldPosition);
    float3 H = normalize(lightDir + V);
    float specular = pow(saturate(dot(Ngeo, H)), 48.0);

    float3 ambient = baseColor * 0.20;
    float3 diffuse = baseColor * (0.20 + 0.80 * NdotL);
    float3 spec = float3(0.45) * specular;
    return float4(ambient + diffuse + spec, 1.0);
}

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

fragment float4 post_fragment(PostVertexOut in [[stage_in]],
                              texture2d<float> sceneTexture [[texture(0)]],
                              texture2d<float> edgeTexture [[texture(1)]],
                              texture2d<float> bloomTexture [[texture(2)]],
                              texture2d<float> particleTexture [[texture(3)]],
                              texture2d<float> historyTexture [[texture(4)]],
                              sampler postSampler [[sampler(0)]],
                              constant PostProcessParams &params [[buffer(0)]])
{
    float3 sceneColor = sceneTexture.sample(postSampler, in.uv).rgb;
    float edge = params.edgeStrength > 0.0001 ? edgeTexture.sample(postSampler, in.uv).r * params.edgeStrength
                                               : 0.0;
    float3 bloom = params.bloomStrength > 0.0001 ? bloomTexture.sample(postSampler, in.uv).rgb * params.bloomStrength
                                                  : float3(0.0);
    float3 particles = params.particleStrength > 0.0001 ? particleTexture.sample(postSampler, in.uv).rgb * params.particleStrength
                                                         : float3(0.0);
    float3 history = params.temporalBlend > 0.0001 ? historyTexture.sample(postSampler, in.uv).rgb
                                                    : sceneColor;

    float2 centered = in.uv * 2.0 - 1.0;
    float vignette = 1.0 - smoothstep(0.35, 1.2, dot(centered, centered));

    float3 edgeTint = float3(0.25, 0.55, 0.95) * edge;
    float3 hdr = sceneColor * (0.85 + 0.15 * vignette) * params.sceneMix + edgeTint + bloom + particles;
    float3 tonemapped = 1.0 - exp(-hdr * params.exposure);
    float3 temporal = mix(tonemapped, history, params.temporalBlend);
    temporal = min(temporal, float3(1.0));
    return float4(temporal, 1.0);
}

static inline float luma(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

static inline float3 fresnel_schlick(float cosTheta, float3 F0)
{
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

static inline float3 fresnel_schlick_roughness(float cosTheta, float3 F0, float roughness)
{
    return F0 + (max(float3(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

kernel void edge_detect_kernel(texture2d<float, access::read> sourceTexture [[texture(0)]],
                               texture2d<float, access::write> edgeTexture [[texture(1)]],
                               uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= sourceTexture.get_width() || gid.y >= sourceTexture.get_height())
    {
        return;
    }

    int2 p = int2(gid);
    int w = (int)sourceTexture.get_width();
    int h = (int)sourceTexture.get_height();

    int2 offsets[9] = {
        int2(-1, -1), int2(0, -1), int2(1, -1),
        int2(-1, 0), int2(0, 0), int2(1, 0),
        int2(-1, 1), int2(0, 1), int2(1, 1)
    };

    float samples[9];
    for (uint i = 0; i < 9; ++i)
    {
        int2 q = p + offsets[i];
        q.x = clamp(q.x, 0, w - 1);
        q.y = clamp(q.y, 0, h - 1);
        samples[i] = luma(sourceTexture.read(uint2(q)).rgb);
    }

    float gx = -samples[0] + samples[2]
             - 2.0 * samples[3] + 2.0 * samples[5]
             - samples[6] + samples[8];
    float gy = -samples[0] - 2.0 * samples[1] - samples[2]
             + samples[6] + 2.0 * samples[7] + samples[8];

    float edge = saturate(length(float2(gx, gy)) * 1.2);
    edgeTexture.write(float4(edge, edge, edge, 1.0), gid);
}

// bright_extract_kernel writes to a HALF-resolution bloom texture.
// A 2x2 box sample from the full-res source gives a free downsample step,
// matching the allocation in ensureRenderTargetsForDrawable.
kernel void bright_extract_kernel(texture2d<float, access::read> sourceTexture [[texture(0)]],
                                  texture2d<float, access::write> brightTexture [[texture(1)]],
                                  constant float &threshold [[buffer(0)]],
                                  uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= brightTexture.get_width() || gid.y >= brightTexture.get_height())
    {
        return;
    }

    // Map half-res gid -> full-res 2x2 block for box-filter downsample.
    uint2 base = gid * 2;
    uint2 maxC = uint2(sourceTexture.get_width() - 1, sourceTexture.get_height() - 1);
    float3 c = (sourceTexture.read(min(base,                   maxC)).rgb +
                sourceTexture.read(min(base + uint2(1, 0),     maxC)).rgb +
                sourceTexture.read(min(base + uint2(0, 1),     maxC)).rgb +
                sourceTexture.read(min(base + uint2(1, 1),     maxC)).rgb) * 0.25;
    float l = luma(c);
    brightTexture.write(float4(l > threshold ? c : float3(0.0), 1.0), gid);
}

kernel void blur_kernel(texture2d<float, access::read> sourceTexture [[texture(0)]],
                        texture2d<float, access::write> outTexture [[texture(1)]],
                        constant uint &horizontal [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height())
    {
        return;
    }

    float weights[5] = {0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216};
    float3 sum = sourceTexture.read(gid).rgb * weights[0];

    int2 axis = horizontal != 0 ? int2(1, 0) : int2(0, 1);
    int w = (int)sourceTexture.get_width();
    int h = (int)sourceTexture.get_height();
    int2 p = int2(gid);

    for (int i = 1; i < 5; ++i)
    {
        int2 p1 = p + axis * i;
        int2 p2 = p - axis * i;
        p1.x = clamp(p1.x, 0, w - 1);
        p1.y = clamp(p1.y, 0, h - 1);
        p2.x = clamp(p2.x, 0, w - 1);
        p2.y = clamp(p2.y, 0, h - 1);
        sum += sourceTexture.read(uint2(p1)).rgb * weights[i];
        sum += sourceTexture.read(uint2(p2)).rgb * weights[i];
    }

    outTexture.write(float4(sum, 1.0), gid);
}

kernel void particle_overlay_kernel(texture2d<float, access::write> particleTexture [[texture(0)]],
                                    constant float &time [[buffer(0)]],
                                    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= particleTexture.get_width() || gid.y >= particleTexture.get_height())
    {
        return;
    }

    float2 uv = (float2(gid) + 0.5) / float2(particleTexture.get_width(), particleTexture.get_height());
    float3 c = float3(0.0);

    for (uint i = 0; i < 48; ++i)
    {
        float fi = (float)i;
        float2 center = float2(fract(fi * 0.618 + time * 0.07), fract(fi * 0.367 + time * 0.09));
        float2 d = uv - center;
        float dist = length(d);
        float radius = 0.006 + 0.010 * fract(fi * 0.131);
        float alpha = smoothstep(radius, radius * 0.35, dist);
        float3 tint = float3(0.3 + 0.7 * fract(fi * 0.11), 0.4 + 0.5 * fract(fi * 0.17), 1.0);
        c += tint * alpha * 0.025;
    }

    particleTexture.write(float4(c, 1.0), gid);
}

kernel void downsample_half_kernel(texture2d<float, access::read> sourceTexture [[texture(0)]],
                                   texture2d<float, access::write> halfTexture [[texture(1)]],
                                   uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= halfTexture.get_width() || gid.y >= halfTexture.get_height())
    {
        return;
    }

    uint2 base = gid * 2;
    uint2 maxCoord = uint2(sourceTexture.get_width() - 1, sourceTexture.get_height() - 1);
    uint2 c0 = min(base, maxCoord);
    uint2 c1 = min(base + uint2(1, 0), maxCoord);
    uint2 c2 = min(base + uint2(0, 1), maxCoord);
    uint2 c3 = min(base + uint2(1, 1), maxCoord);

    float3 out = (sourceTexture.read(c0).rgb + sourceTexture.read(c1).rgb +
                  sourceTexture.read(c2).rgb + sourceTexture.read(c3).rgb) * 0.25;
    halfTexture.write(float4(out, 1.0), gid);
}

kernel void upscale_linear_kernel(texture2d<float, access::read> sourceTexture [[texture(0)]],
                                  texture2d<float, access::write> outTexture [[texture(1)]],
                                  uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height())
    {
        return;
    }

    float2 uv = (float2(gid) + 0.5) / float2(outTexture.get_width(), outTexture.get_height());
    float2 srcPos = uv * float2(sourceTexture.get_width(), sourceTexture.get_height()) - 0.5;

    int2 p0 = int2(floor(srcPos));
    float2 f = fract(srcPos);
    int w = (int)sourceTexture.get_width();
    int h = (int)sourceTexture.get_height();

    int2 p1 = p0 + int2(1, 0);
    int2 p2 = p0 + int2(0, 1);
    int2 p3 = p0 + int2(1, 1);

    p0.x = clamp(p0.x, 0, w - 1); p0.y = clamp(p0.y, 0, h - 1);
    p1.x = clamp(p1.x, 0, w - 1); p1.y = clamp(p1.y, 0, h - 1);
    p2.x = clamp(p2.x, 0, w - 1); p2.y = clamp(p2.y, 0, h - 1);
    p3.x = clamp(p3.x, 0, w - 1); p3.y = clamp(p3.y, 0, h - 1);

    float3 c00 = sourceTexture.read(uint2(p0)).rgb;
    float3 c10 = sourceTexture.read(uint2(p1)).rgb;
    float3 c01 = sourceTexture.read(uint2(p2)).rgb;
    float3 c11 = sourceTexture.read(uint2(p3)).rgb;

    float3 c0 = mix(c00, c10, f.x);
    float3 c1 = mix(c01, c11, f.x);
    float3 out = mix(c0, c1, f.y);
    outTexture.write(float4(out, 1.0), gid);
}
