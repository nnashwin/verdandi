package main

import "core:os"
import "core:unicode/utf8"
import gd "gifdec"

Animation :: struct {
	width:       int,
	height:      int,
	frame_count: int,
	delays:      []u32,
	pixels:      [][]u8, // [frame][width * height] grayscale
}

load_gif_from_bytes :: proc(data: []u8) -> (anim: Animation, ok: bool) {
	tmp_path :: "/tmp/_embedded_gif.gif"

	err := os.write_entire_file(tmp_path, data)
	if err != nil {
		return Animation{}, false
	}

	defer os.remove(tmp_path)

	return load_gif(tmp_path)
}


load_gif :: proc(path: cstring) -> (anim: Animation, ok: bool) {
	gif := gd.gd_open_gif(path)
	if gif == nil do return {}, false

	defer gd.gd_close_gif(gif)

	w := int(gif.width)
	h := int(gif.height)
	rgb_size := w * h * 3

	// Temp buffer for RGB data from gifdec
	rgb_buf := make([]u8, rgb_size)
	defer delete(rgb_buf)

	delays: [dynamic]u32
	frames: [dynamic][]u8

	for gd.gd_get_frame(gif) == 1 {
		// read rgb
		gd.gd_render_frame(gif, raw_data(rgb_buf))

		// convert rgb to grayscale
		gray := make([]u8, w * h)
		for i in 0 ..< w * h {
			r := u16(rgb_buf[i * 3 + 0])
			g := u16(rgb_buf[i * 3 + 1])
			b := u16(rgb_buf[i * 3 + 2])
			// standard luminance weights
			gray[i] = u8((r * 299 + g * 587 + b * 114))
		}

		append(&frames, gray)

		// gifs use centiseconds, store in milliseconds for our braille conversion
		delay := u32(gif.gce.delay) * 10
		if delay == 0 do delay = 100
		append(&delays, delay)
	}

	anim.width = w
	anim.height = h
	anim.frame_count = len(frames)
	anim.delays = delays[:]
	anim.pixels = frames[:]

	return anim, true
}

grayscale_to_braille :: proc(
	src: []u8,
	src_w, src_h: int,
	target_cols, target_rows: int,
	threshold: u8,
) -> string {
	tw := target_cols * 2
	th := target_rows * 4

	buf := make([dynamic]u8, 0, target_cols * target_rows * 4 + target_rows)

	OFFSETS :: [8][3]int {
		{0, 0, 0x01},
		{0, 1, 0x02},
		{0, 2, 0x04},
		{1, 0, 0x08},
		{1, 1, 0x10},
		{1, 2, 0x20},
		{0, 3, 0x40},
		{1, 3, 0x80},
	}

	for row in 0 ..< target_rows {
		for col in 0 ..< target_cols {
			dots: u32 = 0x2800
			bx := col * 2
			by := row * 4

			for off in OFFSETS {
				dx, dy, bit := off[0], off[1], off[2]
				tx := bx + dx
				ty := by + dy

				// Source region this single dot covers
				sx0 := tx * src_w / tw
				sx1 := (tx + 1) * src_w / tw
				sy0 := ty * src_h / th
				sy1 := (ty + 1) * src_h / th
				if sx1 <= sx0 do sx1 = sx0 + 1
				if sy1 <= sy0 do sy1 = sy0 + 1

				sum := 0
				count := 0
				for yy in sy0 ..< sy1 {
					for xx in sx0 ..< sx1 {
						if xx < src_w && yy < src_h {
							sum += int(src[yy * src_w + xx])
							count += 1
						}
					}
				}

				avg := u8(sum / max(count, 1))
				if avg < threshold {
					dots |= u32(bit)
				}
			}

			b, w := utf8.encode_rune(rune(dots))
			append(&buf, ..b[:w])
		}
		append(&buf, '\n')
	}

	return string(buf[:])
}

destroy_animation :: proc(anim: ^Animation) {
	for f in anim.pixels do delete(f)
	delete(anim.pixels)
	delete(anim.delays)
}
