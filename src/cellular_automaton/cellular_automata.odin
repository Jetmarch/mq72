package cellular_automaton

import "../utils"
import "vendor:raylib"

MAX_NEIGHBORS :: 8


Cellular_World :: struct {
	grid:       utils.Grid(Automaton_Cell),
	generation: i32,
	neighbors:  [MAX_NEIGHBORS]utils.Vector2,
}

//
// Describes BN..Na/SN..Na notation
Cellular_Rule :: struct {
	born_at:    [MAX_NEIGHBORS]i32,
	survive_at: [MAX_NEIGHBORS]i32,
}

Automaton_Cell :: struct {
	x:              i32,
	y:              i32,
	position:       utils.Cell,
	is_alive:       bool,
	age:            u8,
	neighbor_count: u8,
}


Error :: enum {
	None,
	Incorrect_Grid_Coordinates,
	Grid_Is_Not_Initialized,
}

ca_world_init :: proc(ca_world: ^Cellular_World, width: i32, height: i32) -> Error {
	err := utils.grid_init(&ca_world.grid, width, height)
	if err != nil {
		return Error.Grid_Is_Not_Initialized
	}

	ca_world.neighbors[0] = utils.Vector2{0, -1}
	ca_world.neighbors[1] = utils.Vector2{0, 1}
	ca_world.neighbors[2] = utils.Vector2{-1, 0}
	ca_world.neighbors[3] = utils.Vector2{1, 0}
	ca_world.neighbors[4] = utils.Vector2{-1, -1}
	ca_world.neighbors[5] = utils.Vector2{1, -1}
	ca_world.neighbors[6] = utils.Vector2{-1, 1}
	ca_world.neighbors[7] = utils.Vector2{1, 1}

	return nil
}

ca_world_set_cell_alive_world_coord :: proc(
	world: ^Cellular_World,
	x: i32,
	y: i32,
	is_alive: bool,
	cell_size: i32,
) -> Error {
	return ca_world_set_cell_alive(world, x / cell_size, y / cell_size, is_alive)
}

ca_world_set_cell_alive :: proc(world: ^Cellular_World, x: i32, y: i32, is_alive: bool) -> Error {
	cell, err := utils.grid_get_cell(&world.grid, x, y)
	if err != nil {
		return .Incorrect_Grid_Coordinates
	}

	cell.is_alive = is_alive

	return nil
}

ca_world_update :: proc(world: ^Cellular_World, rule: ^Cellular_Rule) {

	cell: ^Automaton_Cell
	for i in 0 ..< world.grid.width * world.grid.height {
		cell = &world.grid.cells[i]
		ca_world_set_alive_neighbor_count(world, cell)
		ca_world_apply_rule(cell, rule)
	}
}

ca_world_set_alive_neighbor_count :: proc(ca_world: ^Cellular_World, cell: ^Automaton_Cell) {
	cell.neighbor_count = 0
	coords: utils.Vector2
	neighbor: ^Automaton_Cell
	err: utils.Grid_Error
	for i in 0 ..< len(ca_world.neighbors) {
		coords = ca_world.neighbors[i]
		neighbor, err = utils.grid_get_cell(&ca_world.grid, coords.x, coords.y)
		if err != nil {
			continue
		}
		if neighbor.is_alive {
			cell.neighbor_count += 1
		}
	}
}

ca_world_apply_rule :: proc(cell: ^Automaton_Cell, rule: ^Cellular_Rule) {
	if contains(&rule.survive_at, cell.neighbor_count) ||
	   contains(&rule.born_at, cell.neighbor_count) {
		if cell.is_alive {
			cell.age += 1
		} else {
			cell.is_alive = true
		}
	} else {
		cell.is_alive = false
	}
}

contains :: proc(arr: ^[8]($T), val: ($Y)) -> bool {
	for i in 0 ..< len(arr) {
		if arr[i] == cast(T)val {
			return true
		}
	}

	return false
}

ca_world_terminate :: proc(cw: ^Cellular_World) {
	utils.grid_terminate(&cw.grid)
}

ca_world_render :: proc(cw: ^Cellular_World, cell_size: i32) {
	utils.grid_render(&cw.grid, cell_size)

	cell: ^Automaton_Cell
	for i in 0 ..< len(cw.grid.cells) {
		cell = &cw.grid.cells[i]
		if (cell.is_alive) {
			raylib.DrawRectangle(
				cell.x * cell_size,
				cell.y * cell_size,
				cell_size,
				cell_size,
				raylib.BROWN,
			)
		}
	}

}

ca_world_get_conway_rule :: proc() -> Cellular_Rule {
	ca_rule: Cellular_Rule
	ca_rule.born_at[0] = 3
	ca_rule.survive_at[0] = 2
	ca_rule.survive_at[1] = 3

	return ca_rule
}
