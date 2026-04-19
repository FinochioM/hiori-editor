package app

import "core:os"
import "core:strings"

Command_Action :: enum {
	Open_File,
	Save_File,
}

Command :: struct {
	name:     string,
	shortcut: string,
	action:   Command_Action,
}

@(private)
_commands := [?]Command {
	{name = "Open File", shortcut = "Ctrl+O", action = .Open_File},
	{name = "Save File", shortcut = "Ctrl+S", action = .Save_File},
}

commands_all :: proc() -> []Command {
	return _commands[:]
}

command_try_execute :: proc(
	action: Command_Action,
	buf: ^Buffer,
	current_file: ^string,
	modified: ^bool,
) -> bool {
	switch action {
	case .Save_File:
		if current_file^ != "" {
			_file_save(buf, current_file^)
			modified^ = false
			return true
		}
	case .Open_File:
	// ask for path everytime
	}
	return false
}

command_execute_with_input :: proc(
	action: Command_Action,
	input: string,
	buf: ^Buffer,
	current_file: ^string,
	modified: ^bool,
) {
	path := strings.trim_space(input)
	if path == "" do return

	switch action {
	case .Open_File:
		if data, ok := os.read_entire_file(path); ok {
			buffer_clear(buf)
			buffer_insert_bytes(buf, data)
			buffer_move_cursor(buf, 0)
			delete(data)
			if current_file^ != "" do delete(current_file^)
			current_file^ = strings.clone(path)
			modified^ = false
		}
	case .Save_File:
		_file_save(buf, path)
		if current_file^ != "" do delete(current_file^)
		current_file^ = strings.clone(path)
		modified^ = false
	}
}

@(private)
_file_save :: proc(buf: ^Buffer, path: string) {
	blen := buffer_len(buf)
	data := make([]u8, blen)
	defer delete(data)
	for i in 0 ..< blen {
		data[i] = buffer_byte_at(buf, i)
	}
	tmp := strings.concatenate({path, ".tmp"})
	defer delete(tmp)
	if os.write_entire_file(tmp, data) {
		os.rename(tmp, path)
	}
}
