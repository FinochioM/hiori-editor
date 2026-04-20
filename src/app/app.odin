package app

import "core:fmt"
import "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

@(private)
GUTTER_WIDTH :: 48
@(private)
STATUS_BAR_H :: 24

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

	spotlight: Spotlight
	current_file: string
	modified: bool
	find: Find
	scroll_y: i32

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
				if spotlight.open {
					spotlight_type(&spotlight, text[:n])
				} else if find.active {
					find_type(&find, text[:n])
					find_search(&find, &buf)
					find_jump_first(&find, &buf)
				} else {
					buffer_insert_bytes(&buf, text[:n])
					modified = true
				}
			case .KEYDOWN:
				ctrl := ev.key.keysym.mod & sdl2.KMOD_CTRL != {}
				shift := ev.key.keysym.mod & sdl2.KMOD_SHIFT != {}
				#partial switch ev.key.keysym.sym {
				case .ESCAPE:
					if spotlight.open {
						spotlight_close(&spotlight)
					} else if find.active {
						find_close(&find)
					} else {
						running = false
					}
				case .p:
					if ctrl && shift {
						spotlight_open_command_list(&spotlight)
					}
				case .o:
					if ctrl {
						spotlight_open_input(&spotlight, .Open_File, "Open file:")
					}
				case .s:
					if ctrl && !spotlight.open {
						if current_file != "" {
							_file_save_direct(&buf, current_file)
							modified = false
						} else {
							spotlight_open_input(&spotlight, .Save_File, "Save as:")
						}
					}
				case .z:
					if ctrl && !spotlight.open {
						buffer_undo(&buf)
						modified = true
					}
				case .y:
					if ctrl && !spotlight.open {
						buffer_redo(&buf)
						modified = true
					}
				case .f:
					if ctrl && !spotlight.open {
						if find.active {
							find_close(&find)
						} else {
							find_open(&find)
						}
					}
				case .g:
					if ctrl && !spotlight.open {
						spotlight_open_input(&spotlight, .Goto_Line, "Go to Line: ")
					}
				case .BACKSPACE:
					if spotlight.open {
						spotlight_backspace(&spotlight)
					} else if find.active {
						find_backspace(&find)
						find_search(&find, &buf)
						find_jump_first(&find, &buf)
					} else {
						buffer_delete_before(&buf)
						modified = true
					}
				case .DELETE:
					if !spotlight.open {
						buffer_delete_after(&buf)
						modified = true
					}
				case .RETURN:
					if spotlight.open {
						switch spotlight.mode {
						case .Command:
							if ci, ok := spotlight_selected_command(&spotlight); ok {
								action := commands_all()[ci].action
								if command_try_execute(action, &buf, &current_file, &modified) {
									spotlight_close(&spotlight)
								} else {
									prompt: cstring
									switch action {
									case .Open_File:
										prompt = "Open file:"
									case .Save_File:
										prompt = "Save as:"
									case .Goto_Line:
										prompt = "Go to line:"
									}
									spotlight_open_input(&spotlight, action, prompt)
								}
							}
						case .Input:
							command_execute_with_input(
								spotlight.pending,
								spotlight_input_string(&spotlight),
								&buf,
								&current_file,
								&modified,
							)
							spotlight_close(&spotlight)
						}
					} else if find.active {
						if shift {
							find_prev(&find, &buf)
						} else {
							find_next(&find, &buf)
						}
					} else {
						buffer_insert_byte(&buf, '\n')
						modified = true
					}
				case .UP:
					if spotlight.open {
						spotlight_move(&spotlight, -1)
					} else {
						buffer_move_up(&buf)
					}
				case .DOWN:
					if spotlight.open {
						spotlight_move(&spotlight, 1)
					} else {
						buffer_move_down(&buf)
					}
				case .LEFT:
					if !spotlight.open {
						cur := buffer_cursor(&buf)
						if cur > 0 do buffer_move_cursor(&buf, cur - 1)
					}
				case .RIGHT:
					if !spotlight.open {
						cur := buffer_cursor(&buf)
						buffer_move_cursor(&buf, cur + 1)
					}
				case .HOME:
					if !spotlight.open {
						if ctrl {
							buffer_move_cursor(&buf, 0)
						} else {
							buffer_move_line_start(&buf)
						}
					}
				case .END:
					if !spotlight.open {
						if ctrl {
							buffer_move_cursor(&buf, buffer_len(&buf))
						} else {
							buffer_move_line_end(&buf)
						}
					}
				}
			}
		}

		{
			_, cy_doc := _cursor_screen_pos(&font, &buf, line_skip)
			win_w, win_h: i32
			sdl2.GetRendererOutputSize(renderer, &win_w, &win_h)
			extra := i32(FIND_BAR_H) if find.active else 0
			viewport_h := win_h - STATUS_BAR_H - extra
			if cy_doc < scroll_y {
				scroll_y = cy_doc
			}
			if cy_doc + line_skip > scroll_y + viewport_h {
				scroll_y = cy_doc + line_skip - viewport_h
			}
		}

		sdl2.SetRenderDrawColor(renderer, 30, 30, 30, 255)
		sdl2.RenderClear(renderer)

		extra_bottom := i32(FIND_BAR_H) if find.active else 0
		_render_buffer(renderer, &font, &buf, line_skip, scroll_y, extra_bottom, sdl2.GetTicks())
		_render_status_bar(renderer, &font, current_file, modified, line_skip)
		find_render(&find, renderer, &font, line_skip)
		spotlight_render(&spotlight, renderer, &font, line_skip)

		sdl2.RenderPresent(renderer)
		sdl2.Delay(16)
	}
}

