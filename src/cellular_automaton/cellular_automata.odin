package cellular_automaton

import "../utils"
import "vendor:raylib"

MAX_NEIGHBORS :: 8

DRAW_NEIGHBORS_COUNT :: false

///
// CA - Cellular Automaton

CA_World :: struct {
	grid:        utils.Grid(CA_Cell),
	grid_buffer: utils.Grid(CA_Cell),
	generation:  i32,
	neighbors:   [MAX_NEIGHBORS]utils.Vector2,
}

//
// Describes BN..Na/SN..Na notation
CA_Rule :: struct {
	born_at:    [MAX_NEIGHBORS]i32,
	survive_at: [MAX_NEIGHBORS]i32,
}

CA_Cell :: struct {
	x:              i32,
	y:              i32,
	is_alive:       bool,
	age:            u8,
	neighbor_count: u8,
}

CA_Error :: enum {
	None,
	Incorrect_Grid_Coordinates,
	Grid_Is_Not_Initialized,
}

ca_init :: proc(cw: ^CA_World, width: i32, height: i32) -> CA_Error {
	err := utils.grid_init(&cw.grid, width, height)
	if err != nil {
		return CA_Error.Grid_Is_Not_Initialized
	}

	err = utils.grid_init(&cw.grid_buffer, width, height)
	if err != nil {
		return CA_Error.Grid_Is_Not_Initialized
	}

	cw.neighbors[0] = utils.Vector2{0, -1}
	cw.neighbors[1] = utils.Vector2{0, 1}
	cw.neighbors[2] = utils.Vector2{-1, 0}
	cw.neighbors[3] = utils.Vector2{1, 0}
	cw.neighbors[4] = utils.Vector2{-1, -1}
	cw.neighbors[5] = utils.Vector2{1, -1}
	cw.neighbors[6] = utils.Vector2{-1, 1}
	cw.neighbors[7] = utils.Vector2{1, 1}

	x: i32
	y: i32
	cell: ^CA_Cell
	for i: i32 = 0; i < cast(i32)len(cw.grid.cells); i += 1 {
		x, y = utils.grid_cell_index_to_coord(i, cw.grid.width)

		cell = &cw.grid.cells[i]
		cell.x = x
		cell.y = y
		cell.neighbor_count = 0
	}

	cw.grid_buffer.cells = cw.grid.cells

	return nil
}

set_cell_alive_by_world_coord :: proc(
	cw: ^CA_World,
	x: i32,
	y: i32,
	is_alive: bool,
	cell_size: i32,
) -> CA_Error {
	return set_cell_alive(cw, x / cell_size, y / cell_size, is_alive)
}

set_cell_alive :: proc(world: ^CA_World, x: i32, y: i32, is_alive: bool) -> CA_Error {
	cell, err := utils.grid_get_cell(&world.grid, x, y)
	if err != nil {
		return .Incorrect_Grid_Coordinates
	}

	cell.is_alive = is_alive

	return nil
}

step :: proc(cw: ^CA_World, rule: ^CA_Rule) {

	cell: ^CA_Cell

	for i in 0 ..< len(cw.grid.cells) {
		cell = &cw.grid.cells[i]
		cw.grid_buffer.cells[i].neighbor_count = count_neighbors(cw, cell)
		cw.grid_buffer.cells[i].is_alive = apply_rule(cell, rule)
	}
	cw.grid.cells = cw.grid_buffer.cells
}


contains :: proc(arr: ^[8]($T), val: ($Y)) -> bool {
	for i in 0 ..< len(arr) {
		if arr[i] == cast(T)val {
			return true
		}
	}

	return false
}

ca_world_terminate :: proc(cw: ^CA_World) {
	utils.grid_terminate(&cw.grid)
	utils.grid_terminate(&cw.grid_buffer)
}

ca_world_render :: proc(cw: ^CA_World, cell_size: i32) {

	color: raylib.Color
	cell: ^CA_Cell
	for i in 0 ..< len(cw.grid.cells) {
		cell = &cw.grid.cells[i]
		if (cell.is_alive) {
			color = raylib.Color{255, 0, 0, 120}
		} else {
			color = raylib.BLANK
		}

		raylib.DrawRectangle(cell.x * cell_size, cell.y * cell_size, cell_size, cell_size, color)


		when DRAW_NEIGHBORS_COUNT {
			neighbor_count := ca_world_get_alive_neighbor_count(cw, cell)

			cnt := fmt.caprint(neighbor_count)
			defer delete(cnt)
			raylib.DrawText(cnt, cell.x * cell_size, cell.y * cell_size, 10, raylib.BLACK)
		}
	}

}

ca_rule_init :: proc(rule: ^CA_Rule) {
	for i in 0 ..< len(rule.born_at) {
		rule.born_at[i] = -1
		rule.survive_at[i] = -1
	}
}

// B3/S23 rulestring
ca_world_get_conway_rule :: proc() -> CA_Rule {
	ca_rule: CA_Rule

	ca_rule_init(&ca_rule)

	ca_rule.born_at[0] = 3
	ca_rule.survive_at[0] = 2
	ca_rule.survive_at[1] = 3

	return ca_rule
}

ca_world_get_custom_rule :: proc() -> CA_Rule {
	ca_rule: CA_Rule

	ca_rule_init(&ca_rule)

	ca_rule.born_at[0] = 3
	ca_rule.survive_at[0] = 3
	ca_rule.survive_at[1] = 2

	return ca_rule
}

count_neighbors :: proc(cw: ^CA_World, cell: ^CA_Cell) -> (n: u8) {
	n = 0
	for dy :i32 = -1; dy <= 1; dy += 1 {
		for dx :i32 = -1; dx <= 1; dx += 1 {
			if dx == 0 && dy == 0 {
				continue
			}
			nx := (cell.x + dx + cw.grid.width) % cw.grid.width
			ny := (cell.y + dy + cw.grid.height) % cw.grid.height

			neighbor, err := utils.grid_get_cell(&cw.grid, nx, ny)
			if err != nil {
				continue
			}

			if neighbor.is_alive {
				n += 1
			}
		}
	}
	return n
}

@(private)
get_alive_neighbor_count :: proc(
	cw: ^CA_World,
	cell: ^CA_Cell,
) -> (
	neighbors_count: u8,
) {
	coords: utils.Vector2
	neighbor: ^CA_Cell
	err: utils.Grid_Error
	for i in 0 ..< len(cw.neighbors) {
		coords = cw.neighbors[i]
		neighbor, err = utils.grid_get_cell(&cw.grid, cell.x + coords.x, cell.y + coords.y)
		if err != nil {
			continue
		}
		if neighbor.is_alive {
			neighbors_count += 1
		}
	}

	return neighbors_count
}

@(private)
apply_rule :: proc(
	cell: ^CA_Cell,
	rule: ^CA_Rule,
) -> (
	is_alive: bool,
) {
	// if contains(&rule.survive_at, cell.neighbor_count) ||
	//    contains(&rule.born_at, cell.neighbor_count) {
	// 	if cell.is_alive {
	// 		cell.age += 1
	// 	} else {
	// 		is_alive = true
	// 	}

	// } else {
	// 	is_alive = false
	// }

	if cell.is_alive {
		return cell.neighbor_count == 2 || cell.neighbor_count == 3
	}

	return cell.neighbor_count == 3
}
