package imgui

import "core:hash"
import "core:mem"
import "core:strings"
import "core:math/linalg"
import "core:math"
import "core:log"
import "core:os"
import "../util"
import "../input"

import stb_tt"vendor:stb/truetype"

gen_uid :: proc(location := #caller_location, additional_index: int = 0) -> UID {
    to_hash := make([]byte, len(transmute([]byte)location.file_path) + size_of(i32) * 2)
	mem.copy(&to_hash[0], strings.ptr_from_string(location.file_path), len(location.file_path))
	location_line := location.line
	mem.copy(&to_hash[len(location.file_path)], &location_line, size_of(i32))
	additional_index_cpy := additional_index
	mem.copy(&to_hash[len(location.file_path) + size_of(i32)], &additional_index_cpy, size_of(i32))
    return UID(hash.djb2(to_hash))
}

Button_Theme :: struct {
	default_theme: Rect_Theme,
	hovered_theme: Rect_Theme,
	clicked_theme: Rect_Theme,
}

themed_rect :: proc(using ui_state: ^UI_State, rect: I_Rect, theme: ^Rect_Theme, block_hover: bool = false)
{
	if block_hover && util.is_in_rect(rect, linalg.to_i32(input_state.mouse_pos)) {
		next_hovered = 0
	}
	add_rect_command(&ui_state.command_list, Rect_Command {
		pos = rect.pos,
		size = rect.size,
		theme = theme^,
		clip_index = clip_stack[len(clip_stack) - 1],
	})
}

button :: proc(using ui_state: ^UI_State, rect: I_Rect, theme: ^Button_Theme, uid: UID) -> (out_state: Button_State) {
	displayed_theme := &theme.default_theme
	out_state = input.Key_State_Up

	mouse_pos := linalg.to_i32(input_state.mouse_pos)
    if util.is_in_rect(rect, mouse_pos) && util.is_in_rect(get_clip(ui_state), mouse_pos) {
		next_hovered = uid
		out_state = input.Key_State_Up
		if hovered_element == uid {
			displayed_theme = &theme.hovered_theme
		 	if input.get_mouse_state(ui_state.input_state, 0) == input.Key_State_Pressed {
				dragged_element = uid
				out_state = input.Key_State_Pressed
			}
		}
	}
	if dragged_element == uid {
		if out_state != input.Key_State_Pressed {
			out_state = input.Key_State_Down
			if input.get_mouse_state(ui_state.input_state, 0) == input.Key_State_Released {
				out_state = input.Key_State_Released
				dragged_element = 0
			}
		}
		displayed_theme = &theme.clicked_theme
	}
	themed_rect(ui_state, rect, displayed_theme)
	return
}

Slider_Theme :: struct {
	background_theme: Rect_Theme,
	cursor_theme: Button_Theme,
	cursor_height: i32,
}

slider :: proc(using ui_state: ^UI_State, rect: I_Rect, value: ^$T, min: T, max: T, theme: ^Slider_Theme, uid: UID) -> bool {
	themed_rect(ui_state, rect, &theme.background_theme, true)
	cursor_rect := rect
	cursor_rect.size.y = theme.cursor_height

	available_height := rect.size.y - theme.cursor_height

	display_value := value^
	dragged_data := cast(^Default_Dragged_Data(T))dragged_element_data
	value_changed := false
	
	if dragged_element == uid {
		mouse_delta := linalg.to_i32(input_state.mouse_pos) - dragged_data.drag_start_pos
		delta_value := T(mouse_delta.y) * (max - min) / T(available_height)
		
		display_value = math.clamp(dragged_data.drag_start_value - delta_value, math.min(min, max), math.max(min, max))
		if value^ != display_value do value_changed = true
		value^ = display_value
	}
	cursor_rect.pos.y += i32(f32(available_height) * (1 - f32((display_value - min)) / f32((max - min))))
	switch button(ui_state, cursor_rect, &theme.cursor_theme, uid) {
		case input.Key_State_Pressed:
			new_dragged_data := new(Default_Dragged_Data(T))
			new_dragged_data.drag_start_pos = linalg.to_i32(input_state.mouse_pos)
			new_dragged_data.drag_start_value = value^
			dragged_element_data = new_dragged_data
		case input.Key_State_Released:
			free(dragged_data)
			dragged_element_data = nil
	}
	return value_changed
}

