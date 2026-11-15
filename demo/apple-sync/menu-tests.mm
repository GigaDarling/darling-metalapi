// SPDX-License-Identifier: GPL-3.0-or-later
// Public NSMenu/NSApplication input contract, independent of the Metal renderer.
#import <AppKit/AppKit.h>
#include <cstdio>
#include <cstdlib>

static void requireMenu(bool value,const char* message) {
    if (!value) { std::fprintf(stderr,"FAIL AppKit menu: %s\n",message);std::exit(1); }
}
static NSEvent* menuEvent(NSEventType type,NSWindow* window,NSPoint point) {
    return [NSEvent mouseEventWithType:type location:point modifierFlags:0
        timestamp:[NSDate timeIntervalSinceReferenceDate] windowNumber:window.windowNumber
        context:nil eventNumber:1 clickCount:1 pressure:0];
}
static NSView* findMenuView(NSView* view,NSMenu* menu) {
    if (view.menu==menu) return view;
    for (NSView* child in view.subviews) { NSView* found=findMenuView(child,menu);if(found)return found; }
    return nil;
}
static bool externalMode=false;
static bool alertMode=false;
@interface MenuContractTest : NSObject<NSApplicationDelegate> {
    NSWindow* _window;
    NSMenu* _bar;
    NSMenu* _submenu;
    NSView* _menuView;
    NSTimer* _input;
    NSUInteger _stage,_actions,_case;
}
@end
@implementation MenuContractTest
- (void)closeAlert:(NSTimer*)timer {
    NSAlert* alert=timer.userInfo;
    requireMenu([NSApp modalWindow]==alert.window && [alert.window isVisible],"NSAlert is visible and owns the modal session");
    [[alert.buttons objectAtIndex:0] performClick:nil];
}
- (void)chosen:(id)sender {
    ++_actions;
    if (externalMode) {
        if (alertMode) {
            NSAlert* alert=[NSAlert new];alert.messageText=@"AppKit menu action";
            alert.informativeText=@"Native NSAlert opened from an NSMenu target/action.";
            [alert addButtonWithTitle:@"OK"];
            NSTimer* close=[NSTimer timerWithTimeInterval:.3 target:self selector:@selector(closeAlert:) userInfo:alert repeats:NO];
            [[NSRunLoop mainRunLoop] addTimer:close forMode:NSModalPanelRunLoopMode];
            requireMenu([alert runModal]==NSAlertFirstButtonReturn,"NSAlert OK button ends modal loop");
            std::printf("PASS menu action opens NSAlert and OK closes it\n");
        }
        _window.title=@"AppKit raw menu test - PASS";
        [NSTimer scheduledTimerWithTimeInterval:1 target:NSApp selector:@selector(terminate:) userInfo:nil repeats:NO];
    }
}
- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    _bar=[[NSMenu alloc] initWithTitle:@"Test bar"];
    NSMenuItem* top=[[NSMenuItem alloc] initWithTitle:@"Test" action:NULL keyEquivalent:@""];
    _submenu=[[NSMenu alloc] initWithTitle:@"Test"];
    NSMenuItem* leaf=[_submenu addItemWithTitle:@"Choose" action:@selector(chosen:) keyEquivalent:@"t"];leaf.target=self;
    if (externalMode) { top.title=@"Menu Contract";[_submenu addItem:[NSMenuItem separatorItem]];
        [_submenu addItemWithTitle:@"Inactive" action:NULL keyEquivalent:@""]; }
    top.submenu=_submenu;[_bar addItem:top];[NSApp setMainMenu:_bar];
    _window=[[NSWindow alloc] initWithContentRect:NSMakeRect(50,50,360,200)
        styleMask:NSTitledWindowMask backing:NSBackingStoreBuffered defer:NO];
    _window.title=@"AppKit menu contract test";[_window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    _menuView=findMenuView(_window.contentView.superview,_bar);requireMenu(_menuView!=nil,"native menu view exists");
    if (externalMode) { _window.title=@"AppKit raw menu test - READY";
        NSTimer* timeout=[NSTimer timerWithTimeInterval:15 target:self selector:@selector(timeout:) userInfo:nil repeats:NO];
        [[NSRunLoop mainRunLoop] addTimer:timeout forMode:NSDefaultRunLoopMode];
        [[NSRunLoop mainRunLoop] addTimer:timeout forMode:NSEventTrackingRunLoopMode];
    } else [self prepareCase];
}
- (void)prepareCase {
    _stage=0;
    _input=[NSTimer timerWithTimeInterval:.15 target:self selector:@selector(input:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_input forMode:NSEventTrackingRunLoopMode];
    NSTimer* timeout=[NSTimer timerWithTimeInterval:8 target:self selector:@selector(timeout:) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:timeout forMode:NSDefaultRunLoopMode];
    [[NSRunLoop mainRunLoop] addTimer:timeout forMode:NSEventTrackingRunLoopMode];
    [NSTimer scheduledTimerWithTimeInterval:.1 target:self selector:@selector(open:) userInfo:nil repeats:NO];
}
- (NSPoint)barPoint { return [_menuView convertPoint:NSMakePoint(15,NSMidY(_menuView.bounds)) toView:nil]; }
- (void)open:(NSTimer*)timer {
    [NSApp sendEvent:menuEvent(NSLeftMouseDown,_window,[self barPoint])];
    [_input invalidate];requireMenu(_stage==(_case?6:5) && _actions==_case+1,"sticky menu click invokes target action once");
    std::printf("PASS native menu selection case=%lu: target/action delivered once\n",(unsigned long)_case);
    if (_case==0) { ++_case;[self prepareCase]; } else [NSApp terminate:nil];
}
- (void)input:(NSTimer*)timer {
    if (_stage==0) { [NSApp postEvent:menuEvent(NSLeftMouseUp,_window,[self barPoint]) atStart:NO];++_stage;return; }
    NSWindow* popup=nil;
    for (NSWindow* candidate in NSApp.windows) if (candidate!=_window && [candidate isVisible] && candidate.level==NSSubmenuWindowLevel) {popup=candidate;break;}
    requireMenu(popup!=nil,"submenu window opened");
    // Enter through the top border (no item), then move within the first
    // bar item's old rectangle to the first submenu row: stale-cache regression.
    NSRect bounds=popup.contentView.bounds;
    NSPoint point=[popup.contentView convertPoint:_case?NSMakePoint(10,NSHeight(bounds)-(_stage==1?1:10)):
        NSMakePoint(NSMidX(bounds),NSMidY(bounds)) toView:nil];
    const NSUInteger downStage=_case?3:2;
    NSEventType type=_stage<downStage?NSMouseMoved:_stage==downStage?NSLeftMouseDown:NSLeftMouseUp;
    [NSApp postEvent:menuEvent(type,popup,point) atStart:NO];
    ++_stage;
    if (_stage==downStage+2) { _stage=_case?6:5;[_input invalidate]; }
}
- (void)timeout:(NSTimer*)timer { requireMenu(false,"menu tracking timed out"); }
@end
void runMenuContractTest(bool raw,bool alert) {
    externalMode=raw;alertMode=alert;
    [NSApplication sharedApplication];MenuContractTest* test=[MenuContractTest new];[NSApp setDelegate:test];[NSApp run];
}
