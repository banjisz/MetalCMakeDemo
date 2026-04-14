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

@interface Renderer : NSObject

- (instancetype)initWithLayer:(CAMetalLayer *)layer;
- (void)render;

- (void)setDemoTopic:(MetalDemoTopic)topic;
- (MetalDemoTopic)demoTopic;
- (NSString *)demoTopicTitle;

+ (NSArray<NSString *> *)allDemoTopicTitles;

@end