scrollbar :: proc(
	using ui_state: ^UI_State,
	bar_rect: I_Rect,
	content_size: i32,
	display_size: i32,
	scroll_pos: ^i32,
	theme: ^Slider_Theme,
	uid: UID,
) {
	slider_theme: Slider_Theme = theme^
	slider_theme.cursor_height = bar_rect.size.y * display_size / content_size 
	slider(ui_state, bar_rect, scroll_pos, content_size - display_size, 0, &slider_theme, uid)
}

Scrollzone_Theme :: struct {
	slider_theme: ^Slider_Theme,
	background_theme: ^Rect_Theme,
	bar_thickness: i32,
}

scrollzone_start :: proc (
	using ui_state: ^UI_State,
	rect: I_Rect,
	content_size: i32,
	scroll_pos: ^i32,
	theme: ^Scrollzone_Theme,
	uid: UID,
) -> (out_content_rect: I_Rect) {
	bar_rect := rect
	bar_rect.pos.x = bar_rect.pos.x + bar_rect.size.x - theme.bar_thickness
	bar_rect.size.x = theme.bar_thickness
	scrollbar(ui_state, bar_rect, content_size, rect.size.y, scroll_pos, theme.slider_theme, uid)
	background_rect := rect
	background_rect.size.x -= theme.bar_thickness
	themed_rect(ui_state, background_rect, theme.background_theme)
	rest_rect_theme: Rect_Theme = {
		color = 0x883333ff,
	}
	test_rect : I_Rect = {
		pos = rect.pos - [2]i32{0, scroll_pos^},
		size = [2]i32{rect.size.x - theme.bar_thickness, content_size}
	}
	push_clip(ui_state, rect)
	themed_rect(ui_state, test_rect, &rest_rect_theme)
	out_content_rect = test_rect
	return out_content_rect
}

scrollzone_end :: proc(using ui_state: ^UI_State) {
	pop_clip(ui_state)
}

Text_Theme :: struct {
	size: f32,
	color: u32,
}

Window_Theme :: struct {
	scrollzone_theme: ^Scrollzone_Theme,
	header_thickness: i32,
	header_theme: ^Button_Theme,
	title_theme: ^Text_Theme,
}

window_start :: proc (
	using ui_state: ^UI_State,
	rect: ^I_Rect,
	content_size: i32,
	scroll_pos: ^i32,
	theme: ^Window_Theme,
	uid: UID,
) -> (out_content_rect: I_Rect) {
	title_text := "popup window title"
	header_rect, scrollzone_rect := util.rect_vsplit(rect^, theme.header_thickness)
	header_uid := gen_uid() ~ uid
	dragged_data := cast(^Default_Dragged_Data([2]i32))dragged_element_data
	if dragged_element == header_uid {
		mouse_delta := linalg.to_i32(input_state.mouse_pos) - dragged_data.drag_start_pos
		
		rect.pos = dragged_data.drag_start_value + mouse_delta
	}
	switch button(ui_state, header_rect, theme.header_theme, header_uid) {
		case input.Key_State_Pressed:
			new_dragged_data := new(Default_Dragged_Data([2]i32))
			new_dragged_data.drag_start_pos = linalg.to_i32(input_state.mouse_pos)
			new_dragged_data.drag_start_value = rect.pos
			dragged_element_data = new_dragged_data
		case input.Key_State_Released:
			free(dragged_data)
			dragged_element_data = nil
	}

	default_font := &ui_state.fonts["default"]
	text_pos := linalg.to_f32(header_rect.pos + [2]i32{10, header_rect.size.y - 10})
	text_rect := compute_text_rect(default_font, title_text, linalg.to_i32(text_pos), 20)
	rect_theme := Rect_Theme{color = 0x999999ff}
	themed_rect(ui_state, text_rect, &rect_theme)
    draw_text(ui_state, title_text, text_pos, &ui_state.fonts["default"], 20)

	return scrollzone_start(ui_state, scrollzone_rect, content_size, scroll_pos, theme.scrollzone_theme, gen_uid() ~ uid)
}

