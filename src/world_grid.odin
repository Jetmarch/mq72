package mq72

import rl "vendor:raylib"
import "core:testing"

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
	type: Grid_Cell_Type
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


create_world_grid :: proc(width: i32 = MAX_MAP_WIDTH,
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

grid_get_cell :: proc(grid: ^World_Grid, x: i32, y: i32) -> (^World_Cell, Grid_Error) {
	if grid == nil {
		return nil, .Grid_Not_Initialized
	}

	if x < MAX_MAP_WIDTH && x > 0 && y < MAX_MAP_HEIGHT && y > 0 {
		return &grid.cells[x][y], .None
	}

	return nil, .Out_Of_Range
}

delete_world_grid :: proc(grid: ^World_Grid) {
	free(grid)
}

render_grid :: proc(grid: ^World_Grid) {
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

@(test)
create_empty_grid_test :: proc(t: ^testing.T) {
    grid, err := create_world_grid()
    defer delete_world_grid(grid)

    testing.expect(t, grid != nil, "Something went wrong on grid memory allocation")
}
