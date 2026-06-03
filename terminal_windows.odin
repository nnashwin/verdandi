package main

import win32 "core:sys/windows"

@(private="file") orig_in_mode: win32.DWORD
@(private="file") orig_out_mode: win32.DWORD

enable_raw_mode :: proc() {
    hin := win32.GetStdHandle(win32.STD_INPUT_HANDLE)
    hout := win32.GetStdHandle(win32.STD_INPUT_HANDLE)

    win32.GetConsoleMode(hin, &orig_in_mode)
    win32.GetConsoleMode(hout, &orig_out_mode)

    in_mode := orig_in_mode
    in_mode &~= (win32.ENABLE_LINE_INPUT | win32.ENABLE_ECHO_INPUT | win32.ENABLE_PROCESSED_INPUT)
    in_mode |= win32.ENABLE_VIRTUAL_TERMINAL_INPUT
    win32.SetConsoleMode(hin, in_mode)

    out_mode := orig_out_mode
    out_mode |= win32.ENABLE_VIRTUAL_TERMINAL_PROCESSING
    win32.SetConsoleMode(hout, out_mode)
}

disable_raw_mode :: proc() {
    hin := win32.GetStdHandle(win32.STD_INPUT_HANDLE)
    hout := win32.GetStdHandle(win32.STD_OUTPUT_HANDLE)

    win32.SetConsoleMode(hin, orig_in_mode)
    win32.SetConsoleMode(hout, orig_out_mode)
}
