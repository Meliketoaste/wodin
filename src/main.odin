#+feature dynamic-literals
package main

import "core:fmt"
import x "vendor:x11/xlib"
import "core:c/libc"

NUM_WORKSPACES :: 5
current_ws: u8

display: ^x.Display
root: x.Window
e: x.XEvent

spaces: [NUM_WORKSPACES]struct {
    windows: [dynamic]x.Window,
}

find_index :: proc(arr: ^[dynamic]x.Window, myWindow: x.Window) -> int {
    for window, i in arr^ {
        if window == myWindow { return i }
    }
    return -1
}

main :: proc() {
    display = x.OpenDisplay(nil)
    root = x.DefaultRootWindow(display)
    x.SelectInput(display, root, {.SubstructureRedirect, .SubstructureNotify, .KeyPress, .StructureNotify, .FocusChange})

    for keymap in keyMaps {
        x.GrabKey(display, i32(x.KeysymToKeycode(display, keymap.key)), keymap.mod, root, true, .GrabModeAsync, .GrabModeAsync) 
    }

    for {
        x.NextEvent(display, &e)
        if e.type == .ConfigureRequest {
            x.MoveResizeWindow(display, e.xconfigurerequest.window, 0, 0, u32(e.xconfigurerequest.width), u32(e.xconfigurerequest.height))
        }
        if e.type == .MapRequest {
            if find_index(&spaces[current_ws].windows, e.xmaprequest.window) < 0 {
                append(&spaces[current_ws].windows, e.xmaprequest.window)
            }
            x.MapWindow(display, e.xmaprequest.window)
            x.SetInputFocus(display, e.xmaprequest.window, .RevertToParent, x.CurrentTime)
        }
        if e.type == .DestroyNotify {
            for &workspace in spaces {
                idx := find_index(&workspace.windows, e.xdestroywindow.window)
                if idx >= 0 do unordered_remove(&spaces[current_ws].windows, idx)
            }
        }
        if e.type == .KeyPress {
            for keymap in keyMaps {
                if u8(e.xkey.keycode) == x.KeysymToKeycode(display, keymap.key) do keymap.action()
            }
        }
    }
}


change_current_ws :: proc (ws: u8) {
    for win in spaces[current_ws].windows do x.UnmapWindow(display, win)
    current_ws = ws
    for win in spaces[current_ws].windows do x.MapWindow(display, win)
}

keyMaps: = [?]struct{mod: x.InputMask, key: x.KeySym, action: proc()} {
    {{.Mod4Mask}, .XK_n, proc() {
        x.CirculateSubwindowsUp(display, root) 
        (x.SetInputFocus(display, e.xkey.window, .RevertToParent , 0))
    }},
    {{.Mod4Mask}, .XK_q, proc() {
        x.KillClient(display, e.xkey.subwindow)
    }},
    {{.Mod4Mask} ,.XK_e, proc() {
        libc.system("dmenu_run &") 
    }},
    {{.Mod4Mask, .ShiftMask}, .XK_f, proc() {
        screen := x.DefaultScreen(display)
        x.MoveResizeWindow(display, e.xkey.subwindow, 0, 0, u32(x.DisplayWidth(display, screen)), u32(x.DisplayHeight(display, screen)))
    }},
    {{.Mod4Mask}, .XK_t, proc() {
        for win in spaces[current_ws].windows {
            x.MapWindow(display, win)
        }
    }},
    {{.Mod4Mask}, .XK_y, proc() {
        for win in spaces[current_ws].windows {
            x.UnmapWindow(display, win)
        }
    }},
    {{.Mod4Mask}, .XK_1, proc() { change_current_ws(0) }},
    {{.Mod4Mask}, .XK_2, proc() { change_current_ws(1) }},
    {{.Mod4Mask}, .XK_3, proc() { change_current_ws(2) }},
    {{.Mod4Mask}, .XK_4, proc() { change_current_ws(3) }},
    {{.Mod4Mask}, .XK_5, proc() { change_current_ws(4) }},
}
