package main

import "core:fmt"
import "core:os"
import "core:sys/posix"

CLEAR_SCREEN_CHARS :: "\x1b[2J"
// move cursor to home (top-left)
CURSOR_HOME_CHARS :: "\x1b[H"

// copy of the terminals original settings so we can restore it on program return
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

clear_screen :: proc() {
    os.write_string(os.stdout, CLEAR_SCREEN_CHARS + CURSOR_HOME_CHARS)
}

main :: proc() {
    enable_raw_mode()
    defer disable_raw_mode()

    clear_screen()

    buf: [1]byte
    for {
        n, err := os.read(os.stdin, buf[:])
        if n <= 0 do break
        if err != nil {
            fmt.print("You have encountered an error reading os.stdin.  ending the process. \r\n")
        }

        c := buf[0]
        if c == 'q' do break

        if c >= 32 && c < 127 {
            fmt.printf("%d, ('%c')\r\n", c, rune(c))
        } else {
            fmt.printf("%d\r\n", c)
        }
    }
}
