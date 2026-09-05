package mq72

import "vendor:raylib"
MAX_SELECTED_UNITS :: 128

UNIT_SELECTION_COLOR :: raylib.Color{ 0, 158, 47, 55 }

//TODO: Move to utils
Rect :: struct {
	min_x, min_y, max_x, max_y: i32
}

get_abs_rect_size :: proc(rect: ^Rect) -> (x, y, width, height: i32) {

	max_x := max(rect.max_x, rect.min_x)
	min_x := min(rect.max_x, rect.min_x)

	max_y := max(rect.max_y, rect.min_y)
	min_y := min(rect.max_y, rect.min_y)

	return min_x, min_y, max_x - min_x, max_y - min_y
}

//A selection rectangle
Unit_Selection :: struct {
	rect: Rect,
	is_active: bool
}


unit_select_start :: proc(selection: ^Unit_Selection) {
	// For now it's hardcoded to use raylib functions
	selection.is_active = true
	selection.rect.min_x = raylib.GetMouseX()
	selection.rect.min_y = raylib.GetMouseY()
}

unit_select_update :: proc(selection: ^Unit_Selection) {
	if !selection.is_active  { return }

	selection.rect.max_x = raylib.GetMouseX()
	selection.rect.max_y = raylib.GetMouseY()
}

unit_select_end :: proc(selection: ^Unit_Selection) {
	selection.is_active = false
}

unit_select_render :: proc(selection: ^Unit_Selection) {

	if !selection.is_active { return }

	x, y, width, height := get_abs_rect_size(&selection.rect)
	raylib.DrawRectangle(x, y, width, height, UNIT_SELECTION_COLOR)
}

unit_select_handle_input :: proc(selection: ^Unit_Selection) {
	if raylib.IsMouseButtonPressed(.LEFT) {
		unit_select_start(selection)
	}

	if raylib.IsMouseButtonDown(.LEFT) {
		unit_select_update(selection)
	}

	if raylib.IsMouseButtonReleased(.LEFT) {
		unit_select_end(selection)
	}
}

unit_select_mark_selected_units :: proc(selection: ^Unit_Selection, ecs_world: ^Ecs_World) {
	if !selection.is_active { return }

}
