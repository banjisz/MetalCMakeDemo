#pragma once

#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

typedef NS_ENUM(NSInteger, MetalDemoTopic)
{
	MetalDemoTopicResourceMemory = 1,
	MetalDemoTopicArgumentBuffer = 2,
	MetalDemoTopicFunctionConstants = 3,
	MetalDemoTopicIndirectCommandBuffer = 4,
	MetalDemoTopicParallelEncoding = 5,
	MetalDemoTopicDeferredLike = 6,
	MetalDemoTopicShadowing = 7,
	MetalDemoTopicPBR = 8,
	MetalDemoTopicHDRBloomTAA = 9,
	MetalDemoTopicComputeParticles = 10,
	MetalDemoTopicTextureAdvanced = 11,
	MetalDemoTopicSyncAndScheduling = 12,
	MetalDemoTopicRayTracing = 13,
	MetalDemoTopicMetalFXLike = 14,
	MetalDemoTopicProfiling = 15
};

typedef struct
{
	double cpuFrameTimeMs;
	double gpuFrameTimeMs;
	double estimatedMemoryMB;
	float timeScale;
	float edgeStrength;
	float exposure;
	float bloomStrength;
	float particleStrength;
	float temporalBlend;
	BOOL errorExampleEnabled;
} MetalDemoRuntimeStats;

@interface Renderer : NSObject

- (instancetype)initWithLayer:(CAMetalLayer *)layer;
- (void)render;

- (void)setDemoTopic:(MetalDemoTopic)topic;
- (MetalDemoTopic)demoTopic;
- (NSString *)demoTopicTitle;
- (void)setErrorExampleEnabled:(BOOL)enabled;
- (BOOL)errorExampleEnabled;
- (void)setUserParameterTimeScale:(float)timeScale edgeGain:(float)edgeGain exposureGain:(float)exposureGain;
- (MetalDemoRuntimeStats)runtimeStats;
- (NSString *)errorExampleSummary;

+ (NSArray<NSString *> *)allDemoTopicTitles;

@end