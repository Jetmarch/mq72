package utils

Grid :: struct {
	cells:         []Cell,
	width, height: i32,
}

Cell :: struct {
	x, y: i32,
}

Grid_Error :: enum {
	None,
	Out_Of_Range,
	Grid_Not_Initialized,
}

grid_init :: proc(width: i32, height: i32) -> Grid {
	return Grid{width = width, height = height, cells = make([]Cell, width * height)}
}

grid_terminate :: proc(grid: ^Grid) {
	delete(grid.cells)
	grid.cells = nil
}

grid_cell_coord_to_index :: proc(x: i32, y: i32, width: i32) -> (index: i32) {
	return y * width + x
}

grid_get_cell :: proc(grid: ^Grid, x: i32, y: i32) -> (^Cell, Grid_Error) {
	if grid == nil {
		return nil, .Grid_Not_Initialized
	}

	if x < grid.width && x > 0 && y < grid.height && y > 0 {
		index := grid_cell_coord_to_index(x, y, grid.width)
		return &grid.cells[index], .None
	}

	return nil, .Out_Of_Range
}
