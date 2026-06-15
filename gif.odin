package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:unicode/utf8"
import gd "gifdec"
import stb_resize "stb_resize"

DITHERING_THRESHOLD_OFFSET :: 20

Animation :: struct {
	width:       int,
	height:      int,
	frame_count: int,
	delays:      []u32,
	pixels:      [][]u8, // [frame][width * height] grayscale
}

apply_floyd_steinberg :: proc(pixels: []u8, w, h: int, threshold: u8) {
	fmt.printf("dither: len(pixels)=%d w=%d h=%d w*h=%d\n", len(pixels), w, h, w * h)
	assert(len(pixels) == w * h)
	// work in signed space to carry error
	buf := make([]f64, len(pixels))
	defer delete(buf)
	for i in 0 ..< len(pixels) do buf[i] = f64(pixels[i])

	size := w + h

	for y in 0 ..< h {
		for x in 0 ..< w {
			idx := y * w + x
			old := buf[idx]
			new := f64(255) if old >= f64(threshold) else 0

			buf[idx] = new
			err := old - new

			// distribute error to neighbors
			if x + 1 < w && idx + 1 < size do buf[idx + 1] += err * 7.0 / 16.0
			if y + 1 < h {
				if x > 0 && idx + w - 1 < size {
					buf[idx + w - 1] += err * 3.0 / 16.0
				}
				if idx + w < size {
					buf[idx + w] = err * 5.0 / 16.0
				}
				if x + 1 < w && idx + w + 1 < size {
					buf[idx + w + 1] += err * 1.0 / 16.0
				}
			}
		}
	}

	for i in 0 ..< len(pixels) do pixels[i] = u8(clamp(buf[i], 0, 255))
}

compute_otsu_threshold :: proc(pixels: []u8) -> u8 {
	hist: [256]int
	for p in pixels do hist[p] += 1

	total := len(pixels)
	sum: f64 = 0
	for i in 0 ..< 256 do sum += f64(i) * f64(hist[i])

	sum_bg: f64 = 0
	weight_bg := 0
	weight_fg := 0

	max_variance: f64 = 0
	best_threshold: u8 = 128

	for t in 0 ..< 256 {
		weight_bg += hist[t]
		if weight_bg == 0 do continue

		weight_fg = total - weight_bg
		if weight_fg == 0 do break

		sum_bg += f64(t) * f64(hist[t])
		mean_bg := sum_bg / f64(weight_bg)
		mean_fg := (sum - sum_bg) / f64(weight_fg)

		diff := mean_fg - mean_bg
		variance := f64(weight_bg) * f64(weight_fg) * diff * diff

		if variance > max_variance {
			max_variance = variance
			best_threshold = u8(t)
		}

	}

	return best_threshold
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

	resized := make([]u8, tw * th)
	defer delete(resized)

	stb_resize.resize_uint8_linear(
		raw_data(src),
		c.int(src_w),
		c.int(src_h),
		0,
		raw_data(resized),
		c.int(tw),
		c.int(th),
		0,
		1,
	)

	// choose threshold to calculate
	threshold := compute_otsu_threshold(resized) - DITHERING_THRESHOLD_OFFSET

	// dither using the adaptive threshold in order to provide correct contrast gradient (not flat)
	apply_floyd_steinberg(resized, tw, th, threshold)

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
				px := bx + dx
				py := by + dy

				if resized[py * tw + px] == 0 {
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
