package mq72

import "core:fmt"
import rl "vendor:raylib"
import "core:testing"
import ecs "../vendor/ode_ecs/src"

MAX_ENTITIES_IN_CELL :: 4
MAX_MAP_WIDTH :: 256
MAX_MAP_HEIGHT :: 256
WORLD_CELL_SIZE :: 16


GRID_COLOR :: rl.Color{ 76, 63, 47, 125 }

World_Grid :: struct {
	cells: [MAX_MAP_WIDTH * MAX_MAP_HEIGHT]World_Cell,
	cell_size: i32,
	width: i32,
	height: i32,
	origin: Position,
}

World_Cell :: struct {
	type: Grid_Cell_Type,
	entities: [MAX_ENTITIES_IN_CELL]ecs.entity_id,
	entities_count: u8,
}

Grid_Cell_Type :: enum {
	Empty = 0,
	Building,
}

Grid_Error :: enum {
	None,
	Out_Of_Range,
	Grid_Not_Initialized
}


world_grid_create :: proc(width: i32 = MAX_MAP_WIDTH,
	height: i32 = MAX_MAP_HEIGHT,
	cell_size: i32 = WORLD_CELL_SIZE,
	allocator := context.allocator) -> (^World_Grid, bool) {

		grid, err := new(World_Grid, allocator)
		if err != nil {
			return nil, false
		}

		grid.cell_size = cell_size
		grid.width = width
		grid.height = height
		grid.origin = Position { 0, 0, 0 }

		return grid, true
}

world_grid_cell_coord_to_index :: proc(x: i32, y:i32, width: i32) -> (index: i32) {
	return y * width + x
}

world_grid_get_cell :: proc(grid: ^World_Grid, x: i32, y: i32) -> (^World_Cell, Grid_Error) {
	if grid == nil {
		return nil, .Grid_Not_Initialized
	}

	if x < MAX_MAP_WIDTH && x > 0 && y < MAX_MAP_HEIGHT && y > 0 {
		index := world_grid_cell_coord_to_index(x, y, grid.width)
		return &grid.cells[index], .None
	}

	return nil, .Out_Of_Range
}

///
// TODO: Debug and fix incorrect cells selection
world_grid_get_cells_in_rect :: proc(grid: ^World_Grid, rect: ^Rect) -> ([dynamic]World_Cell) {
	x, y, width, height := get_abs_rect_size(rect)
	rect_selection := make([dynamic]World_Cell)


	selected_cell: ^World_Cell
	err: Grid_Error
	for i := x; i < width; i += grid.cell_size {
		for j := y; j < height; j += grid.cell_size {
			selected_cell, err = world_grid_get_cell_by_world_pos(grid, x, y)
			if err != .None {
				continue
			}

			append(&rect_selection, selected_cell^)
		}
	}

	return rect_selection
}

world_grid_get_cell_by_world_pos :: proc(grid: ^World_Grid, x: i32, y: i32) -> (^World_Cell, Grid_Error) {
	return world_grid_get_cell(grid, x / grid.cell_size, y / grid.cell_size)
}

world_grid_delete :: proc(grid: ^World_Grid) {
	free(grid)
}

world_grid_render_grid :: proc(grid: ^World_Grid) {
	// Render grid
	cell_size := grid.cell_size
	grid_origin := grid.origin
	grid_width := grid.width
	grid_height := grid.height

	line_width := grid_width + (cell_size * grid_width)
	line_height := grid_height + (cell_size * grid_height)

	for i in 0..<grid_width {
		rl.DrawLine(0, i * cell_size,
			line_width, i * cell_size, GRID_COLOR)
	}

	for i in 0..<grid_height {
		rl.DrawLine(i * cell_size, 0,
			i * cell_size, line_height, GRID_COLOR)
	}
}

world_grid_update_entities_position :: proc(grid: ^World_Grid,
	positions_table: ^ecs.Table(Position),
	grid_positions_table: ^ecs.Table(Grid_Position),
	view: ^ecs.View) {

	eids := ecs.entities_slice(view)
	positions := ecs.slice(positions_table)
	grid_positions := ecs.slice(grid_positions_table)

	pos: Position
	cell: ^World_Cell
	error: Grid_Error
	for i in 0..<len(eids) {
		pos = positions[i]
		cell, error = world_grid_get_cell_by_world_pos(grid, pos.x, pos.y)
		if error != .None {
			report_error(fmt.aprintf("Position % is outside of thw world grid", pos))
			continue
		}

		grid_positions[i].x = i32(pos.x / grid.cell_size)
		grid_positions[i].y = i32(pos.y / grid.cell_size)
	}
}

@(test)
create_empty_grid_test :: proc(t: ^testing.T) {
    grid, err := world_grid_create()
    defer world_grid_delete(grid)

    testing.expect(t, grid != nil, "Something went wrong on grid memory allocation")
}
