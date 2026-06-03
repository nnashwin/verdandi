#+build linux, darwin
package main

import "core:sys/posix"

// copy of the terminals original settings so we can restore it on program return
@(private="file") orig_termios: posix.termios

orig_termios: posix.termios

enable_raw_mode :: proc() {
    posix.tcgetattr(posix.STDIN_FILENO, &orig_termios)
    raw := orig_termios

    raw.c_lflag -= {.ECHO, .ICANON, .ISIG, .IEXTEN}
    raw.c_iflag -= {.IXON, .ICRNL, .BRKINT, .INPCK, .ISTRIP}
    raw.c_oflag -= {.OPOST}

    posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw)
}

disable_raw_mode :: proc() {
    posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &orig_termios)
}
