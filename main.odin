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

init_audio_and_check_validity :: proc() -> bool {
	config := ma.engine_config_init()
	if ma.engine_init(&config, &engine) != .SUCCESS {
		// handle error
		return false
	}
	ma.engine_start(&engine)
	return true
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
	custom_audio_file_path: string `args:"name=audio_file_path" usage:"sets custom audio file path"`,
}
// ============================================================================
// CLI Flags End
// ============================================================================


main :: proc() {
	is_audio_initted := init_audio_and_check_validity()
	if is_audio_initted {
		fmt.println("audio is initted")
	} else {
		fmt.println("audio could not init")
	}

	sound: ma.sound
	result := ma.sound_init_from_file(
		&engine,
		"./default-sound-effects/lets-fight-like-gentlemen.wav",
		nil,
		nil,
		nil,
		&sound,
	)

	if result == .SUCCESS {
		ma.sound_set_looping(&sound, true)
		ma.sound_start(&sound)
	}

	opts: Options

	flags.parse_or_exit(&opts, os.args, .Unix)

	if opts.custom_audio_file_path != "" {
		fmt.printfln(
			"verdandi will now use '%s' as the audio file when the timer is complete",
			opts.custom_audio_file_path,
		)
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
			break
		}

		c := buf[0]
		if c == 'q' {
			ma.sound_stop(&sound)
			break
		}

		if c >= 32 && c < 127 {
			fmt.printf("%d, ('%c')\r\n", c, rune(c))
		} else {
			fmt.printf("%d\r\n", c)
		}
	}
}
