package main

import "core:fmt"
import "core:strings"
import "core:testing"
import "core:unicode/utf8"

count_dot_bits :: proc(v: u32) -> int {
	n := 0
	x := v
	for x > 0 {
		n += int(x & 1)
		x >>= 1
	}
	return n
}

measure_render :: proc(s: string, rows, cols: int) -> (ink_fraction: f64, border_fraction: f64) {
	lines := strings.split(s, "\n")
	defer delete(lines)

	ink_bits, total_bits := 0, 0
	border_ink_bits, border_total_bits := 0, 0
	for line, row in lines {
		if row >= rows do continue

		col := 0
		i := 0
		for i < len(line) {
			ru, size := utf8.decode_rune_in_string(line[i:])
			i += size

			if ru < 0x2800 || ru > 0x28FF do continue

			is_border := row == 0 || row == rows - 1 || col == 0 || col == cols - 1
			bits := count_dot_bits(u32(ru) - 0x2800)

			total_bits += 8
			ink_bits += bits
			if is_border {
				border_total_bits += 8
				border_ink_bits += bits
			}

			col += 1
		}
	}

	return f64(ink_bits) / f64(total_bits), f64(border_ink_bits) / f64(border_total_bits)
}

gif_render_case :: proc(t: ^testing.T, path: string) {
	cpath := strings.clone_to_cstring(path)
	defer delete(cpath)

	anim, ok := load_gif(cpath)
	if !testing.expectf(t, ok, "failed to load %s", path) {
		return
	}
	defer destroy_animation(&anim)

	// emulate the terminal fit in main: max 88 cols x 26 rows, braille cell 2x4
	src_aspect := f64(anim.height) / f64(anim.width)
	cols := 88
	rows := int(f64(cols) * src_aspect * 0.5)
	if rows > 26 {
		rows = 26
		cols = int(f64(rows) / src_aspect / 0.5)
	}

	frame := anim.frame_count / 2

	s := grayscale_to_braille(anim.pixels[frame], anim.width, anim.height, cols, rows, anim.invert)
	defer delete(s)

	ink, border := measure_render(s, rows, cols)
	fmt.printfln(
		"%s: anim_invert=%v frames=%d grid=%dx%d ink=%.1f%% border_ink=%.1f%%",
		path,
		anim.invert,
		anim.frame_count,
		cols,
		rows,
		ink * 100,
		border * 100,
	)

	// the render must keep the animation visible but the background blank
	testing.expectf(t, ink > 0.02, "%s: render came out blank", path)
	testing.expectf(t, ink < 0.90, "%s: render came out solid", path)
	testing.expectf(t, border < 0.50, "%s: border is inked; background polarity is wrong", path)
}

@test gif_contrast_render_test :: proc(t: ^testing.T) {
	gif_render_case(t, "./assets/zangief-yes-gif.gif")
	gif_render_case(t, "./assets/heman-hey.gif")
}