window_end :: proc(using ui_state: ^UI_State) {
	pop_clip(ui_state)
}

init_ui_state :: proc(using ui_state: ^UI_State, viewport: I_Rect) {
	init_renderer(&render_system)
	reset_draw_list(&command_list, viewport)
	append(&clip_stack, 0)

	fontinfo: stb_tt.fontinfo
	fontdata, fontdata_ok := os.read_entire_file("resources/fonts/Roboto-Regular.ttf", context.temp_allocator)
	stb_tt.InitFont(&fontinfo, &fontdata[0], 0)
	fonts["default"] = pack_font_characters(&fontinfo, " abcdefhijklmnopqrstuvwxyzABCDEFHIJKLMNOPQRSTUVWXYZ0123456789+-*/.,;:!?&()[]{}", font_atlas_size)

}

render_frame :: proc(using ui_state: ^UI_State, viewport: I_Rect) {
	render_draw_commands(&render_system, &command_list, viewport)
	reset_draw_list(&command_list, viewport)
	clear(&clip_stack)
	append(&clip_stack, 0)
	hovered_element = next_hovered
	next_hovered = 0
	switch input.get_mouse_state(ui_state.input_state, 0)
	{
		case input.Key_State_Released:
			dragged_element = 0
	}
	mouse_pos := linalg.to_i32(input_state.mouse_pos)
}

push_clip :: proc(using ui_state: ^UI_State, clip: I_Rect) {
	append(&command_list.clips, clip)
	clip_index := i32(len(command_list.clips) - 1)
	append(&clip_stack, clip_index)
}

pop_clip :: proc(using ui_state: ^UI_State) {
	pop(&clip_stack)
}

get_clip :: proc (using ui_state: ^UI_State) -> I_Rect {
	return command_list.clips[clip_stack[len(clip_stack) - 1]]
}

compute_text_size :: proc(font: ^Packed_Font, text: string, scale: f32) -> [2]i32{
	glyph_cursor := [2]f32{0, 0}
	display_scale := scale / f32(font.render_height)
	
	for character in text {
        glyph := font.glyph_data[character]
        
        glyph_cursor.x += f32(glyph.advance) * font.render_scale * display_scale
    }
	return [2]i32{ i32(glyph_cursor.x) + 1, i32(f32(font.ascent + font.descent) * font.render_scale * display_scale) }
}

compute_text_rect :: proc(font: ^Packed_Font, text: string, render_pos: [2]i32, scale: f32) -> I_Rect {
	glyph_cursor := [2]f32{0, 0}
	display_scale := scale / f32(font.render_height)
	
	for character in text {
        glyph := font.glyph_data[character]
        
        glyph_cursor.x += f32(glyph.advance) * font.render_scale * display_scale
    }
	size := [2]i32{ i32(glyph_cursor.x) + 1, i32(f32(font.ascent - font.descent) * font.render_scale * display_scale) }
	pos := render_pos + [2]i32{0, -i32(f32(font.ascent) * font.render_scale * display_scale) }
	return I_Rect{pos, size}
}

draw_text :: proc(using ui_state: ^UI_State, text: string, pos: [2]f32, font: ^Packed_Font, scale: f32) {
	glyph_cursor := pos
	atlas_size := font.atlas_texture.size
	for character in text {
        glyph := font.glyph_data[character]
		display_scale := scale / f32(font.render_height)
        add_glyph_command(&ui_state.command_list, Glyph_Command {
            pos = glyph_cursor + linalg.to_f32(glyph.offset) * display_scale,
            size = linalg.to_f32(glyph.rect.size) * display_scale,
            uv_pos = linalg.to_f32(glyph.rect.pos) / linalg.to_f32(atlas_size),
            uv_size = linalg.to_f32(glyph.rect.size) / linalg.to_f32(atlas_size),
            color = 0xffffffff,
            threshold = f32(180)/f32(255),
            texture_id = font.atlas_texture.bindless_id,
            clip_index = 0,
        })
        glyph_cursor.x += f32(glyph.advance) * font.render_scale * display_scale
    }
}
