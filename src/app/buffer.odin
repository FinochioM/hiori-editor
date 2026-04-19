package app

import "core:mem"

BUFFER_GAP_MIN :: 64

Buffer :: struct {
	data:      []u8,
	gap_start: int,
	gap_end:   int,
	allocator: mem.Allocator,
}

buffer_make :: proc(allocator := context.allocator) -> Buffer {
	data := make([]u8, BUFFER_GAP_MIN, allocator)
	return Buffer{data = data, gap_start = 0, gap_end = BUFFER_GAP_MIN, allocator = allocator}
}

buffer_destroy :: proc(b: ^Buffer) {
	delete(b.data, b.allocator)
	b^ = {}
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
	_buffer_ensure_gap(b, 1)
	b.data[b.gap_start] = ch
	b.gap_start += 1
}

buffer_insert_bytes :: proc(b: ^Buffer, bytes: []u8) {
	if len(bytes) == 0 do return
	_buffer_ensure_gap(b, len(bytes))
	copy(b.data[b.gap_start:], bytes)
	b.gap_start += len(bytes)
}

buffer_delete_before :: proc(b: ^Buffer) {
	if b.gap_start == 0 do return
	b.gap_start -= 1
}

buffer_delete_after :: proc(b: ^Buffer) {
	if b.gap_end >= len(b.data) do return
	b.gap_end += 1
}

buffer_move_cursor :: proc(b: ^Buffer, pos: int) {
	clamped := clamp(pos, 0, buffer_len(b))
	_buffer_move_gap(b, clamped)
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
