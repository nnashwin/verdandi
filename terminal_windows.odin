#+build windows
package main

import win32 "core:sys/windows"

@(private = "file")
orig_in_mode: win32.DWORD
@(private = "file")
orig_out_mode: win32.DWORD

disable_raw_mode :: proc() {
	hin := win32.GetStdHandle(win32.STD_INPUT_HANDLE)
	hout := win32.GetStdHandle(win32.STD_OUTPUT_HANDLE)

	win32.SetConsoleMode(hin, orig_in_mode)
	win32.SetConsoleMode(hout, orig_out_mode)
}

enable_raw_mode :: proc() {
	hin := win32.GetStdHandle(win32.STD_INPUT_HANDLE)
	hout := win32.GetStdHandle(win32.STD_OUTPUT_HANDLE)

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

enable_virtual_terminal :: proc() {
	stdout := win32.GetStdHandle(win32.STD_OUTPUT_HANDLE)
	mode: win32.DWORD
	win32.GetConsoleMode(stdout, &mode)
	mode |= win32.ENABLE_VIRTUAL_TERMINAL_PROCESSING
	win32.SetConsoleMode(stdout, mode)

	// enable utf-8 for our braille characters
	win32.SetConsoleOutputCP(win32.CODEPAGE(win32.CP_UTF8))
}

get_terminal_size :: proc() -> (int, int) {
	handle := win32.GetStdHandle(win32.STD_OUTPUT_HANDLE)
	info: win32.CONSOLE_SCREEN_BUFFER_INFO
	if win32.GetConsoleScreenBufferInfo(handle, &info) {
		width := int(info.srWindow.Right - info.srWindow.Left + 1)
		height := int(info.srWindow.Bottom - info.srWindow.Top + 1)
		return width, height
	}
	return 80, 24 // fallback
}
