/*
	2026 j3s2
*/

package mq72


import ca "cellular_automaton"
import "core:fmt"
import "core:log"
import "utils"
import rl "vendor:raylib"

CONSOLE_LOG :: #config(FILE_LOG, true)

SCREEN_WIDTH :: 640
SCREEN_HEIGHT :: 480
SCREEN_NAME :: "mq72"

UNIT_ENTITIES_CAP :: 100


App :: struct {
	state:              App_State,
	ecs_world:          Ecs_World,
	world_grid:         World_Grid,
	unit_selection:     Unit_Selection,
	ca_world:           ca.CA_World,
	ca_rule:            ca.CA_Rule,
}

App_State :: enum {
	Not_Initialized = 0,
	Running,
	Terminated,
}


init_app :: proc(game: ^App, allocator := context.allocator) -> bool {

	is_ok: bool

	is_ok = init_ecs_world(&game.ecs_world)

	if !is_ok {
		report_error("Error on ecs world initialize")
		return is_ok
	}

	is_ok = world_grid_create(&game.world_grid)

	if !is_ok {
		report_error("Grid was not properly created")
		return is_ok
	}

	game.unit_selection.is_active = false


	ca_err := ca.ca_init(&game.ca_world, MAX_MAP_WIDTH, MAX_MAP_HEIGHT)
	if ca_err != nil {
		report_error("Cellular world was not initialized")
		return false
	}

	game.ca_rule = ca.ca_world_get_custom_rule()

	game.state = .Running
	return is_ok
}



process_frame :: proc(game: ^App) {
	if rl.IsKeyPressed(.SPACE) {
		x := rl.GetMouseX()
		y := rl.GetMouseY()
		// eid := create_base_unit_entity(x, y, &game.ecs_world)
		//
		cell_size := game.world_grid.cell_size
		start_point := utils.Vector2{x - (3 * cell_size), y - (3 * cell_size)}
		end_point := utils.Vector2{x + (3 * cell_size), y + (3 * cell_size)}

		for i := start_point.x; i < end_point.x; i += cell_size {
			for j := start_point.y; j < end_point.y; j += cell_size {
				ca.set_cell_alive_by_world_coord(
					&game.ca_world,
					i,
					j,
					true,
					game.world_grid.cell_size,
				)
			}
		}
	}

	// if rl.IsKeyPressed(.TAB) {
		ca.step(&game.ca_world, &game.ca_rule)
	// }

	unit_select_handle_input(&game.unit_selection)
	unit_select_mark_selected_units(&game.unit_selection, &game.ecs_world, &game.world_grid)

	world_grid_update_entities_position(
		&game.world_grid,
		&game.ecs_world.positions,
		&game.ecs_world.grid_positions,
		&game.ecs_world.grid_position_view,
	)


}

render_frame :: proc(game: ^App) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.DARKGRAY)

	unit_select_render(&game.unit_selection)

	unit_select_debug_render_selected_grid(&game.world_grid, &game.unit_selection)

	// world_grid_render_grid(&game.world_grid)

	rl.DrawFPS(20, 20)

	update_ecs_systems(&game.ecs_world)

	ca.ca_world_render(&game.ca_world, game.world_grid.cell_size)

}

terminate_app :: proc(game: ^App) {
	if game.state == .Terminated {
		report_error("Game data was already terminated. Aborting")
		return
	}

	terminate_ecs(&game.ecs_world)
	world_grid_delete(&game.world_grid)
	ca.ca_world_terminate(&game.ca_world)
	game.state = .Terminated
}



report_error :: proc(arg: $T) {
	fmt.println(arg)
}
