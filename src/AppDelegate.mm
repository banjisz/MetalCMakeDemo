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