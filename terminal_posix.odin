#+build linux, darwin
package main

import "core:c"
import "core:sys/posix"

foreign import libc "system:c"

foreign libc {
	ioctl :: proc "c" (fd: c.int, request: c.ulong, #c_vararg args: ..any) -> c.int ---
}

// copy of the terminals original settings so we can restore it on program return
@(private = "file")
orig_termios: posix.termios

Winsize :: struct {
	ws_row:    u16,
	ws_col:    u16,
	ws_xpixel: u16,
	ws_ypixel: u16,
}

when ODIN_OS == .Darwin {
	TIOCGWINSZ :: 0x40087468
} else {
	TIOCGWINSZ :: 0x5413
}

enable_raw_mode :: proc() {
	posix.tcgetattr(posix.STDIN_FILENO, &orig_termios)
	raw := orig_termios

	raw.c_lflag -= {.ECHO, .ICANON, .ISIG, .IEXTEN}
	raw.c_iflag -= {.IXON, .ICRNL, .BRKINT, .INPCK, .ISTRIP}
	raw.c_oflag -= {.OPOST}

	raw.c_cc[.VMIN] = 0
	raw.c_cc[.VTIME] = 1

	posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw)
}

disable_raw_mode :: proc() {
	posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &orig_termios)
}

get_terminal_size :: proc() -> (width: int, height: int) {
	ws: Winsize
	ioctl(posix.STDIN_FILENO, TIOCGWINSZ, &ws)
	return int(ws.ws_col), int(ws.ws_row)
}
