#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Send X11 protocol events only to the standalone AppKit menu-test fixture.

Start `run-render.py apple-menu-raw-test` first. This does not move the desktop
pointer or operate another app; the fixture exits after receiving its action.
"""
import ctypes as c
import ctypes.util
import time
import argparse
import os
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--grab-focus-events",action="store_true",help="exercise focus notifications that do not change X input focus")
parser.add_argument("--popup-focus-transfer",action="store_true",help="transfer actual focus to the owned popup on a private test X server")
args=parser.parse_args()
if args.popup_focus_transfer and os.environ.get("METALAPI_PRIVATE_X11")!=os.environ.get("DISPLAY"):
    raise SystemExit("focus-transfer checks require the isolated Xvfb runner")

x=c.CDLL(ctypes.util.find_library('X11'))
D=c.c_void_p
W=c.c_ulong
class Button(c.Structure):
    _fields_=[('type',c.c_int),('serial',W),('send_event',c.c_int),('display',D),
              ('window',W),('root',W),('subwindow',W),('time',W),('x',c.c_int),('y',c.c_int),
              ('x_root',c.c_int),('y_root',c.c_int),('state',c.c_uint),('button',c.c_uint),('same_screen',c.c_int)]
class Attributes(c.Structure):
    _fields_=[('background_pixmap',W),('background_pixel',W),('border_pixmap',W),('border_pixel',W),
              ('bit_gravity',c.c_int),('win_gravity',c.c_int),('backing_store',c.c_int),
              ('backing_planes',W),('backing_pixel',W),('save_under',c.c_int),
              ('event_mask',c.c_long),('do_not_propagate_mask',c.c_long),('override_redirect',c.c_int),
              ('colormap',W),('cursor',W)]
class Focus(c.Structure):
    _fields_=[("type",c.c_int),("serial",W),("send_event",c.c_int),("display",D),("window",W),("mode",c.c_int),("detail",c.c_int)]
class Event(c.Union):
    _fields_=[('button',Button),('focus',Focus),('padding',c.c_long*24)]
x.XOpenDisplay.argtypes=[c.c_char_p];x.XOpenDisplay.restype=D
x.XDefaultRootWindow.argtypes=[D];x.XDefaultRootWindow.restype=W
x.XQueryTree.argtypes=[D,W,c.POINTER(W),c.POINTER(W),c.POINTER(c.POINTER(W)),c.POINTER(c.c_uint)]
x.XFetchName.argtypes=[D,W,c.POINTER(D)];x.XFree.argtypes=[D]
x.XGetGeometry.argtypes=[D,W,c.POINTER(W),c.POINTER(c.c_int),c.POINTER(c.c_int),c.POINTER(c.c_uint),c.POINTER(c.c_uint),c.POINTER(c.c_uint),c.POINTER(c.c_uint)]
x.XTranslateCoordinates.argtypes=[D,W,W,c.c_int,c.c_int,c.POINTER(c.c_int),c.POINTER(c.c_int),c.POINTER(W)]
x.XSendEvent.argtypes=[D,W,c.c_int,c.c_long,c.POINTER(Event)]
x.XGetTransientForHint.argtypes=[D,W,c.POINTER(W)]
x.XCreateSimpleWindow.argtypes=[D,W,c.c_int,c.c_int,c.c_uint,c.c_uint,c.c_uint,W,W];x.XCreateSimpleWindow.restype=W
x.XMapWindow.argtypes=[D,W]
x.XChangeWindowAttributes.argtypes=[D,W,c.c_ulong,c.POINTER(Attributes)]
x.XSetInputFocus.argtypes=[D,W,c.c_int,W]
x.XGetInputFocus.argtypes=[D,c.POINTER(W),c.POINTER(c.c_int)]
x.XFlush.argtypes=[D];x.XCloseDisplay.argtypes=[D]
d=x.XOpenDisplay(None)
if not d:raise SystemExit('X11 display is unavailable')
root=x.XDefaultRootWindow(d)
def windows():
    result=set();queue=[root]
    while queue:
        w=queue.pop();result.add(w);r,p=W(),W();children=c.POINTER(W)();n=c.c_uint()
        if x.XQueryTree(d,w,c.byref(r),c.byref(p),c.byref(children),c.byref(n)):
            queue.extend(children[i] for i in range(n.value))
            if children:x.XFree(children)
    return result
def name(w):
    value=D()
    if x.XFetchName(d,w,c.byref(value)) and value.value:
        result=c.string_at(value).decode(errors='replace');x.XFree(value);return result
    return ''
def size(w):
    r=W();px,py=c.c_int(),c.c_int();width,height,border,depth=(c.c_uint() for _ in range(4))
    if not x.XGetGeometry(d,w,c.byref(r),c.byref(px),c.byref(py),c.byref(width),c.byref(height),c.byref(border),c.byref(depth)):return (0,0)
    return width.value,height.value
def ownedPopup(w,target):
    owner=W()
    return x.XGetTransientForHint(d,w,c.byref(owner)) and owner.value==target
def send(w,kind,px,py):
    gx,gy=c.c_int(),c.c_int();child=W()
    if not x.XTranslateCoordinates(d,w,root,px,py,c.byref(gx),c.byref(gy),c.byref(child)):raise RuntimeError('fixture coordinates unavailable')
    event=Event();b=event.button;b.type=kind;b.display=d;b.window=w;b.root=root;b.time=int(time.monotonic()*1000)&0xffffffff
    b.x=px;b.y=py;b.x_root=gx.value;b.y_root=gy.value;b.same_screen=1;b.state=256 if kind==5 else 0;b.button=0 if kind==6 else 1
    mask={4:1<<2,5:1<<3,6:1<<6}[kind]
    if not x.XSendEvent(d,w,False,mask,c.byref(event)):raise RuntimeError('XSendEvent failed')
    x.XFlush(d);time.sleep(.12)
def grabFocus(w,kind,mode):
    event=Event();f=event.focus;f.type=kind;f.display=d;f.window=w;f.mode=mode;f.detail=0
    x.XSendEvent(d,w,False,1<<21,c.byref(event));x.XFlush(d);time.sleep(.08)
try:
    deadline=time.monotonic()+5;target=None
    while time.monotonic()<deadline and target is None:
        target=next((w for w in windows() if name(w)=='AppKit raw menu test - READY'),None)
        if target is None:time.sleep(.05)
    if target is None:raise RuntimeError('start apple-menu-raw-test first')
    if args.popup_focus_transfer:
        # Native child focus produces NotifyNonlinearVirtual on the parent,
        # matching the recorded real-window transition to the submenu.
        child=x.XCreateSimpleWindow(d,target,200,50,20,20,0,0,0)
        attributes=Attributes();attributes.override_redirect=1
        x.XChangeWindowAttributes(d,child,1<<9,c.byref(attributes))
        x.XMapWindow(d,child);x.XSetInputFocus(d,child,1,0);x.XFlush(d);time.sleep(.15)
    before=windows();print('Fixture X11 size:',size(target),flush=True)
    send(target,4,15,10);send(target,5,15,10)
    deadline=time.monotonic()+2;popup=None
    while time.monotonic()<deadline and popup is None:
        popup=next((w for w in windows()-before if ownedPopup(w,target) and
                    40<size(w)[0]<300 and 10<size(w)[1]<100),None)
        if popup is None:time.sleep(.05)
    if popup is None:raise RuntimeError('raw click did not open fixture menu')
    print('Popup X11 size:',size(popup),flush=True)
    send(popup,6,10,1);send(popup,6,10,10)
    if args.grab_focus_events:
        focused=W();revert=c.c_int();x.XGetInputFocus(d,c.byref(focused),c.byref(revert));beforeFocus=focused.value
        grabFocus(target,10,1)  # FocusOut / NotifyGrab
        grabFocus(target,9,2)   # FocusIn / NotifyUngrab
        x.XGetInputFocus(d,c.byref(focused),c.byref(revert))
        if focused.value!=beforeFocus:raise RuntimeError("fixture focus actually changed")
    if args.popup_focus_transfer:
        x.XSetInputFocus(d,popup,1,0);x.XFlush(d);time.sleep(.1)
    send(popup,4,10,10);send(popup,5,10,10)
    deadline=time.monotonic()+2
    while time.monotonic()<deadline:
        if name(target)=='AppKit raw menu test - PASS':print('PASS X11 events → NSMenu → target/action');break
        time.sleep(.03)
    else:raise RuntimeError('raw submenu click did not invoke its action')
finally:x.XCloseDisplay(d)
