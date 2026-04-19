package app

import "core:fmt"
import "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

Font :: struct {
	inner: ^ttf.Font,
}

font_load :: proc(path: cstring, size: i32) -> (Font, bool) {
	f := ttf.OpenFont(path, size)
	if f == nil {
		fmt.eprintln("Failed to load font: ", ttf.GetError())
		return {}, false
	}

	return Font{inner = f}, true
}

font_destroy :: proc(f: ^Font) {
	if f.inner != nil {
		ttf.CloseFont(f.inner)
		f.inner = nil
	}
}

font_render :: proc(f: ^Font, renderer: ^sdl2.Renderer, text: cstring, x, y: i32, r, g, b: u8) {
	color := sdl2.Color{r, g, b, 255}
	surface := ttf.RenderUTF8_Blended(f.inner, text, color)
	if surface == nil do return
	defer sdl2.FreeSurface(surface)

	texture := sdl2.CreateTextureFromSurface(renderer, surface)
	if texture == nil do return
	defer sdl2.DestroyTexture(texture)

	dst := sdl2.Rect{x, y, surface.w, surface.h}
	sdl2.RenderCopy(renderer, texture, nil, &dst)
}
