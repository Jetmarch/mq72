package cellular_automaton

import "utils"

MAX_NEIGHBORS :: 8

Cellular_World :: struct {
	grid:       utils.Grid,
	generation: i32,
}

//
// Describes BN..Na/SN..Na notation
Cellular_Rule :: struct {
	born_at:    [MAX_NEIGHBORS]i32,
	survive_at: [MAX_NEIGHBORS]i32,
}

Automaton_Cell :: struct {
	position: utils.Cell,
	bool:     is_alive,
	age:      i32,
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

cell_world_init :: proc(width: i32, height: i32) -> Cellular_World {
	return Cellular_World{grid = utils.grid_init(width, height)}
}

cell_world_update :: proc(world: ^Cellular_World, rule: ^Cellular_Rule) {
	for x in 0 .. world.grid.width {
		for y in 0 .. world.grid.height {

		}
	}
}

cell_world_get_neighbor :: proc() -> ^utils.Cell {

}

cell_world_terminate :: proc(cw: ^Cellular_World) {
	delete(cw.grid)
}
