package main

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import ma "vendor:miniaudio"

// ============================================================================
// Constants Start
// ============================================================================
CLEAR_SCREEN_CHAR :: "\x1b[2J"
CONFIG_DIR :: "verdandi"
// move cursor to home (top-left)
CURSOR_HOME_CHAR :: "\x1b[H"

DEFAULT_SOUND_FILE :: #load("./default-sound-effects/perfect.mp3")

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
	has_custom_audio_file:       bool,
	custom_audio_file_extension: string,
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

// ============================================================================
// Parse Sound File Start
// ============================================================================
validate_audio_file :: proc(path: string) -> (valid: bool, err: ma.result) {
	cpath := strings.clone_to_cstring(path, context.temp_allocator)

	test_decoder: ma.decoder
	dec_config: ma.decoder_config
	result := ma.decoder_init_file(cpath, &dec_config, &test_decoder)
	if result != .SUCCESS {
		return false, result
	}

	ma.decoder_uninit(&test_decoder)

	return true, .SUCCESS
}
// ============================================================================
// Parse Sound File End
// ============================================================================


main :: proc() {
	// see if config directory exists
	config_dir_name := get_config_dir()

	config_file_name, _ := filepath.join({config_dir_name, "config.json"})

	config: Config

	if !os.exists(config_dir_name) {

		err := os.make_directory_all(config_dir_name)
		if err != nil {
			fmt.printfln(
				"the config directory could not be completed with the following error: %v",
				err,
			)
		}

		config = Config{}

		// since this is just a 0 value for a struct, should be able to initialize with no error and not worry about it
		data, _ := json.marshal(config)

		err = os.write_entire_file(config_file_name, data)
		if err != nil {
			fmt.printfln("config init could not be completed with the following error: %v", err)
			return
		}
	} else {
		data, err := os.read_entire_file(config_file_name, context.temp_allocator)
		if err != nil {
			fmt.println("config file not found; falling back to default sound")
			config = Config{}
		}

		unmarshal_err := json.unmarshal(data, &config)
		if unmarshal_err != nil {
			fmt.println("could not parse config; falling back to default sound")
			config = Config{}
		}
	}


	// parse cli flags
	opts: Options

	flags.parse_or_exit(&opts, os.args, .Unix)

	if opts.custom_audio_file_path != "" {
		valid, ma_err_result := validate_audio_file(opts.custom_audio_file_path)
		if !valid {
			fmt.printfln(
				"invalid custom audio file for the following reason: %v.  please choose another file",
				ma_err_result,
			)
		}

		// copy file to custom path; handle errors if failed
		data, err := os.read_entire_file(opts.custom_audio_file_path, context.temp_allocator)
		if err != nil {
			fmt.printfln(
				"the custom file could not be read from %s.  please update the path and try again",
				opts.custom_audio_file_path,
			)
			return
		}

		file_ext := filepath.ext(opts.custom_audio_file_path)

		custom_file_name := strings.join({"custom-audio-file", file_ext}, "")

		path, _ := filepath.join({config_dir_name, custom_file_name})

		err = os.write_entire_file(path, data)
		if err != nil {
			fmt.printfln(
				"custom audio file could not be copied from %s to %s.  please check the file and try again",
				opts.custom_audio_file_path,
				path,
			)
			return
		}

		// flip config to have custom audio file now that it's been copied to the correct spot
		config.has_custom_audio_file = true
		config.custom_audio_file_extension = file_ext

		data, _ = json.marshal(config)

		err = os.write_entire_file(config_file_name, data)
		if err != nil {
			fmt.printfln("config init could not be completed with the following error: %v", err)
			return
		}


		// this needs to go at the end once all file operations and seeing if the audio file is valid are complete
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

	defer cleanup_audio()

	result: ma.result

	if (config.has_custom_audio_file) {
		custom_file_name := strings.join(
			{"custom-audio-file", config.custom_audio_file_extension},
			"",
		)

		path, err := filepath.join({config_dir_name, custom_file_name})

		if err != nil {
			fmt.printfln("filepath could not be created with the following error")
		}

		cpath := strings.clone_to_cstring(path, context.temp_allocator)

		result = ma.decoder_init_file(cpath, &dec_config, &decoder)

	} else {
		result = ma.decoder_init_memory(
			raw_data(DEFAULT_SOUND_FILE),
			len(DEFAULT_SOUND_FILE),
			&dec_config,
			&decoder,
		)


	}

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
