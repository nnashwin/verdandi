package stb_resize

import "core:c"

foreign import lib "../vendor/stb_image_resize2/libstb_resize.a"

Filter :: enum c.int {
	DEFAULT    = 0,
	BOX        = 1,
	TRIANGLE   = 2,
	CUBICBSP   = 3,
	CATMULLROM = 4,
	MITCHELL   = 5,
}

foreign lib {
	@(link_name = "stbir_resize_uint8_linear")
	resize_uint8_linear :: proc(input_pixels: [^]u8, input_w, input_h, input_stride: c.int, output_pixels: [^]u8, output_w, output_h, output_stride: c.int, num_channels: c.int) -> [^]u8 ---
}
