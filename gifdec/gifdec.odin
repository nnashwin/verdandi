package gifdec

import "core:c"

GD_GCE :: struct #packed {
	delay:        c.uint16_t,
	tindex:       c.uint8_t,
	disposal:     c.uint8_t,
	input:        c.int,
	transparency: c.int,
}

// Mirror the gd_GIF struct — we only need the fields we access
GD_GIF :: struct {
	fd:         c.int,
	anim_start: c.long, // off_t
	width:      c.uint16_t,
	height:     c.uint16_t,
	depth:      c.uint16_t,
	loop_count: c.uint16_t,
	gce:        GD_GCE,
	palette:    ^[256][3]c.uint8_t,
	lct:        [256][3]c.uint8_t,
	gct:        [256][3]c.uint8_t,
	canvas:     [^]c.uint8_t,
	frame:      [^]c.uint8_t,
}

when ODIN_OS == .Windows {
	foreign import lib "../vendor/gifdec/gifdec.lib"
} else {
	foreign import lib "../vendor/gifdec/libgifdec.a"
}


foreign lib {
	gd_open_gif :: proc(path: cstring) -> ^GD_GIF ---
	gd_get_frame :: proc(gif: ^GD_GIF) -> c.int ---
	gd_render_frame :: proc(gif: ^GD_GIF, buffer: [^]c.uint8_t) ---
	gd_rewind :: proc(gif: ^GD_GIF) ---
	gd_close_gif :: proc(gif: ^GD_GIF) ---
}
