package cellular_automaton

import "core:testing"


@(test)
ca_world_init_test :: proc(t: ^testing.T) {
	ca_world: Cellular_World
	err: Error
	err = ca_world_init(&ca_world, 10, 10)
	defer ca_world_terminate(&ca_world)

	testing.expect(t, err == nil, "Cellular world init error")
}