@(private)
_cursor_screen_pos :: proc(font: ^Font, buf: ^Buffer, line_skip: i32) -> (cx, cy: i32) {
	cursor := buffer_cursor(buf)
	line: [4096]u8
	ln: int
	cx = GUTTER_WIDTH
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
		cx = GUTTER_WIDTH + w
	}

	return
}

@(private)
_render_status_bar :: proc(
	renderer: ^sdl2.Renderer,
	font: ^Font,
	current_file: string,
	modified: bool,
	line_skip: i32,
) {
	win_w, win_h: i32
	sdl2.GetRendererOutputSize(renderer, &win_w, &win_h)

	bar := sdl2.Rect{0, win_h - STATUS_BAR_H, win_w, STATUS_BAR_H}
	sdl2.SetRenderDrawColor(renderer, 40, 40, 45, 255)
	sdl2.RenderFillRect(renderer, &bar)

	ty := win_h - STATUS_BAR_H + (STATUS_BAR_H - line_skip) / 2

	if current_file == "" {
		font_render(font, renderer, "untitled", 8, ty, 120, 120, 130)
	} else {
		name_buf: [512]u8
		n := min(len(current_file), len(name_buf) - 1)
		copy(name_buf[:n], current_file[:n])
		name_buf[n] = 0
		font_render(font, renderer, cstring(&name_buf[0]), 8, ty, 180, 180, 190)
	}

	if modified {
		font_render(font, renderer, "[+]", win_w - 40, ty, 180, 140, 80)
	}
}

_file_save_direct :: proc(buf: ^Buffer, path: string) {
	_file_save(buf, path)
}

@(private)
_render_buffer :: proc(
	renderer: ^sdl2.Renderer,
	font: ^Font,
	buf: ^Buffer,
	line_skip: i32,
	scroll_y: i32,
	extra_bottom: i32,
	ticks: u32,
) {
	line: [4096]u8
	num_buf: [16]u8
	ln: int
	line_num: int = 1
	x: i32 = GUTTER_WIDTH
	y: i32 = 8 - scroll_y
	blen := buffer_len(buf)

	win_w, win_h: i32
	sdl2.GetRendererOutputSize(renderer, &win_w, &win_h)
	viewport_h := win_h - STATUS_BAR_H - extra_bottom

	_render_line_number :: proc(
		renderer: ^sdl2.Renderer,
		font: ^Font,
		num_buf: []u8,
		n: int,
		y: i32,
		line_skip: i32,
		viewport_h: i32,
	) {
		if y + line_skip < 0 || y >= viewport_h do return
		s := fmt.bprintf(num_buf, "%d", n)
		num_buf[len(s)] = 0
		w: i32
		ttf.SizeUTF8(font.inner, cstring(&num_buf[0]), &w, nil)
		font_render(font, renderer, cstring(&num_buf[0]), GUTTER_WIDTH - w - 6, y, 80, 80, 80)
	}

	cx, cy_doc := _cursor_screen_pos(font, buf, line_skip)
	cy := cy_doc - scroll_y

	if cy >= 0 && cy < viewport_h {
		highlight := sdl2.Rect{0, cy, win_w, line_skip}
		sdl2.SetRenderDrawColor(renderer, 45, 45, 50, 255)
		sdl2.RenderFillRect(renderer, &highlight)
	}

	_render_line_number(renderer, font, num_buf[:], line_num, y, line_skip, viewport_h)

	for i := 0; i <= blen; i += 1 {
		ch: u8 = 0 if i == blen else buffer_byte_at(buf, i)

		if ch == '\n' || i == blen {
			if ln > 0 && y + line_skip >= 0 && y < viewport_h {
				line[ln] = 0
				font_render(font, renderer, cstring(&line[0]), x, y, 204, 204, 204)
			}
			y += line_skip
			ln = 0
			line_num += 1
			if i < blen {
				_render_line_number(renderer, font, num_buf[:], line_num, y, line_skip, viewport_h)
			}
			if y >= viewport_h do break
		} else if ln < len(line) - 1 {
			line[ln] = ch
			ln += 1
		}
	}

	if (ticks / 530) % 2 == 0 && cy >= 0 && cy < viewport_h {
		cursor_rect := sdl2.Rect{cx, cy, 2, line_skip}
		sdl2.SetRenderDrawColor(renderer, 204, 204, 204, 255)
		sdl2.RenderFillRect(renderer, &cursor_rect)
	}
}
