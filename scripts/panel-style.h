#import <AppKit/AppKit.h>

// Shared interaction treatment; anchored windows never slide during a refresh.
void DFPanelPresent(NSWindow *window);
void DFPanelPrepare(NSPanel *panel);

@interface DFPanelButton : NSButton
@property(nonatomic) BOOL hovered;
@property BOOL showsHover;
@end
