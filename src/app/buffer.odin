package app

import "core:mem"

BUFFER_GAP_MIN :: 64
BUFFER_MAX_HISTORY :: 2000

Edit_Kind :: enum {
	Insert,
	Delete_Before,
	Delete_After,
}

Edit :: struct {
	kind:  Edit_Kind,
	pos:   int,
	bytes: [dynamic]u8,
}

Buffer :: struct {
	data:         []u8,
	gap_start:    int,
	gap_end:      int,
	allocator:    mem.Allocator,
	history:      [dynamic]Edit,
	history_head: int,
	recording:    bool,
}

buffer_make :: proc(allocator := context.allocator) -> Buffer {
	data := make([]u8, BUFFER_GAP_MIN, allocator)
	return Buffer {
		data = data,
		gap_start = 0,
		gap_end = BUFFER_GAP_MIN,
		allocator = allocator,
		history = make([dynamic]Edit, allocator),
		recording = true,
	}
}

buffer_destroy :: proc(b: ^Buffer) {
	_history_clear(b)
	delete(b.history)
	delete(b.data, b.allocator)
	b^ = {}
}

buffer_clear :: proc(b: ^Buffer) {
	b.gap_start = 0
	b.gap_end = len(b.data)
	_history_clear(b)
	b.history_head = 0
}

buffer_len :: proc(b: ^Buffer) -> int {
	return len(b.data) - (b.gap_end - b.gap_start)
}

buffer_cursor :: proc(b: ^Buffer) -> int {
	return b.gap_start
}

buffer_byte_at :: proc(b: ^Buffer, i: int) -> u8 {
	if i < b.gap_start do return b.data[i]
	return b.data[i + (b.gap_end - b.gap_start)]
}

buffer_insert_byte :: proc(b: ^Buffer, ch: u8) {
	if b.recording {
		pos := b.gap_start
		if b.history_head > 0 {
			prev := &b.history[b.history_head - 1]
			if prev.kind == .Insert && prev.pos + len(prev.bytes) == pos {
				append(&prev.bytes, ch)
				_raw_insert_byte(b, ch)
				return
			}
		}
		_history_push(b, Edit_Kind.Insert, pos, {ch})
	}
	_raw_insert_byte(b, ch)
}

buffer_insert_bytes :: proc(b: ^Buffer, bytes: []u8) {
	if len(bytes) == 0 do return
	if b.recording {
		pos := b.gap_start
		if b.history_head > 0 {
			prev := &b.history[b.history_head - 1]
			if prev.kind == .Insert && prev.pos + len(prev.bytes) == pos {
				append(&prev.bytes, ..bytes)
				_raw_insert_bytes(b, bytes)
				return
			}
		}
		_history_push(b, Edit_Kind.Insert, pos, bytes)
	}
	_raw_insert_bytes(b, bytes)
}

buffer_delete_before :: proc(b: ^Buffer) {
	if b.gap_start == 0 do return
	ch := b.data[b.gap_start - 1]
	if b.recording {
		pos := b.gap_start - 1
		if b.history_head > 0 {
			prev := &b.history[b.history_head - 1]
			if prev.kind == .Delete_Before && prev.pos == pos + 1 {
				prev.pos = pos
				inject_at(&prev.bytes, 0, ch)
				_raw_delete_before(b)
				return
			}
		}
		_history_push(b, Edit_Kind.Delete_Before, pos, {ch})
	}
	_raw_delete_before(b)
}

buffer_delete_after :: proc(b: ^Buffer) {
	if b.gap_end >= len(b.data) do return
	ch := b.data[b.gap_end]
	if b.recording {
		pos := b.gap_start
		if b.history_head > 0 {
			prev := &b.history[b.history_head - 1]
			if prev.kind == .Delete_After && prev.pos == pos {
				append(&prev.bytes, ch)
				_raw_delete_after(b)
				return
			}
		}
		_history_push(b, Edit_Kind.Delete_After, pos, {ch})
	}
	_raw_delete_after(b)
}

buffer_undo :: proc(b: ^Buffer) {
	if b.history_head == 0 do return
	b.history_head -= 1
	e := &b.history[b.history_head]
	b.recording = false
	switch e.kind {
	case .Insert:
		buffer_move_cursor(b, e.pos)
		for _ in e.bytes do _raw_delete_after(b)
	case .Delete_Before:
		buffer_move_cursor(b, e.pos)
		_raw_insert_bytes(b, e.bytes[:])
	case .Delete_After:
		buffer_move_cursor(b, e.pos)
		_raw_insert_bytes(b, e.bytes[:])
	}
	b.recording = true
}

buffer_redo :: proc(b: ^Buffer) {
	if b.history_head >= len(b.history) do return
	e := &b.history[b.history_head]
	b.recording = false
	switch e.kind {
	case .Insert:
		buffer_move_cursor(b, e.pos)
		_raw_insert_bytes(b, e.bytes[:])
	case .Delete_Before:
		buffer_move_cursor(b, e.pos)
		for _ in e.bytes do _raw_delete_before(b)
	case .Delete_After:
		buffer_move_cursor(b, e.pos)
		for _ in e.bytes do _raw_delete_after(b)
	}
	b.recording = true
	b.history_head += 1
}

