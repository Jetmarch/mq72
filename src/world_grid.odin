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
	cells: [MAX_MAP_WIDTH][MAX_MAP_HEIGHT]World_Cell,
	cell_size: i32,
	width: i32,
	height: i32,
	origin: Position
}

World_Cell :: struct {
	type: Grid_Cell_Type,
	entities: [MAX_ENTITIES_IN_CELL]ecs.entity_id,
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

world_grid_get_cell :: proc(grid: ^World_Grid, x: i32, y: i32) -> (^World_Cell, Grid_Error) {
	if grid == nil {
		return nil, .Grid_Not_Initialized
	}

	if x < MAX_MAP_WIDTH && x > 0 && y < MAX_MAP_HEIGHT && y > 0 {
		return &grid.cells[x][y], .None
	}

	return nil, .Out_Of_Range
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

world_grid_update_entities_position :: proc(grid: ^World_Grid, positions: ^ecs.Table(Position)) {
	pos_slice := ecs.slice(positions)

	pos: Position
	cell: ^World_Cell
	error: Grid_Error
	for i in 0..<len(pos_slice) {
		pos = pos_slice[i]
		cell, error = world_grid_get_cell(grid, pos.x, pos.y)
		if error != .None {
			report_error(fmt.aprintf("Position % is outside of thw world grid", pos))
			continue
		}
	}
}

@(test)
create_empty_grid_test :: proc(t: ^testing.T) {
    grid, err := world_grid_create()
    defer world_grid_delete(grid)

    testing.expect(t, grid != nil, "Something went wrong on grid memory allocation")
}
