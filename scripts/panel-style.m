#import "panel-style.h"
#import "control-panel.h"
#import <QuartzCore/QuartzCore.h>

void DFPanelPrepare(NSPanel *panel) {
    panel.animationBehavior=NSWindowAnimationBehaviorNone;
    panel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces
        |NSWindowCollectionBehaviorFullScreenAuxiliary|NSWindowCollectionBehaviorStationary;
    panel.hidesOnDeactivate=NO;
}
void DFPanelPresent(NSWindow *window) {
    BOOL fresh=!window.visible;
    if (fresh) window.alphaValue=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 1 : 0;
    [window orderFrontRegardless];
    if (!fresh) return;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration=NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion ? 0 : .12;
        context.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        window.animator.alphaValue=1;
    } completionHandler:nil];
}
@implementation DFPanelButton
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.showsHover=YES;self.bordered=NO;self.wantsLayer=YES;
        self.layer.cornerRadius=7;self.layer.masksToBounds=YES;
        self.focusRingType=NSFocusRingTypeNone;
    }
    return self;
}
- (void)setHovered:(BOOL)hovered {
    if (_hovered==hovered) return;
    _hovered=hovered;
    CGColorRef previous=((CALayer *)self.layer.presentationLayer ?: self.layer).backgroundColor;
    NSColor *color=hovered && self.enabled && self.showsHover ? DFPanelColor(0x202735) : NSColor.clearColor;
    if (!NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion && previous) {
        CABasicAnimation *animation=[CABasicAnimation animationWithKeyPath:@"backgroundColor"];
        animation.fromValue=(__bridge id)previous;animation.toValue=(__bridge id)color.CGColor;animation.duration=.09;
        [self.layer addAnimation:animation forKey:@"hover"];
    }
    self.layer.backgroundColor=color.CGColor;self.needsDisplay=YES;
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    for (NSTrackingArea *area in self.trackingAreas.copy) [self removeTrackingArea:area];
    [self addTrackingArea:[[NSTrackingArea alloc] initWithRect:self.bounds
        options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect owner:self userInfo:nil]];
    if (self.window) self.hovered=NSPointInRect([self convertPoint:[self.window convertPointFromScreen:NSEvent.mouseLocation] fromView:nil],self.bounds);
}
- (void)mouseEntered:(__unused NSEvent *)event {self.hovered=YES;}
- (void)mouseExited:(__unused NSEvent *)event {self.hovered=NO;}
@end
