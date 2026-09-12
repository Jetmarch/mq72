package cellular_automaton

import "../utils"
import "core:testing"

@(test)
test_ca_world_init :: proc(t: ^testing.T) {
	ca_world: CA_World
	err: CA_Error
	err = ca_init(&ca_world, 10, 10)
	defer ca_world_terminate(&ca_world)

	testing.expect(t, err == nil, "Cellular world init error")
}

@(test)
test_ca_world_initca_world_update :: proc(t: ^testing.T) {

	ca_world: CA_World
	err: CA_Error
	err = ca_init(&ca_world, 10, 10)
	defer ca_world_terminate(&ca_world)
	ca_rule := ca_world_get_conway_rule()

	set_cell_alive(&ca_world, 1, 1, true)
	set_cell_alive(&ca_world, 1, 2, true)
	set_cell_alive(&ca_world, 2, 1, true)
	set_cell_alive(&ca_world, 4, 1, true)
	set_cell_alive(&ca_world, 4, 2, true)


	step(&ca_world, &ca_rule)

	cell, grid_err := utils.grid_get_cell(&ca_world.grid, 1, 1)

	testing.expect(t, err == nil, "Error while getting cell from grid")

	testing.expect_value(t, cell.is_alive, true)


	cell, grid_err = utils.grid_get_cell(&ca_world.grid, 2, 2)

	testing.expect_value(t, cell.neighbor_count, 3)
}

@(test)
test_contains :: proc(t: ^testing.T) {
	ca_rule := ca_world_get_conway_rule()

	testing.expect(t, contains(&ca_rule.born_at, 3), "Rule does not contains expected value")
	testing.expect(t, !contains(&ca_rule.born_at, 4), "Rule contains does not expected value")

	testing.expect(t, contains(&ca_rule.survive_at, 3), "Rule does not contains expected value")
}
