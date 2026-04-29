#pragma once

#import <Cocoa/Cocoa.h>
#import "Renderer.h"

typedef struct
{
    double cpuFrameTimeMs;
    double fpsEstimate;
    NSUInteger frameIndex;
    float timeScale;
    float edgeStrength;
    float exposure;
    float bloomStrength;
    float particleStrength;
    float temporalBlend;
    float shadowBias;
    float shadowPCFRadius;
    float topic9ThresholdA;
    float topic9ThresholdB;
    NSInteger topic9BlurPassCount;
    float heatThreshold1;
    float heatThreshold2;
    float heatThreshold3;
    BOOL errorExampleEnabled;
} OpenGLRuntimeStats;

typedef NS_ENUM(NSInteger, OpenGLRenderMode)
{
    OpenGLRenderModeTriangle = 0,
    OpenGLRenderModeCube = 1
};

@interface OpenGLRenderer : NSObject

- (instancetype)initWithOpenGLView:(NSOpenGLView *)view;
- (BOOL)isReady;
- (void)render;

- (void)setDemoTopic:(MetalDemoTopic)topic;
- (MetalDemoTopic)demoTopic;
- (NSString *)demoTopicTitle;
- (void)setErrorExampleEnabled:(BOOL)enabled;
- (BOOL)errorExampleEnabled;
- (void)setUserParameterTimeScale:(float)timeScale edgeGain:(float)edgeGain exposureGain:(float)exposureGain;
- (void)setTopic9BloomThresholdA:(float)thresholdA thresholdB:(float)thresholdB blurPassCount:(NSInteger)blurPassCount;
- (void)setRenderMode:(OpenGLRenderMode)mode;
- (OpenGLRenderMode)renderMode;
- (NSString *)renderModeTitle;

- (OpenGLRuntimeStats)runtimeStats;
- (NSString *)scenePathSummary;
- (NSString *)postPathSummary;
- (NSString *)upscalePathSummary;
- (NSString *)runtimePathSummary;
- (NSString *)runtimeFallbackSummary;
- (NSString *)errorExampleSummary;

@end
