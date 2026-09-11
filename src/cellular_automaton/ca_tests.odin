package cellular_automaton

import "../utils"
import "core:testing"

@(test)
test_ca_world_init :: proc(t: ^testing.T) {
	ca_world: Cellular_World
	err: Error
	err = ca_world_init(&ca_world, 10, 10)
	defer ca_world_terminate(&ca_world)

	testing.expect(t, err == nil, "Cellular world init error")
}

@(test)
test_ca_world_initca_world_update :: proc(t: ^testing.T) {

	ca_world: Cellular_World
	err: Error
	err = ca_world_init(&ca_world, 10, 10)
	defer ca_world_terminate(&ca_world)
	ca_rule: Cellular_Rule
	ca_rule.born_at[0] = 3
	ca_rule.survive_at[0] = 2
	ca_rule.survive_at[1] = 3

	ca_world_set_cell_alive(&ca_world, 1, 1, true)
	ca_world_set_cell_alive(&ca_world, 1, 2, true)
	ca_world_set_cell_alive(&ca_world, 2, 1, true)
	ca_world_set_cell_alive(&ca_world, 4, 1, true)
	ca_world_set_cell_alive(&ca_world, 4, 2, true)


	ca_world_update(&ca_world, &ca_rule)

	cell, grid_err := utils.grid_get_cell(&ca_world.grid, 1, 1)

	testing.expect(t, err == nil, "Error while getting cell from grid")


	testing.expect_value(t, cell.is_alive, true)
}
