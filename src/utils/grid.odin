package utils

Grid :: struct($T: typeid) {
	cells:         []T,
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

grid_init :: proc(grid: ^Grid($T), width: i32, height: i32) -> bool {
	if size_of(T) == 0 {return false}


	return Grid($T){width = width, height = height, cells = make([]T, width * height)}
}

grid_terminate :: proc(grid: ^Grid($T)) {
	delete(grid.cells)
	grid.cells = nil
}

grid_cell_coord_to_index :: proc(x: i32, y: i32, width: i32) -> (index: i32) {
	return y * width + x
}

grid_get_cell :: proc(grid: ^Grid($T), x: i32, y: i32) -> (^T, Grid_Error) {
	if grid == nil {
		return nil, .Grid_Not_Initialized
	}

	if x < grid.width && x > 0 && y < grid.height && y > 0 {
		index := grid_cell_coord_to_index(x, y, grid.width)
		return &grid.cells[index], .None
	}

	return nil, .Out_Of_Range
}
