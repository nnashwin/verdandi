package main

import "core:encoding/json"
import "core:flags"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import "core:time"

import ma "vendor:miniaudio"

CLEAR_SCREEN_CHAR :: "\x1b[2J"
CONFIG_DIR :: "verdandi"

// ============================================================================
// Terminal Cursor Options Start
// ============================================================================
// move cursor to home (top-left)
MOVE_CURSOR_HOME_CHAR :: "\x1b[H"

ENTER_ALT_SCREEN :: "\x1b[?1049h"
LEAVE_ALT_SCREEN :: "\x1b[?1049l" // lowercase L

HIDE_CURSOR_ON_SCREEN :: "\x1b[?25l"
SHOW_CURSOR_ON_SCREEN :: "\x1b[?25h"
// ============================================================================
// Terminal Cursor Options End
// ============================================================================

DEFAULT_SOUND :: #load("./default-sound-effects/perfect.mp3")
DEFAULT_SOUND_FILE :: "custom-audio-file.mp3"

CLOCK_CONTENT_WIDTH :: 54
CLOCK_CONTENT_HEIGHT :: 6

clear_screen :: proc() {
	os.write_string(os.stdout, CLEAR_SCREEN_CHAR + MOVE_CURSOR_HOME_CHAR)
}

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
	time:                   string `args:"pos=0" usage:"Time unit (s, sec, seconds, m, min, minutes, h, hr, hours)"`,
	overflow:               [dynamic]string,
}

DurationUnit :: enum {
	Seconds,
	Minutes,
	Hours,
}

parse_unit :: proc(s: string) -> (DurationUnit, bool) {
	switch strings.to_lower(s) {
	case "s", "sec", "second", "seconds":
		return DurationUnit.Seconds, true

	case "m", "min", "minute", "minutes":
		return DurationUnit.Minutes, true
	case "h", "hr", "hrs", "hour", "hours":
		return DurationUnit.Hours, true
	}

	return .Seconds, false
}

to_duration :: proc(value: f64, unit: DurationUnit) -> time.Duration {
	ns: f64
	switch unit {
	case DurationUnit.Seconds:
		ns = value * f64(time.Second)
	case DurationUnit.Minutes:
		ns = value * f64(time.Minute)
	case DurationUnit.Hours:
		ns = value * f64(time.Hour)
	}

	return time.Duration(ns)
}

parse_combined :: proc(duration_str: string) -> (f64, DurationUnit, bool) {
	split := 0
	for i := 0; i < len(duration_str); i += 1 {
		if duration_str[i] >= '0' && duration_str[i] <= '9' || duration_str[i] == '.' {
			split += 1
		} else {
			// we have started to hit the actual unit string (second, minute, or hour)
			break
		}
	}

	if split == 0 || split == len(duration_str) {
		return 0, DurationUnit.Seconds, false
	}

	value, val_ok := strconv.parse_f64(duration_str[:split])
	if !val_ok {return 0, DurationUnit.Seconds, false}

	unit, unit_ok := parse_unit(duration_str[split:])
	if !unit_ok {return 0, DurationUnit.Seconds, false}

	return value, unit, true
}

parse_duration :: proc(raw: string, overflow: []string) -> (time.Duration, bool) {
	if len(overflow) == 1 {

		value, val_ok := strconv.parse_f64(raw)
		if !val_ok do return 0, false

		unit, unit_ok := parse_unit(overflow[0])
		if !unit_ok do return 0, false

		return to_duration(value, unit), true
	}

	if len(overflow) == 0 {
		value, unit, ok := parse_combined(raw)

		if !ok do return 0, false
		return to_duration(value, unit), true
	}

	return 0, false
}

// ============================================================================
// Config Code Start
// ============================================================================
Config :: struct {
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


		// write default sound file to directory
		path, _ := filepath.join({config_dir_name, DEFAULT_SOUND_FILE})

		if !os.exists(path) {
			err := os.write_entire_file(path, DEFAULT_SOUND)
			if err != nil {
				fmt.printfln(
					"could not write the default sound file to the config directory with the following error: %v",
					err,
				)
			}
		}

		config.custom_audio_file_extension = ".mp3"

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

	// parse duration and handle errors
	parsed_duration, duration_is_ok := parse_duration(opts.time, opts.overflow[:])
	if !duration_is_ok {
		fmt.printfln(
			"the duration you entered is invalid.  please re-enter the time duration and try again",
		)
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

	custom_file_name := strings.join({"custom-audio-file", config.custom_audio_file_extension}, "")

	path, err := filepath.join({config_dir_name, custom_file_name})

	if err != nil {
		fmt.printfln("filepath could not be created with the following error")
	}

	cpath := strings.clone_to_cstring(path, context.temp_allocator)

	result = ma.sound_init_from_file(&engine, cpath, nil, nil, nil, &sound)
	if result != .SUCCESS {
		fmt.printfln(
			"The audio for the timer was not able to be initialized with the following error: %v",
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

	os.write_string(os.stdout, HIDE_CURSOR_ON_SCREEN)
	defer os.write_string(os.stdout, SHOW_CURSOR_ON_SCREEN)


	clear_screen()

	// timer start here
	// TODO: Update to use the parsed input from the cli params (10s, 10 seconds, 20m, 20min, 20 minutes, 10sec, 10, etc)

	start := time.now()
	last_second := -1
	timer_is_running := true
	timer_is_paused := true

	buf: [8]byte
	for {
		// handle keyboard motions: quit and pause
		n, _ := os.read(os.stdin, buf[:])
		if n > 0 {
			c := buf[0]
			if c == 'q' || c == 3 {
				ma.sound_stop(&sound)
				break
			}
		}

		elapsed := time.diff(start, time.now())
		remaining := parsed_duration - elapsed

		// handle egg timer completion + play sound
		if remaining <= 0 {
			ma.sound_set_looping(&sound, true)
			ma.sound_start(&sound)
			timer_is_running = false
		}

		total_seconds := int(time.duration_seconds(remaining))

		if total_seconds != last_second && timer_is_running {
			last_second = total_seconds

			hours := total_seconds / time.SECONDS_PER_HOUR
			minutes := (total_seconds % time.SECONDS_PER_HOUR) / 60
			seconds := total_seconds % time.SECONDS_PER_MINUTE

			d := [6]int {
				hours / 10,
				hours % 10,
				minutes / 10,
				minutes % 10,
				seconds / 10,
				seconds % 10,
			}

			term_width, term_height := get_terminal_size()

			start_col := (term_width - CLOCK_CONTENT_WIDTH) / 2
			start_row := (term_height - CLOCK_CONTENT_HEIGHT) / 2

			clear_screen()

			for line in 0 ..< 6 {
				fmt.printf("\x1b[%d;%dH", start_row + line, start_col)

				os.write_string(os.stdout, DIGITS[d[0]][line])
				os.write_string(os.stdout, DIGITS[d[1]][line])
				os.write_string(os.stdout, COLON[line])
				os.write_string(os.stdout, DIGITS[d[2]][line])
				os.write_string(os.stdout, DIGITS[d[3]][line])
				os.write_string(os.stdout, COLON[line])
				os.write_string(os.stdout, DIGITS[d[4]][line])
				os.write_string(os.stdout, DIGITS[d[5]][line])
			}
		}
	}
}
