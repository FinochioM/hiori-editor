package app

import "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

SPOTLIGHT_W :: 600
_MAX_VISIBLE :: 8

Spotlight_Mode :: enum {
	Command,
	Input,
}

Spotlight :: struct {
	open:      bool,
	mode:      Spotlight_Mode,
	input:     [256]u8,
	input_len: int,
	selected:  int,
	pending:   Command_Action,
	prompt:    cstring,
}

spotlight_open_command_list :: proc(s: ^Spotlight) {
	s^ = {}
	s.open = true
	s.mode = .Command
}

spotlight_open_input :: proc(s: ^Spotlight, action: Command_Action, prompt: cstring) {
	s^ = {}
	s.open = true
	s.mode = .Input
	s.pending = action
	s.prompt = prompt
}

spotlight_close :: proc(s: ^Spotlight) {
	s^ = {}
}

spotlight_type :: proc(s: ^Spotlight, bytes: []u8) {
	for b in bytes {
		if s.input_len < len(s.input) - 1 {
			s.input[s.input_len] = b
			s.input_len += 1
		}
	}
	if s.mode == .Command do s.selected = 0
}

spotlight_backspace :: proc(s: ^Spotlight) {
	if s.input_len > 0 do s.input_len -= 1
}

spotlight_move :: proc(s: ^Spotlight, delta: int) {
	if s.mode != .Command do return
	f := _filter(s)
	if f.count == 0 do return
	s.selected = (s.selected + delta + f.count) % f.count
}

// Returns index into commands_all() for the highlighted command.
spotlight_selected_command :: proc(s: ^Spotlight) -> (index: int, ok: bool) {
	if s.mode != .Command do return 0, false
	f := _filter(s)
	if f.count == 0 do return 0, false
	return f.indices[s.selected], true
}

spotlight_input_string :: proc(s: ^Spotlight) -> string {
	return string(s.input[:s.input_len])
}

@(private)
_Filtered :: struct {
	indices: [16]int,
	count:   int,
}

@(private)
_filter :: proc(s: ^Spotlight) -> _Filtered {
	result: _Filtered
	query := string(s.input[:s.input_len])
	for cmd, i in commands_all() {
		if _name_match(cmd.name, query) {
			if result.count < len(result.indices) {
				result.indices[result.count] = i
				result.count += 1
			}
		}
	}
	return result
}

@(private)
_name_match :: proc(name, query: string) -> bool {
	if len(query) == 0 do return true
	if len(query) > len(name) do return false
	outer: for i in 0 ..= len(name) - len(query) {
		for j in 0 ..< len(query) {
			nc := name[i + j]
			qc := query[j]
			if nc >= 'A' && nc <= 'Z' do nc += 32
			if qc >= 'A' && qc <= 'Z' do qc += 32
			if nc != qc do continue outer
		}
		return true
	}
	return false
}

spotlight_render :: proc(s: ^Spotlight, renderer: ^sdl2.Renderer, font: ^Font, line_skip: i32) {
	if !s.open do return

	win_w, win_h: i32
	sdl2.GetRendererOutputSize(renderer, &win_w, &win_h)

	bx := (win_w - SPOTLIGHT_W) / 2
	by := win_h / 5
	input_h := line_skip + 20

	switch s.mode {
	case .Command:
		f := _filter(s)
		n_vis := min(f.count, _MAX_VISIBLE)
		bh := input_h + i32(n_vis) * (line_skip + 2) + 4

		box := sdl2.Rect{bx, by, SPOTLIGHT_W, bh}
		sdl2.SetRenderDrawColor(renderer, 50, 50, 55, 255)
		sdl2.RenderFillRect(renderer, &box)
		sdl2.SetRenderDrawColor(renderer, 90, 90, 100, 255)
		sdl2.RenderDrawRect(renderer, &box)

		font_render(font, renderer, ">", bx + 10, by + 10, 120, 120, 130)
		s.input[s.input_len] = 0
		if s.input_len > 0 {
			font_render(font, renderer, cstring(&s.input[0]), bx + 26, by + 10, 204, 204, 204)
		}

		cmds := commands_all()
		for fi in 0 ..< n_vis {
			ci := f.indices[fi]
			cmd := cmds[ci]
			ry := by + input_h + i32(fi) * (line_skip + 2)

			if fi == s.selected {
				sel := sdl2.Rect{bx + 1, ry, SPOTLIGHT_W - 2, line_skip + 2}
				sdl2.SetRenderDrawColor(renderer, 70, 70, 80, 255)
				sdl2.RenderFillRect(renderer, &sel)
			}

			name_buf: [64]u8
			nn := min(len(cmd.name), len(name_buf) - 1)
			copy(name_buf[:nn], cmd.name[:nn])
			name_buf[nn] = 0
			font_render(font, renderer, cstring(&name_buf[0]), bx + 10, ry + 2, 204, 204, 204)

			sc_buf: [32]u8
			sn := min(len(cmd.shortcut), len(sc_buf) - 1)
			copy(sc_buf[:sn], cmd.shortcut[:sn])
			sc_buf[sn] = 0
			sw: i32
			ttf.SizeUTF8(font.inner, cstring(&sc_buf[0]), &sw, nil)
			font_render(
				font,
				renderer,
				cstring(&sc_buf[0]),
				bx + SPOTLIGHT_W - sw - 10,
				ry + 2,
				100,
				120,
				140,
			)
		}

	case .Input:
		box := sdl2.Rect{bx, by, SPOTLIGHT_W, input_h}
		sdl2.SetRenderDrawColor(renderer, 50, 50, 55, 255)
		sdl2.RenderFillRect(renderer, &box)
		sdl2.SetRenderDrawColor(renderer, 90, 90, 100, 255)
		sdl2.RenderDrawRect(renderer, &box)

		tx := bx + 10
		if s.prompt != nil {
			pw: i32
			ttf.SizeUTF8(font.inner, s.prompt, &pw, nil)
			font_render(font, renderer, s.prompt, tx, by + 10, 120, 120, 130)
			tx += pw + 8
		}
		s.input[s.input_len] = 0
		if s.input_len > 0 {
			font_render(font, renderer, cstring(&s.input[0]), tx, by + 10, 204, 204, 204)
		}
	}
}
