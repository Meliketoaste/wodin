package main

import "core:fmt"
import x "vendor:x11/xlib"
import "core:c/libc"

display: ^x.Display
e: x.XEvent
root: x.Window

main :: proc() {
    display = x.OpenDisplay(nil)
    root = x.DefaultRootWindow(display)

    x.SelectInput(display, root, {.SubstructureRedirect, .SubstructureNotify, .KeyPress, .StructureNotify, .FocusChange})

    for keymap in keyMaps {
        x.GrabKey(display, i32(x.KeysymToKeycode(display, keymap.key)), {.Mod4Mask}, root, true, .GrabModeAsync, .GrabModeAsync) 
    }

    for {
        x.NextEvent(display, &e)
        if e.type == .ConfigureRequest {
            x.MoveResizeWindow(display, e.xconfigurerequest.window, 0, 0, u32(e.xconfigurerequest.width), u32(e.xconfigurerequest.height))
        }
        if e.type == .MapRequest {
            x.MapWindow(display, e.xmaprequest.window)
            x.SetInputFocus(display, e.xmaprequest.window, .RevertToParent, x.CurrentTime)
        }
        if e.type == .KeyPress {
            for keymap in keyMaps {
                if u8(e.xkey.keycode) == x.KeysymToKeycode(display, keymap.key) do keymap.action()
            }
        }
    }
}

keyMaps: = [?]struct{key: x.KeySym, action: proc()} {
    {.XK_n, proc() {
        x.CirculateSubwindowsUp(display, root); 
        x.SetInputFocus(display, e.xkey.window, .RevertToParent, 0)
    }},
    {.XK_q, proc() {
        x.KillClient(display, e.xkey.subwindow)
    }},
    {.XK_e, proc() {
        libc.system("dmenu_run &") 
    }},
    {.XK_f, proc() {
        screen := x.DefaultScreen(display)
        x.MoveResizeWindow(display, e.xkey.subwindow, 0, 0, u32(x.DisplayWidth(display, screen)), u32(x.DisplayHeight(display, screen)))
    }},
}
