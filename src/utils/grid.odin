package utils

import rl "vendor:raylib"

GRID_COLOR :: rl.Color{76, 63, 47, 125}

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
	Grid_Cell_Is_Zero_Sized,
}

grid_init :: proc(grid: ^Grid($T), width: i32, height: i32) -> Grid_Error {
	if size_of(T) == 0 {
		return .Grid_Cell_Is_Zero_Sized
	}

	grid.width = width
	grid.height = height
	grid.cells = make([]T, width * height)

	return nil
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
		return &grid.cells[index], nil
	}

	return nil, .Out_Of_Range
}

grid_render :: proc(grid: ^Grid($T), cell_size: i32) {
	// Render grid
	grid_width := grid.width
	grid_height := grid.height

	line_width := grid_width + (cell_size * grid_width)
	line_height := grid_height + (cell_size * grid_height)

	for i in 0 ..< grid_width {
		rl.DrawLine(0, i * cell_size, line_width, i * cell_size, GRID_COLOR)
	}

	for i in 0 ..< grid_height {
		rl.DrawLine(i * cell_size, 0, i * cell_size, line_height, GRID_COLOR)
	}

}
