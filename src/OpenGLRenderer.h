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
    BOOL errorExampleEnabled;
} OpenGLRuntimeStats;

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

- (OpenGLRuntimeStats)runtimeStats;
- (NSString *)scenePathSummary;
- (NSString *)postPathSummary;
- (NSString *)upscalePathSummary;
- (NSString *)runtimePathSummary;
- (NSString *)runtimeFallbackSummary;
- (NSString *)errorExampleSummary;

@end
