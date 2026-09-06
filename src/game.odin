/*
	2026 j3s2
*/

package mq72

import "core:fmt"
import "core:log"
import rl "vendor:raylib"
import ecs "../vendor/ode_ecs/src"

CONSOLE_LOG :: #config(FILE_LOG, true)

SCREEN_WIDTH :: 640
SCREEN_HEIGHT :: 480
SCREEN_NAME :: "mq72"

UNIT_ENTITIES_CAP :: 100


Game :: struct {
	state: Game_State,

	ecs_world: Ecs_World,


	//TODO: Move views to EcsWorld
	render_view: ecs.View,
	grid_position_view: ecs.View,
	world_grid: ^World_Grid,

	unit_selection: Unit_Selection,
}

Game_State :: enum {
	Not_Initialized = 0,
	Running,
	Terminated
}

Ecs_World :: struct {
	units_db: ecs.Database,
	err: ecs.Error,

	positions: ecs.Table(Position),
	velocities: ecs.Table(Velocity),
	sprites: ecs.Table(Sprite),
	healths: ecs.Table(Health),
	is_circle_sprites: ecs.Tag_Table,
	is_unit_selected: ecs.Tag_Table,
	grid_positions: ecs.Table(Grid_Position),
}


init_game :: proc(game: ^Game, allocator := context.allocator) -> bool {

	is_ok: bool

	is_ok = init_world(&game.ecs_world)

	if !is_ok {
		report_error("Error on ecs world initialize");
		return is_ok;
	}

	ecs.view_init(&game.render_view, &game.ecs_world.units_db, {&game.ecs_world.is_circle_sprites, &game.ecs_world.positions})

	ecs.view_init(&game.grid_position_view, &game.ecs_world.units_db, {&game.ecs_world.positions, &game.ecs_world.grid_positions})

	game.world_grid, is_ok = world_grid_create()

	if !is_ok {
		report_error("Grid was not properly created")
		return is_ok
	}

	game.unit_selection.is_active = false

	game.state = .Running
	return is_ok
}

init_world :: proc(ecs_world: ^Ecs_World) -> bool {
	ecs_world.err = ecs.init(&ecs_world.units_db, UNIT_ENTITIES_CAP)

	if ecs_world.err != nil {
		log.error("Error:", ecs_world.err)
		return false;
	}

	if !init_table(&ecs_world.positions, &ecs_world.units_db) {
		return false;
	}

	if !init_table(&ecs_world.velocities, &ecs_world.units_db) {
		return false;
	}

	if !init_table(&ecs_world.sprites, &ecs_world.units_db) {
		return false;
	}

	if !init_table(&ecs_world.healths, &ecs_world.units_db) {
		return false;
	}

	if !init_tag_table(&ecs_world.is_circle_sprites, &ecs_world.units_db) {
		return false;
	}

	if !init_tag_table(&ecs_world.is_unit_selected, &ecs_world.units_db) {
		return false
	}

	if !init_table(&ecs_world.grid_positions, &ecs_world.units_db) {
		return false;
	}

	return true;
}

process_frame :: proc(game: ^Game) {
	if rl.IsKeyPressed(.SPACE) {
		x := rl.GetMouseX();
		y := rl.GetMouseY();
		eid := create_base_unit_entity(x, y, &game.ecs_world)
	}

	unit_select_handle_input(&game.unit_selection)
	unit_select_mark_selected_units(&game.unit_selection, &game.ecs_world, game.world_grid)

	world_grid_update_entities_position(game.world_grid,
	 &game.ecs_world.positions, &game.ecs_world.grid_positions, &game.grid_position_view)
}

render_frame :: proc(game: ^Game) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.DARKGRAY)

	unit_select_render(&game.unit_selection)

	unit_select_debug_render_selected_grid(game.world_grid, &game.unit_selection)

	world_grid_render_grid(game.world_grid)

	rl.DrawFPS(20, 20)

	// Unit render system
	renderable_eid := ecs.entities_slice(&game.render_view)
	pos_slice := ecs.slice(&game.render_view, Position)

	pos: ^Position
	grid_pos: ^Grid_Position
	for i in 0..<len(renderable_eid) {
		pos = pos_slice[i]

		rl.DrawCircle(i32(pos.x), i32(pos.y), 4.0, rl.BLUE)

		if ecs.has_tag(&game.ecs_world.is_unit_selected, renderable_eid[i]) {
			rl.DrawCircle(i32(pos.x), i32(pos.y), 5.0, rl.Color {125, 0, 0, 125})
		}
	}

	// Additional info
}

terminate_game :: proc(game: ^Game) {
	if game.state == .Terminated {
		report_error("Game data was already terminated. Aborting")
		return
	}
	ecs.terminate(&game.ecs_world.units_db)

	world_grid_delete(game.world_grid)
	game.state = .Terminated
}

init_table :: proc(table: ^ecs.Table($T), db: ^ecs.Database) -> bool {
	err := ecs.table_init(table, db, UNIT_ENTITIES_CAP)
	if err != nil {
		report_error(err);
		return false;
	}

	return true;
}

init_tag_table :: proc(tag_table: ^ecs.Tag_Table, db: ^ecs.Database) -> bool{
	err := ecs.tag_table_init(tag_table, db, UNIT_ENTITIES_CAP)
	if err != nil {
		report_error(err);
		return false;
	}

	return true;
}

report_error :: proc(arg: $T) {
	fmt.println(arg)
}
