package mq72

import "core:fmt"
import "vendor:raylib"
import ecs "../vendor/ode_ecs/src"
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

unit_select_deselect_all :: proc(ecs_world: ^Ecs_World) {

	selected_units_dense := ecs.slice(&ecs_world.is_unit_selected)
	for i in 0..<len(selected_units_dense) {
		ecs.remove_tag(&ecs_world.is_unit_selected, selected_units_dense[i])
	}
}

unit_select_mark_selected_units :: proc(selection: ^Unit_Selection, ecs_world: ^Ecs_World, grid: ^World_Grid) {
	if !selection.is_active { return }

	unit_select_deselect_all(ecs_world)

	//Get all collided with selection rect world cells
	selected_world_cells := world_grid_get_cells_in_rect(grid, &selection.rect)
	defer delete(selected_world_cells)

	cell: ^World_Cell
	eid: ecs.entity_id
	err: ecs.Error
	for i in 0..<len(selected_world_cells) {
		cell = &selected_world_cells[i]

		for j in 0..=cell.entities_count {
			eid = cell.entities[j]

			if ecs.is_entity_expired(&ecs_world.units_db, eid) { continue }

			err = ecs.add_tag(&ecs_world.is_unit_selected, eid)
			if err != nil {
				report_error(fmt.aprint("Error while add 'Selected' tag to unit %", eid))
			}
		}
	}
}
