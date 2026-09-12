package mq72

import ecs "../vendor/ode_ecs/src"
import "core:fmt"
import "core:testing"
import "utils"

MAX_ENTITIES_IN_CELL :: 4
MAX_MAP_WIDTH :: 256
MAX_MAP_HEIGHT :: 256
// At this point we don't care about memory usage
// TODO: Calculate amount of cells that can fits in viewport
MAX_CELL_IN_SELECTION_RECT :: 100
WORLD_CELL_SIZE :: 4


World_Grid :: struct {
	grid:      utils.Grid(World_Cell),
	cell_size: i32,
	origin:    utils.Vector2,
}

World_Cell :: struct {
	x, y:           i32,
	type:           Grid_Cell_Type,
	entities:       [MAX_ENTITIES_IN_CELL]ecs.entity_id,
	entities_count: u8,
}

Grid_Cell_Type :: enum {
	None = 0,
	Empty,
	Building,
}

world_grid_create :: proc(
	world: ^World_Grid,
	width: i32 = MAX_MAP_WIDTH,
	height: i32 = MAX_MAP_HEIGHT,
	cell_size: i32 = WORLD_CELL_SIZE,
	allocator := context.allocator,
) -> (
	ok: bool,
) {

	world.cell_size = cell_size
	world.origin = utils.Vector2{0, 0}

	err := utils.grid_init(&world.grid, width, height)
	if err != nil {
		return false
	}

	index: i32
	for x: i32 = 0; x < width; x += 1 {
		for y: i32 = 0; y < height; y += 1 {
			index = utils.grid_cell_coord_to_index(x, y, width)
			world.grid.cells[index].x = x
			world.grid.cells[index].y = y

		}
	}

	return true
}

///
world_grid_get_cells_in_rect :: proc(
	grid: ^World_Grid,
	rect: ^Rect,
) -> (
	rect_selection: [MAX_CELL_IN_SELECTION_RECT]World_Cell,
) {
	x, y, width, height := get_abs_rect_size(rect)

	selected_cell: ^World_Cell
	ok: bool
	next_cell_index: i32 = 0
	for i := x; i < x + width; i += grid.cell_size {
		for j := y; j < y + height; j += grid.cell_size {
			selected_cell, ok = world_grid_get_cell_by_world_pos(grid, i, j)
			if !ok {
				continue
			}

			rect_selection[next_cell_index] = selected_cell^
			next_cell_index += 1
		}
	}

	return rect_selection
}

world_grid_get_cell_by_world_pos :: proc(
	grid: ^World_Grid,
	x: i32,
	y: i32,
) -> (
	cell: ^World_Cell,
	ok: bool,
) {
	err: utils.Grid_Error
	cell, err = utils.grid_get_cell(&grid.grid, x / grid.cell_size, y / grid.cell_size)

	if err != nil {
		return nil, false
	}

	return cell, true
}

world_grid_delete :: proc(world_grid: ^World_Grid) {
	utils.grid_terminate(&world_grid.grid)
}

world_grid_render_grid :: proc(grid: ^World_Grid) {
	utils.grid_render(&grid.grid, grid.cell_size)
}

world_grid_update_entities_position :: proc(
	grid: ^World_Grid,
	positions_table: ^ecs.Table(Position),
	grid_positions_table: ^ecs.Table(Grid_Position),
	view: ^ecs.View,
) {

	eids := ecs.entities_slice(view)
	positions := ecs.slice(positions_table)
	grid_positions := ecs.slice(grid_positions_table)

	pos: Position
	cell: ^World_Cell
	ok: bool
	for i in 0 ..< len(eids) {
		pos = positions[i]
		cell, ok = world_grid_get_cell_by_world_pos(grid, pos.x, pos.y)
		if !ok {
			report_error(fmt.aprintf("Position % is outside of thw world grid", pos))
			continue
		}

		grid_positions[i].x = i32(pos.x / grid.cell_size)
		grid_positions[i].y = i32(pos.y / grid.cell_size)
	}
}

//TODO: Move to test pkg
@(test)
create_empty_grid_test :: proc(t: ^testing.T) {
	grid: World_Grid
	ok := world_grid_create(&grid)
	defer world_grid_delete(&grid)

	testing.expect_value(t, ok, true)
}
