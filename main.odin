package main

import "core:flags"
import "core:fmt"
import "core:os"

import ma "vendor:miniaudio"

// visual handling
CLEAR_SCREEN_CHAR :: "\x1b[2J"
ALTERNATE_SCREEN_BUFFER_CHAR :: "\x1b[?1049h"
// move cursor to home (top-left)
CURSOR_HOME_CHAR :: "\x1b[H"

clear_screen :: proc() {
	os.write_string(os.stdout, CLEAR_SCREEN_CHAR + CURSOR_HOME_CHAR)
}

// ============================================================================
// Audio Processing Code Start
// ============================================================================
engine: ma.engine

init_audio :: proc() {
	config := ma.engine_config_init()
	if ma.engine_init(&config, &engine) != .SUCCESS {
		// handle error
		return
	}
	ma.engine_start(&engine)
}

cleanup_audio :: proc() {
	ma.engine_uninit(&engine)
}

play_file :: proc(path: cstring) {
	ma.engine_play_sound(&engine, path, nil)
}
// ============================================================================
// Audio Processing Code End
// ============================================================================

// ============================================================================
// CLI Flags Start
// ============================================================================
Options :: struct {
	audio_file_path: string `args:"name=audio-file-path"`,
}
// ============================================================================
// CLI Flags End
// ============================================================================


main :: proc() {
	opts: Options

	flags.parse_or_exit(&opts, os.args, .Unix)

	if (opts.audio_file_path == "") {
		fmt.println("there is no audio path")
		return
	} else {
		fmt.printfln("the following audio path was found: %s", opts.audio_file_path)
		return
	}

	// sets the terminal apperance to raw and not cooked to turn off default echo behavior and treat it more like a game engine
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
