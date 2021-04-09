package ui

import "core:log"

import "core:fmt"
import "../render"

label :: proc(ctx: ^UI_Context, str: string, color: Color = {1, 1, 1, 1}, location := #caller_location, additional_location_index: i32 = 0) -> (state: Element_State)
{
	layout := current_layout(ctx);
	line_height := ctx.current_font.line_height;
	lines := render.split_text_for_render(ctx.current_font, str, int(layout.size.x));
	allocated_length := layout.size.x;
	if len(lines) == 1
	{
		allocated_length = f32(render.get_text_render_size(ctx.current_font, str));
	}
	allocated_space := allocate_element_space(ctx, [2]f32{allocated_length, f32(len(lines)) * line_height});
	first_line_pos := allocated_space.pos + [2]f32{0, line_height};
	for line, index in lines
	{
		text(line, color, first_line_pos + [2]f32{0, f32(line_height) * f32(index)}, ctx.current_font, ctx);
	}
	return state;
}


drag_int :: proc(ctx: ^UI_Context, value: ^int, location := #caller_location, additional_location_index: i32 = 0)
{
	parent_layout := current_layout(ctx)^;
	widget_rect := allocate_element_space(ctx, {0, f32(ctx.editor_config.line_height)});
	state := ui_element(ctx, widget_rect, {.Hover, .Drag}, location, 0);
	text_color := render.Color{1, 1, 1, 1};
	if Interaction_Type.Drag in state
	{
		value^ += int(ctx.input_state.delta_drag.x);
	}
	if Interaction_Type.Hover in state 
	{
		text_color.r = 0;
		element_draw_rect(default_anchor, {}, render.Color{1, 1, 0, 1}, ctx);
	}
	new_layout := Layout {
		pos = widget_rect.pos, size = widget_rect.size,
		direction = {1, 0}
	};
	push_layout_group(ctx);
	add_layout_to_group(ctx, new_layout);
	label(ctx, "drag editor ", text_color, location, additional_location_index + 1);
	label(ctx, fmt.tprint(value^), text_color, location, additional_location_index + 2);
	pop_layout_group(ctx);
}