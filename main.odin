package main

import "core:flags"
import "core:fmt"
import "core:os"
import "core:path/filepath"

import ma "vendor:miniaudio"

// ============================================================================
// Constants Start
// ============================================================================
CLEAR_SCREEN_CHAR :: "\x1b[2J"
CONFIG_DIR :: "verdandi"
// move cursor to home (top-left)
CURSOR_HOME_CHAR :: "\x1b[H"

CUSTOM_SOUND_FILE :: #load("./default-sound-effects/perfect.mp3")

ENTER_ALT_SCREEN :: "\x1b[?1049h"
LEAVE_ALT_SCREEN :: "\x1b[?1049l" // lowercase L


// ============================================================================
// Constants End
// ============================================================================

// ============================================================================
// Video Processing Start
// ============================================================================
clear_screen :: proc() {
	os.write_string(os.stdout, CLEAR_SCREEN_CHAR + CURSOR_HOME_CHAR)
}
// ============================================================================
// Video Processing End
// ============================================================================

// ============================================================================
// Audio Processing Code Start
// ============================================================================
decoder: ma.decoder
dec_config: ma.decoder_config
engine: ma.engine
sound: ma.sound

init_audio :: proc() -> ma.result {
	config := ma.engine_config_init()
	init_result := ma.engine_init(&config, &engine)
	if init_result != .SUCCESS do return init_result

	start_result := ma.engine_start(&engine)
	if start_result != .SUCCESS {
		ma.engine_uninit(&engine)
		return start_result
	}

	return .SUCCESS
}

cleanup_audio :: proc() {
	ma.sound_uninit(&sound)
	ma.decoder_uninit(&decoder)
	ma.engine_uninit(&engine)
}

play_file :: proc(path: cstring) {
	ma.engine_play_sound(&engine, path, nil)
}
// ============================================================================
// Audio Processing Code End
// ============================================================================

Options :: struct {
	custom_audio_file_path: string `args:"name=audio_file_path" usage:"sets custom audio file path"`,
}

// ============================================================================
// Config Code Start
// ============================================================================
Config :: struct {
	audio_file_path: string,
}

get_config_dir :: proc() -> string {
	when ODIN_OS == .Windows {
		base := os.get_env_alloc("APPDATA", context.temp_allocator)
	} else {
		base := os.get_env_alloc("HOME", context.temp_allocator)
		base = fmt.tprintf("%s/.config", base)
	}

	return fmt.tprintf("%s/%s", base, CONFIG_DIR)
}

// ============================================================================
// Config Code End
// ============================================================================

main :: proc() {
	dir_name := get_config_dir()

	config_file_name, _ := filepath.join({dir_name, "config.json"})

	if !os.exists(config_file_name) {
		err := os.write_entire_file(config_file_name, `{
        audio_file_path: ''
    }`)
		if err != nil {
			fmt.printfln("config init could not be completed with the following error: %v", err)
			return
		}
	}

	defer cleanup_audio()

	opts: Options

	flags.parse_or_exit(&opts, os.args, .Unix)

	if opts.custom_audio_file_path != "" {
		fmt.printfln(
			"verdandi will now use '%s' as the audio file when the timer is complete",
			opts.custom_audio_file_path,
		)
		return
	}


	// initialize audio
	audio_result := init_audio()
	if audio_result != .SUCCESS {
		fmt.printfln(
			"audio could not init for your device for the following reason: %v.  Please resolve and try again",
			audio_result,
		)
		return
	}

	result := ma.decoder_init_memory(
		raw_data(CUSTOM_SOUND_FILE),
		len(CUSTOM_SOUND_FILE),
		&dec_config,
		&decoder,
	)

	if result == .SUCCESS {
		ma.sound_init_from_data_source(&engine, decoder.ds.pCurrent, {}, nil, &sound)
		ma.sound_set_looping(&sound, true)
		ma.sound_start(&sound)
	} else {
		fmt.printfln(
			"The audio was not able to be initialized with the following error: %v",
			result,
		)
		return
	}

	// sets the terminal apperance to raw and not cooked to turn off default echo behavior and treat it more like a game engine
	enable_raw_mode()
	defer disable_raw_mode()

	// enter alt screen so that we can restore the previous terminal once the tui is finished
	os.write_string(os.stdout, ENTER_ALT_SCREEN)
	defer os.write_string(os.stdout, LEAVE_ALT_SCREEN)

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
		if c == 'q' || c == 3 {
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
