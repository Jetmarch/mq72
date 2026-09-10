package cellular_automaton

import "../utils"
import "base:intrinsics"
import "core:rexcode/isa"

MAX_NEIGHBORS :: 8

Vector2 :: struct {
	x, y: i32,
}

Cellular_World :: struct {
	grid:       utils.Grid(Automaton_Cell),
	generation: i32,
	neighbors:  [MAX_NEIGHBORS]Vector2,
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

Cell_Neighbors :: enum utils.Cell {
	Top          = utils.Cell{0, -1},
	Bottom       = utils.Cell{0, 1},
	Left         = utils.Cell{-1, 0},
	Right        = utils.Cell{1, 0},
	Top_Left     = utils.Cell{-1, -1},
	Top_Right    = utils.Cell{1, -1},
	Bottom_Left  = utils.Cell{-1, 1},
	Bottom_Right = utils.Cell{1, 1},
}

Error :: enum {
	None,
	Grid_Is_Not_Initialized,
}

ca_world_init :: proc(ca_world: ^Cellular_World, width: i32, height: i32) -> Error {
	err := utils.grid_init(ca_world.grid, width, height)
	if err != nil {
		return Error.Grid_Is_Not_Initialized
	}

	ca_world.neighbors[0] = Vector2{0, -1}
	ca_world.neighbors[1] = Vector2{0, 1}
	ca_world.neighbors[2] = Vector2{-1, 0}
	ca_world.neighbors[3] = Vector2{1, 0}
	ca_world.neighbors[4] = Vector2{-1, -1}
	ca_world.neighbors[5] = Vector2{1, -1}
	ca_world.neighbors[6] = Vector2{-1, 1}
	ca_world.neighbors[7] = Vector2{1, 1}

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
	coords: Vector2
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
