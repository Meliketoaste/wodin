#+feature dynamic-literals
package main

import "core:fmt"
import x "vendor:x11/xlib"
import "core:c/libc"

NUM_WORKSPACES :: 10
current_ws: u8

display: ^x.Display
root: x.Window
e: x.XEvent

spaces: [NUM_WORKSPACES]struct {
    windows: [dynamic]x.Window,
    focused: x.Window,
}

find_index :: proc(arr: ^[dynamic]x.Window, myWindow: x.Window) -> int {
    for window, i in arr^ {
        if window == myWindow { return i }
    }
    return -1
}

master_ratio :: 50

tile :: proc(ws: ^[dynamic]x.Window) {
    if len(ws) == 0 { return }
    s := x.DefaultScreen(display)
    sw := x.DisplayWidth(display, s)
    sh := x.DisplayHeight(display, s)

    if len(ws) == 1 {
        x.MoveResizeWindow(display, ws[0], 0, 0, u32(sw), u32(sh))
        return
    }

    mw := i32(sw * master_ratio / 100)
    if mw < 1 { mw = sw/2 }
    x.MoveResizeWindow(display, ws[0], 0, 0, u32(mw), u32(sh))

    y: i32 = 0
    for i := 1; i < len(ws); i += 1 {
        h: i32
        if i == len(ws)-1 {
            h = sh - y
        } else {
            h = sh / i32(len(ws) - 1)
        }
        x.MoveResizeWindow(display, ws[i], mw, y, u32(sw - mw), u32(h))
        y += h
    }
}

main :: proc() {
    display = x.OpenDisplay(nil)
    root = x.DefaultRootWindow(display)
    x.SelectInput(display, root, {.SubstructureRedirect, .SubstructureNotify, .KeyPress, .StructureNotify, .FocusChange})

    x.SetErrorHandler(proc "c" (display: ^x.Display, err: ^x.XErrorEvent) -> i32 { return 0 })
    for keymap in keyMaps {
        x.GrabKey(display, i32(x.KeysymToKeycode(display, keymap.key)), keymap.mod, root, true, .GrabModeAsync, .GrabModeAsync) 
    }

    for {
        x.NextEvent(display, &e)
        #partial switch e.type {
        case .ConfigureRequest: 
            if find_index(&spaces[current_ws].windows, e.xconfigurerequest.window) >= 0 {
                tile(&spaces[current_ws].windows)
            } else {
                x.MoveResizeWindow(
                    display, e.xconfigurerequest.window,
                    e.xconfigurerequest.x, e.xconfigurerequest.y,
                    u32(e.xconfigurerequest.width), u32(e.xconfigurerequest.height),
                )
            }

        case .MapRequest: 
            if find_index(&spaces[current_ws].windows, e.xmaprequest.window) < 0 {
                append(&spaces[current_ws].windows, e.xmaprequest.window)
            }
            x.MapWindow(display, e.xmaprequest.window)
            focus_window(e.xmaprequest.window)
            tile(&spaces[current_ws].windows)

        case .DestroyNotify:
            idx := find_index(&spaces[current_ws].windows, e.xdestroywindow.window)
            if idx >= 0 {
                unordered_remove(&spaces[current_ws].windows, idx)
                tile(&spaces[current_ws].windows)
            }

        case .KeyPress:
            for keymap in keyMaps {
                if u8(e.xkey.keycode) == x.KeysymToKeycode(display, keymap.key) do keymap.action()
            }
        }
    }
}

focus_window :: proc(w: x.Window) {
    if w == 0 { return }
    spaces[current_ws].focused = w
    x.RaiseWindow(display, w)
    x.SetInputFocus(display, w, .RevertToParent, x.CurrentTime)
}

focus_rel :: proc(step: int) {
    if len(spaces[current_ws].windows) == 0 { return }
    i := find_index(&spaces[current_ws].windows, spaces[current_ws].focused)
    if i < 0 {
        focus_window(spaces[current_ws].windows[0])
        return
    }
    i = (i + step + len(spaces[current_ws].windows)) % len(spaces[current_ws].windows)
    focus_window(spaces[current_ws].windows[i])
}


change_current_ws :: proc(ws: u8) {
    if ws >= NUM_WORKSPACES || ws == current_ws { return }
    for win in spaces[current_ws].windows do x.UnmapWindow(display, win)
    for win in spaces[ws].windows do x.MapWindow(display, win)
    current_ws = ws

    if spaces[current_ws].focused != 0 && find_index(&spaces[current_ws].windows, spaces[current_ws].focused) >= 0 {
        focus_window(spaces[current_ws].focused)
    } else if len(spaces[current_ws].windows) > 0 {
        focus_window(spaces[current_ws].windows[0])
    } else {
        spaces[current_ws].focused = 0
    }
    tile(&spaces[current_ws].windows)
}

keyMaps: = [?]struct{mod: x.InputMask, key: x.KeySym, action: proc()} {
    {{.Mod4Mask}, .XK_j, proc(){ focus_rel(+1) }},
    {{.Mod4Mask}, .XK_k, proc(){ focus_rel(-1) }},
    {{.Mod4Mask, .ShiftMask}, .XK_q, proc() {
        protocols: [^]x.Atom
        count: i32 = 0
        wm_delete := x.InternAtom(display, "WM_DELETE_WINDOW", false)
        if x.GetWMProtocols(display, spaces[current_ws].focused, &protocols, &count) != .Success {
            for i in 0..<count {
                if protocols[i] == wm_delete {
                    x.SendEvent(display, spaces[current_ws].focused, false, {}, &{ xclient = {
                        type = .ClientMessage,
                        window = spaces[current_ws].focused,
                        message_type = x.InternAtom(display, "WM_PROTOCOLS", false),
                        format = 32,
                        data = { l = { 
                            0 = int(wm_delete), 
                            1 = x.CurrentTime,
                        }}, 
                    }})
                }
            }
            return
        }
        x.KillClient(display, e.xkey.subwindow)
    }},
    {{.Mod4Mask} ,.XK_e, proc() {
        libc.system("dmenu_run &") 
    }},
    {{.Mod4Mask, .ShiftMask}, .XK_f, proc() {
        screen := x.DefaultScreen(display)
        x.MoveResizeWindow(display, e.xkey.subwindow, 0, 0, u32(x.DisplayWidth(display, screen)), u32(x.DisplayHeight(display, screen)))
    }},
    {{.Mod4Mask}, .XK_1, proc() { change_current_ws(0) }},
    {{.Mod4Mask}, .XK_2, proc() { change_current_ws(1) }},
    {{.Mod4Mask}, .XK_3, proc() { change_current_ws(2) }},
    {{.Mod4Mask}, .XK_4, proc() { change_current_ws(3) }},
    {{.Mod4Mask}, .XK_5, proc() { change_current_ws(4) }},
    {{.Mod4Mask}, .XK_6, proc() { change_current_ws(5) }},
    {{.Mod4Mask}, .XK_7, proc() { change_current_ws(6) }},
    {{.Mod4Mask}, .XK_8, proc() { change_current_ws(7) }},
    {{.Mod4Mask}, .XK_9, proc() { change_current_ws(8) }},
    {{.Mod4Mask}, .XK_0, proc() { change_current_ws(9) }},
}
