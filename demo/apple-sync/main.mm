// SPDX-License-Identifier: GPL-3.0-or-later
// Application bootstrap for the MIT Apple sample; the renderer is unchanged.
#import <AppKit/AppKit.h>
#import <MetalKit/MetalKit.h>
#import "AAPLRenderer.h"
#import <objc/runtime.h>
#include "validation.hpp"
#include <cstdio>
#include <cstring>
#include <cstdlib>

static void requireSample(bool value,const char* text) {
    if (!value) { std::fprintf(stderr,"FAIL Apple sample: %s\n",text);std::exit(1); }
}
static bool testMode=false;
static const CGFloat controlHeight=84;
void verifyPortableLibraries();
void runMenuContractTest(bool raw,bool alert);

@protocol SampleInput <NSObject>
- (void)pointerEvent:(NSEvent*)event inView:(NSView*)view;
- (void)toggleAnimation:(id)sender;
- (void)contextMenu:(NSEvent*)event inView:(NSView*)view;
@end
@interface SampleView : MTKView
@property(nonatomic,strong) id<MTLTexture> observedTexture;
@property(nonatomic,weak) id<SampleInput> inputDelegate;
@end
@implementation SampleView
- (id<CAMetalDrawable>)currentDrawable {
    id<CAMetalDrawable> drawable=[super currentDrawable];
    if (testMode) self.observedTexture=drawable.texture;
    return drawable;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent*)event { return YES; }
- (void)mouseDown:(NSEvent*)event {
    [self.window makeFirstResponder:self];
    [self.inputDelegate pointerEvent:event inView:self];[self.inputDelegate toggleAnimation:self];
}
- (void)mouseMoved:(NSEvent*)event { [self.inputDelegate pointerEvent:event inView:self]; }
- (void)mouseDragged:(NSEvent*)event { [self.inputDelegate pointerEvent:event inView:self]; }
- (void)rightMouseDown:(NSEvent*)event { [self.inputDelegate contextMenu:event inView:self]; }
- (void)keyDown:(NSEvent*)event {
    if ([event.charactersIgnoringModifiers isEqualToString:@" "]) [self.inputDelegate toggleAnimation:self];
    else [super keyDown:event];
}
@end

@interface SampleApplication : NSObject<NSApplicationDelegate,NSWindowDelegate,SampleInput> {
    NSWindow* _window;
    SampleView* _view;
    AAPLRenderer* _renderer;
    NSTimer* _timer;
    unsigned _frames;
    float _phase;
    BOOL _animationPaused;
    NSUInteger _clicks;
    NSButton* _clickButton;
    NSButton* _pauseButton;
    NSTextField* _summary;
    NSTextField* _pointerLabel;
    NSTextField* _editField;
    NSMenuItem* _pauseItem;
}
@end

