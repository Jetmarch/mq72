package mq72

import "core:log"
import "core:testing"

MAX_MAP_WIDTH :: 256
MAX_MAP_HEIGHT :: 256
WORLD_CELL_SIZE :: 16

World_Grid :: struct {
	cells: [MAX_MAP_WIDTH][MAX_MAP_HEIGHT]World_Cell,
	cell_size: i32
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


create_grid :: proc(width: i32 = MAX_MAP_WIDTH,
	height: i32 = MAX_MAP_HEIGHT,
	cell_size: i32 = WORLD_CELL_SIZE,
	allocator := context.allocator) -> (^World_Grid, bool) {

		grid, err := new(World_Grid, allocator)

		if err == nil {
			return grid, true
		}

		return nil, false
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

delete_grid :: proc(grid: ^World_Grid) {
	free(grid)
}

@(test)
create_empty_grid_test :: proc(t: ^testing.T) {
    grid, err := create_grid()
    defer delete_grid(grid)

    testing.expect(t, grid != nil, "Something went wrong on grid memory allocation")
}
