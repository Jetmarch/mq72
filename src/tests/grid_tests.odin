package tests

import "../utils"
import "core:testing"


@(test)
test_grid_init :: proc(t: ^testing.T) {
	grid: utils.Grid(utils.Cell)
	err: utils.Grid_Error

	err = utils.grid_init(&grid, 10, 10)
	defer utils.grid_terminate(&grid)

	testing.expect(t, err == nil, "Cannot initialize grid. Error message was not implemented yet")

	testing.expect(t, grid.cells != nil, "Grid was not initialized")
}