buffer_move_cursor :: proc(b: ^Buffer, pos: int) {
	clamped := clamp(pos, 0, buffer_len(b))
	_buffer_move_gap(b, clamped)
}

buffer_cursor_col :: proc(b: ^Buffer) -> int {
	cursor := buffer_cursor(b)
	col := 0
	for i := cursor - 1; i >= 0; i -= 1 {
		if buffer_byte_at(b, i) == '\n' do break
		col += 1
	}
	return col
}

buffer_move_up :: proc(b: ^Buffer) {
	col := buffer_cursor_col(b)
	cursor := buffer_cursor(b)

	i := cursor - 1
	for i >= 0 && buffer_byte_at(b, i) != '\n' {
		i -= 1
	}
	if i < 0 do return

	prev_end := i
	i -= 1
	for i >= 0 && buffer_byte_at(b, i) != '\n' {
		i -= 1
	}
	prev_start := i + 1
	prev_len := prev_end - prev_start
	buffer_move_cursor(b, prev_start + min(col, prev_len))
}

buffer_move_down :: proc(b: ^Buffer) {
	col := buffer_cursor_col(b)
	cursor := buffer_cursor(b)
	blen := buffer_len(b)

	i := cursor
	for i < blen && buffer_byte_at(b, i) != '\n' {
		i += 1
	}
	if i >= blen do return

	next_start := i + 1
	j := next_start
	for j < blen && buffer_byte_at(b, j) != '\n' {
		j += 1
	}
	next_len := j - next_start
	buffer_move_cursor(b, next_start + min(col, next_len))
}

buffer_move_line_start :: proc(b: ^Buffer) {
	i := buffer_cursor(b) - 1
	for i >= 0 && buffer_byte_at(b, i) != '\n' {
		i -= 1
	}
	buffer_move_cursor(b, i + 1)
}

buffer_move_line_end :: proc(b: ^Buffer) {
	blen := buffer_len(b)
	i := buffer_cursor(b)
	for i < blen && buffer_byte_at(b, i) != '\n' {
		i += 1
	}
	buffer_move_cursor(b, i)
}

@(private)
_raw_insert_byte :: proc(b: ^Buffer, ch: u8) {
	_buffer_ensure_gap(b, 1)
	b.data[b.gap_start] = ch
	b.gap_start += 1
}

@(private)
_raw_insert_bytes :: proc(b: ^Buffer, bytes: []u8) {
	if len(bytes) == 0 do return
	_buffer_ensure_gap(b, len(bytes))
	copy(b.data[b.gap_start:], bytes)
	b.gap_start += len(bytes)
}

@(private)
_raw_delete_before :: proc(b: ^Buffer) {
	if b.gap_start == 0 do return
	b.gap_start -= 1
}

@(private)
_raw_delete_after :: proc(b: ^Buffer) {
	if b.gap_end >= len(b.data) do return
	b.gap_end += 1
}

@(private)
_history_push :: proc(b: ^Buffer, kind: Edit_Kind, pos: int, bytes: []u8) {
	for i := b.history_head; i < len(b.history); i += 1 {
		delete(b.history[i].bytes)
	}
	resize(&b.history, b.history_head)

	if len(b.history) >= BUFFER_MAX_HISTORY {
		delete(b.history[0].bytes)
		copy(b.history[:], b.history[1:])
		resize(&b.history, len(b.history) - 1)
		b.history_head -= 1
	}

	e := Edit {
		kind = kind,
		pos  = pos,
	}
	e.bytes = make([dynamic]u8, b.allocator)
	append(&e.bytes, ..bytes)
	append(&b.history, e)
	b.history_head += 1
}

@(private)
_history_clear :: proc(b: ^Buffer) {
	for i in 0 ..< len(b.history) {
		delete(b.history[i].bytes)
	}
	clear(&b.history)
}

@(private)
_buffer_move_gap :: proc(b: ^Buffer, pos: int) {
	if pos == b.gap_start do return
	gap_size := b.gap_end - b.gap_start

	if pos < b.gap_start {
		n := b.gap_start - pos
		copy(b.data[b.gap_end - n:b.gap_end], b.data[pos:b.gap_start])
		b.gap_start = pos
		b.gap_end = pos + gap_size
	} else {
		n := pos - b.gap_start
		copy(b.data[b.gap_start:b.gap_start + n], b.data[b.gap_end:b.gap_end + n])
		b.gap_start = pos
		b.gap_end = pos + gap_size
	}
}

@(private)
_buffer_ensure_gap :: proc(b: ^Buffer, needed: int) {
	if (b.gap_end - b.gap_start) >= needed do return

	old_len := len(b.data)
	new_len := max(old_len * 2, old_len + needed + BUFFER_GAP_MIN)
	new_data := make([]u8, new_len, b.allocator)
	after_len := old_len - b.gap_end
	new_gap_end := new_len - after_len

	copy(new_data[:b.gap_start], b.data[:b.gap_start])
	copy(new_data[new_gap_end:], b.data[b.gap_end:])

	delete(b.data, b.allocator)
	b.data = new_data
	b.gap_end = new_gap_end
}
