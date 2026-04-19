package app

import "core:fmt"
import "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

run :: proc() {
	if sdl2.Init(sdl2.INIT_VIDEO) != 0 {
		fmt.eprintln("SDL2 init failed:", sdl2.GetError())
		return
	}
	defer sdl2.Quit()

	if ttf.Init() != 0 {
		fmt.eprintln("TTF init failed:", ttf.GetError())
		return
	}
	defer ttf.Quit()

	window := sdl2.CreateWindow(
		"Hiori",
		sdl2.WINDOWPOS_CENTERED,
		sdl2.WINDOWPOS_CENTERED,
		1280,
		720,
		sdl2.WINDOW_RESIZABLE,
	)
	if window == nil {
		fmt.eprintln("Window creation failed:", sdl2.GetError())
		return
	}
	defer sdl2.DestroyWindow(window)

	renderer := sdl2.CreateRenderer(window, -1, sdl2.RENDERER_ACCELERATED)
	if renderer == nil {
		fmt.eprintln("Renderer creation failed:", sdl2.GetError())
		return
	}
	defer sdl2.DestroyRenderer(renderer)

	font, font_ok := font_load(
		"/home/fmatttt/Desarrollos/HioriEditor/assets/JetBrainsMono-Regular.ttf",
		16,
	)
	if !font_ok do return
	defer font_destroy(&font)

	buf := buffer_make()
	defer buffer_destroy(&buf)

	line_skip := ttf.FontLineSkip(font.inner)

	running := true
	for running {
		ev: sdl2.Event
		for sdl2.PollEvent(&ev) {
			#partial switch ev.type {
			case .QUIT:
				running = false
			case .TEXTINPUT:
				text := ev.text.text
				n := 0
				for n < len(text) && text[n] != 0 {
					n += 1
				}
				buffer_insert_bytes(&buf, text[:n])
			case .KEYDOWN:
				#partial switch ev.key.keysym.sym {
				case .ESCAPE:
					running = false
				case .BACKSPACE:
					buffer_delete_before(&buf)
				case .DELETE:
					buffer_delete_after(&buf)
				case .RETURN:
					buffer_insert_byte(&buf, '\n')
				case .LEFT:
					cur := buffer_cursor(&buf)
					if cur > 0 do buffer_move_cursor(&buf, cur - 1)
				case .RIGHT:
					cur := buffer_cursor(&buf)
					buffer_move_cursor(&buf, cur + 1)
				}
			}
		}

		sdl2.SetRenderDrawColor(renderer, 30, 30, 30, 255)
		sdl2.RenderClear(renderer)

		_render_buffer(renderer, &font, &buf, line_skip)

		sdl2.RenderPresent(renderer)
		sdl2.Delay(16)
	}
}

@(private)
_cursor_screen_pos :: proc(font: ^Font, buf: ^Buffer, line_skip: i32) -> (cx, cy: i32) {
	cursor := buffer_cursor(buf)
	line: [4096]u8
	ln: int
	cx = 8
	cy = 8

	for i := 0; i < cursor; i += 1 {
		ch := buffer_byte_at(buf, i)
		if ch == '\n' {
			cy += line_skip
			ln = 0
		} else if ln < len(line) - 1 {
			line[ln] = ch
			ln += 1
		}
	}

	if ln > 0 {
		line[ln] = 0
		w: i32
		ttf.SizeUTF8(font.inner, cstring(&line[0]), &w, nil)
		cx = 8 + w
	}

	return
}

@(private)
_render_buffer :: proc(renderer: ^sdl2.Renderer, font: ^Font, buf: ^Buffer, line_skip: i32) {
	line: [4096]u8
	ln: int
	x: i32 = 8
	y: i32 = 8
	blen := buffer_len(buf)

	for i := 0; i <= blen; i += 1 {
		ch: u8 = 0 if i == blen else buffer_byte_at(buf, i)

		if ch == '\n' || i == blen {
			if ln > 0 {
				line[ln] = 0
				font_render(font, renderer, cstring(&line[0]), x, y, 204, 204, 204)
			}
			y += line_skip
			ln = 0
		} else if ln < len(line) - 1 {
			line[ln] = ch
			ln += 1
		}
	}

	cx, cy := _cursor_screen_pos(font, buf, line_skip)
	cursor_rect := sdl2.Rect{cx, cy, 2, line_skip}
	sdl2.SetRenderDrawColor(renderer, 204, 204, 204, 255)
	sdl2.RenderFillRect(renderer, &cursor_rect)
}