@implementation SampleApplication
- (NSMenu*)addMenu:(NSString*)title to:(NSMenu*)bar {
    NSMenuItem* item=[[NSMenuItem alloc] initWithTitle:title action:NULL keyEquivalent:@""];
    NSMenu* menu=[[NSMenu alloc] initWithTitle:title];[item setSubmenu:menu];[bar addItem:item];return menu;
}
- (NSMenuItem*)item:(NSString*)title action:(SEL)action key:(NSString*)key menu:(NSMenu*)menu target:(id)target {
    NSMenuItem* item=[menu addItemWithTitle:title action:action keyEquivalent:key];item.target=target;return item;
}
- (void)buildMenus {
    NSMenu* bar=[[NSMenu alloc] initWithTitle:@"Main Menu"];
    NSMenu* app=[self addMenu:@"Metal Sample" to:bar];
    [self item:@"Об этом примере" action:@selector(showAbout:) key:@"" menu:app target:self];
    [app addItem:[NSMenuItem separatorItem]];
    [self item:@"Завершить" action:@selector(closeWindow:) key:@"q" menu:app target:self];
    NSMenu* file=[self addMenu:@"Файл" to:bar];
    [self item:@"Закрыть окно" action:@selector(closeWindow:) key:@"w" menu:file target:self];
    NSMenu* edit=[self addMenu:@"Правка" to:bar];
    [self item:@"Вырезать" action:@selector(cut:) key:@"x" menu:edit target:nil];
    [self item:@"Копировать" action:@selector(copy:) key:@"c" menu:edit target:nil];
    [self item:@"Вставить" action:@selector(paste:) key:@"v" menu:edit target:nil];
    [edit addItem:[NSMenuItem separatorItem]];
    [self item:@"Выделить всё" action:@selector(selectAll:) key:@"a" menu:edit target:nil];
    NSMenu* view=[self addMenu:@"Вид" to:bar];
    _pauseItem=[self item:@"Приостановить анимацию" action:@selector(toggleAnimation:) key:@"p" menu:view target:self];
    [self item:@"Один кадр" action:@selector(singleFrame:) key:@"n" menu:view target:self];
    NSMenu* window=[self addMenu:@"Окно" to:bar];
    [self item:@"Свернуть" action:@selector(minimize:) key:@"m" menu:window target:self];
    [self item:@"Масштаб" action:@selector(zoomWindow:) key:@"" menu:window target:self];
    NSMenu* help=[self addMenu:@"Справка" to:bar];
    [self item:@"Управление" action:@selector(showHelp:) key:@"" menu:help target:self];
    [NSApp setMainMenu:bar];[NSApp setWindowsMenu:window];[NSApp setHelpMenu:help];
}
- (NSTextField*)labelIn:(NSView*)content frame:(NSRect)frame {
    NSTextField* label=[[NSTextField alloc] initWithFrame:frame];
    label.editable=NO;label.selectable=NO;label.bezeled=NO;label.drawsBackground=NO;[content addSubview:label];return label;
}
- (void)buildControls:(NSView*)content {
    CGFloat top=content.bounds.size.height;
    _clickButton=[[NSButton alloc] initWithFrame:NSMakeRect(16,top-46,150,30)];
    _clickButton.title=@"Нажми меня";_clickButton.target=self;_clickButton.action=@selector(countClick:);
    _clickButton.autoresizingMask=NSViewMinYMargin;[content addSubview:_clickButton];
    _pauseButton=[[NSButton alloc] initWithFrame:NSMakeRect(178,top-46,140,30)];
    _pauseButton.target=self;_pauseButton.action=@selector(toggleAnimation:);
    _pauseButton.autoresizingMask=NSViewMinYMargin;[content addSubview:_pauseButton];
    _editField=[[NSTextField alloc] initWithFrame:NSMakeRect(334,top-44,230,26)];
    _editField.stringValue=@"Текст для меню «Правка»";_editField.autoresizingMask=NSViewMinYMargin;[content addSubview:_editField];
    _summary=[self labelIn:content frame:NSMakeRect(580,top-43,400,24)];
    _summary.autoresizingMask=NSViewWidthSizable|NSViewMinYMargin;
    _pointerLabel=[self labelIn:content frame:NSMakeRect(16,2,968,21)];
    _pointerLabel.autoresizingMask=NSViewWidthSizable|NSViewMaxYMargin;
    _pointerLabel.stringValue=@"ЛКМ / пробел: пауза · ПКМ: меню · Движение и перетаскивание: координаты";
    [self updateControls];
}
- (void)updateControls {
    _pauseButton.title=_animationPaused?@"Продолжить":@"Пауза";
    _pauseItem.title=_animationPaused?@"Продолжить анимацию":@"Приостановить анимацию";
    _pauseItem.state=_animationPaused?NSControlStateValueOn:NSControlStateValueOff;
    [self updateSummary];
}
- (void)updateSummary {
    _summary.stringValue=[NSString stringWithFormat:@"Кнопка: %lu · Кадр: %u · %@",(unsigned long)_clicks,_frames,_animationPaused?@"Пауза":@"Анимация идёт"];
}
- (void)countClick:(id)sender { ++_clicks;[self updateControls]; }
- (void)toggleAnimation:(id)sender { _animationPaused=!_animationPaused;[self updateControls]; }
- (void)singleFrame:(id)sender { _animationPaused=YES;[self updateControls];[self frame:nil]; }
- (void)closeWindow:(id)sender { [_window performClose:sender]; }
- (void)minimize:(id)sender { [_window performMiniaturize:sender]; }
- (void)zoomWindow:(id)sender { [_window performZoom:sender]; }
- (void)showAbout:(id)sender {
    NSAlert* alert=[NSAlert new];alert.messageText=@"Apple Metal Sample";
    alert.informativeText=@"Synchronizing CPU and GPU Work\n\nОфициальный пример Apple, MIT license. Renderer и шейдер сохранены без изменений.\n\nСборка, меню и управление окном: Darling Metal API, локальная версия 0.4.0.";
    [alert addButtonWithTitle:@"OK"];[alert runModal];
}
- (void)showHelp:(id)sender {
    NSAlert* alert=[NSAlert new];alert.messageText=@"Управление";
    alert.informativeText=@"«Нажми меня» увеличивает счётчик.\n\nЛКМ по сцене или пробел ставит анимацию на паузу. ПКМ открывает меню сцены.\n\n«Вид → Один кадр» останавливает анимацию и увеличивает номер кадра ровно на 1.\n\nМеню «Правка» работает с выделенным текстом в поле ввода.";
    [alert addButtonWithTitle:@"Понятно"];[alert runModal];
}
- (void)pointerEvent:(NSEvent*)event inView:(NSView*)view {
    NSPoint point=[view convertPoint:event.locationInWindow fromView:nil];
    _pointerLabel.stringValue=[NSString stringWithFormat:@"Мышь: x=%.0f y=%.0f · %@",point.x,point.y,
        event.type==NSLeftMouseDragged?@"Перетаскивание":event.type==NSLeftMouseDown?@"Нажатие":@"Движение"];
}
- (void)contextMenu:(NSEvent*)event inView:(NSView*)view {
    NSMenu* menu=[[NSMenu alloc] initWithTitle:@"Сцена"];
    [self item:_animationPaused?@"Продолжить":@"Пауза" action:@selector(toggleAnimation:) key:@"" menu:menu target:self];
    [self item:@"Один кадр" action:@selector(singleFrame:) key:@"" menu:menu target:self];
    [self item:@"Управление" action:@selector(showHelp:) key:@"" menu:menu target:self];
    [NSMenu popUpContextMenu:menu withEvent:event forView:view];
}
- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    [self buildMenus];
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();requireSample(device!=nil,"Metal device");
    NSError* error=nil;
    id<MTLLibrary> library=[device newDefaultLibraryWithBundle:[NSBundle mainBundle] error:&error];
    if (!library) std::fprintf(stderr,"Default library: %s\n",[[error description] UTF8String]);
    requireSample(library && !error,"newDefaultLibraryWithBundle loads packaged shader library");
    requireSample([library newFunctionWithName:@"vertexShader"] && [library newFunctionWithName:@"fragmentShader"],"official shader entry points");
    std::printf("PASS default library and Apple shader functions; device=%s\n",[device.name UTF8String]);
    _window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1000,600+controlHeight)
        styleMask:NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask backing:NSBackingStoreBuffered defer:NO];
    [_window setTitle:testMode ? @"Apple Metal Sample - Verification" : @"Darling Metal 0.4 - Native Controls"];
    [_window setReleasedWhenClosed:NO];[_window setDelegate:self];
    _view=[[SampleView alloc] initWithFrame:NSMakeRect(0,24,1000,600) device:device];
    _view.paused=YES;_view.enableSetNeedsDisplay=NO;
    _view.framebufferOnly=!testMode;
    _view.clearColor=MTLClearColorMake(.04,.05,.08,1);
    _view.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    [_window.contentView addSubview:_view];_view.inputDelegate=self;_window.acceptsMouseMovedEvents=YES;
    [self buildControls:_window.contentView];
    _renderer=[[AAPLRenderer alloc] initWithMetalKitView:_view];requireSample(_renderer!=nil,"official renderer initializes");
    [_renderer mtkView:_view drawableSizeWillChange:_view.drawableSize];_view.delegate=_renderer;
    [_window center];[_window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    _timer=[NSTimer scheduledTimerWithTimeInterval:1.0/60.0 target:self selector:@selector(frame:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)frame:(NSTimer*)timer {
    if (_animationPaused && timer) return;
    @try {
    [_view draw];++_frames;_phase+=.05f;
    if (_animationPaused || _frames%6==0) [self updateSummary];
    if (testMode && (_frames==1 || _frames==59 || _frames==119 || _frames==179)) {
        // Test-only queue barrier on this openly licensed sample's own queue.
        // No Apple framework internals are inspected or altered.
        Ivar ivar=class_getInstanceVariable([AAPLRenderer class],"_commandQueue");
        requireSample(ivar!=nullptr,"sample queue is available to the verification harness");
        id<MTLCommandQueue> queue=object_getIvar(_renderer,ivar);
        id<MTLCommandBuffer> barrier=[queue commandBuffer];[barrier commit];[barrier waitUntilCompleted];
        requireSample(barrier.error==nil,"sample queue completed before readback");
        id<MTLTexture> texture=_view.observedTexture;requireSample(texture!=nil,"rendered drawable texture");
        unsigned width=unsigned(texture.width),height=unsigned(texture.height);
        const size_t row=(size_t(width)*4+255)&~size_t(255);
        id<MTLBuffer> readback=[texture.device newBufferWithLength:row*height options:MTLResourceStorageModeShared];
        requireSample(readback!=nil,"drawable readback buffer");
        id<MTLCommandBuffer> copy=[queue commandBuffer];id<MTLBlitCommandEncoder> blit=[copy blitCommandEncoder];
        [blit copyFromTexture:texture sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
            sourceSize:MTLSizeMake(width,height,1) toBuffer:readback destinationOffset:0
            destinationBytesPerRow:row destinationBytesPerImage:row*height];
        [blit endEncoding];[copy commit];[copy waitUntilCompleted];requireSample(copy.error==nil,"drawable blit completion");
        std::vector<unsigned char> pixels(size_t(width)*height*4);
        for (unsigned y=0;y<height;++y) std::memcpy(pixels.data()+size_t(y)*width*4,
            static_cast<unsigned char*>(readback.contents)+size_t(y)*row,size_t(width)*4);
        auto result=AppleSample::validate(pixels,width,height,_phase);
        auto wrong=AppleSample::validate(pixels,width,height,_phase+1);
        std::printf("APPLE frame=%u size=%ux%u checked=%zu mismatches=%zu interiors=%zu wrong-phase=%zu\n",
            _frames,width,height,result.checked,result.mismatches,result.triangles,wrong.mismatches);
        requireSample(result.checked>50000 && result.triangles>1000 && result.mismatches==0,"official renderer matches independent analytic CPU reference");
        requireSample(wrong.mismatches>1000,"wrong animation phase is rejected");
    }
    if (testMode && _frames==60) [_window setContentSize:NSMakeSize(800,500+controlHeight)];
    if (testMode && _frames==120) [_window setContentSize:NSMakeSize(640,420+controlHeight)];
    if (testMode && _frames==180) { std::printf("PASS Apple sample 180 frames, three in-flight buffers, resize and close\n");[_window performClose:nil]; }
    } @catch (NSException* exception) {
        std::fprintf(stderr,"FAIL Apple sample frame: %s\n",[[exception description] UTF8String]);std::exit(1);
    }
}
- (BOOL)windowShouldClose:(id)sender {
    if (testMode) requireSample(_frames==180,"verification window was closed before all frames completed");
    [_timer invalidate];[NSApp terminate:nil];return YES;
}
@end

int main(int argc,char** argv) {
    @autoreleasepool {
        requireSample(argc==1 || (argc==2 && (std::strcmp(argv[1],"--test")==0 || std::strcmp(argv[1],"--library-test")==0 || std::strcmp(argv[1],"--menu-test")==0 || std::strcmp(argv[1],"--menu-raw-test")==0 || std::strcmp(argv[1],"--menu-alert-test")==0)),"usage: apple-metal-sample [--test|--library-test|--menu-test|--menu-raw-test|--menu-alert-test]");
        if (argc==2 && std::strcmp(argv[1],"--library-test")==0) { verifyPortableLibraries();return 0; }
        if (argc==2 && std::strcmp(argv[1],"--menu-test")==0) { runMenuContractTest(false,false);return 0; }
        if (argc==2 && std::strcmp(argv[1],"--menu-raw-test")==0) { runMenuContractTest(true,false);return 0; }
        if (argc==2 && std::strcmp(argv[1],"--menu-alert-test")==0) { runMenuContractTest(true,true);return 0; }
        testMode=argc==2;
        [NSApplication sharedApplication];
        SampleApplication* delegate=[SampleApplication new];[NSApp setDelegate:delegate];[NSApp run];
    }
    return 0;
}
