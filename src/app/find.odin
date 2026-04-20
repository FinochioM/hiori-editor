package app

import "core:fmt"
import "vendor:sdl2"

FIND_BAR_H :: 28
FIND_MAX :: 1024

Find :: struct {
	active:  bool,
	query:   [256]u8,
	qlen:    int,
	matches: [FIND_MAX]int,
	count:   int,
	current: int,
}

find_open :: proc(f: ^Find) {
	f^ = {}
	f.active = true
}

find_close :: proc(f: ^Find) {
	f^ = {}
}

find_type :: proc(f: ^Find, bytes: []u8) {
	for b in bytes {
		if f.qlen < len(f.query) - 1 {
			f.query[f.qlen] = b
			f.qlen += 1
		}
	}
}

find_backspace :: proc(f: ^Find) {
	if f.qlen > 0 do f.qlen -= 1
}

find_search :: proc(f: ^Find, buf: ^Buffer) {
	f.count = 0
	f.current = 0
	if f.qlen == 0 do return

	blen := buffer_len(buf)
	qlen := f.qlen

	for i := 0; i <= blen - qlen; i += 1 {
		match := true
		for j := 0; j < qlen; j += 1 {
			if buffer_byte_at(buf, i + j) != f.query[j] {
				match = false
				break
			}
		}
		if match {
			if f.count < FIND_MAX {
				f.matches[f.count] = i
				f.count += 1
			}
		}
	}
}

find_next :: proc(f: ^Find, buf: ^Buffer) {
	if f.count == 0 do return
	f.current = (f.current + 1) % f.count
	buffer_move_cursor(buf, f.matches[f.current])
}

find_prev :: proc(f: ^Find, buf: ^Buffer) {
	if f.count == 0 do return
	f.current = (f.current - 1 + f.count) % f.count
	buffer_move_cursor(buf, f.matches[f.current])
}

find_jump_first :: proc(f: ^Find, buf: ^Buffer) {
	if f.count == 0 do return
	cursor := buffer_cursor(buf)
	for i in 0 ..< f.count {
		if f.matches[i] >= cursor {
			f.current = i
			buffer_move_cursor(buf, f.matches[i])
			return
		}
	}

	f.current = 0
	buffer_move_cursor(buf, f.matches[0])
}

find_render :: proc(f: ^Find, renderer: ^sdl2.Renderer, font: ^Font, line_skip: i32) {
	if !f.active do return

	win_w, win_h: i32
	sdl2.GetRendererOutputSize(renderer, &win_w, &win_h)

	by := win_h - STATUS_BAR_H - FIND_BAR_H

	bar := sdl2.Rect{0, by, win_w, FIND_BAR_H}
	sdl2.SetRenderDrawColor(renderer, 38, 38, 44, 255)
	sdl2.RenderFillRect(renderer, &bar)
	sdl2.SetRenderDrawColor(renderer, 80, 80, 95, 255)
	sdl2.RenderDrawLine(renderer, 0, by, win_w, by)

	ty := by + (FIND_BAR_H - line_skip) / 2

	font_render(font, renderer, "Find:", 8, ty, 100, 120, 140)

	f.query[f.qlen] = 0
	if f.qlen > 0 {
		font_render(font, renderer, cstring(&f.query[0]), 56, ty, 204, 204, 204)
	}

	if f.qlen > 0 {
		count_buf: [32]u8
		s := count_buf[:]
		if f.count == 0 {
			s[0] = '0'; s[1] = 0
			font_render(font, renderer, cstring(&s[0]), win_w - 60, ty, 160, 80, 80)
		} else {
			text := fmt.bprintf(s, "%d / %d", f.current + 1, f.count)
			s[len(text)] = 0
			font_render(font, renderer, cstring(&s[0]), win_w - 80, ty, 100, 160, 100)
		}
	}
}
