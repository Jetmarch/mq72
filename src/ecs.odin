package mq72

import ecs "../vendor/ode_ecs/src"
import rl "vendor:raylib"

Ecs_World :: struct {
	units_db:          ecs.Database,
	err:               ecs.Error,
	positions:         ecs.Table(Position),
	velocities:        ecs.Table(Velocity),
	sprites:           ecs.Table(Sprite),
	healths:           ecs.Table(Health),
	is_circle_sprites: ecs.Tag_Table,
	is_unit_selected:  ecs.Tag_Table,
	grid_positions:    ecs.Table(Grid_Position),
	render_view:        ecs.View,
	grid_position_view: ecs.View,
}

init_ecs_world :: proc(ecs_world: ^Ecs_World) -> bool {
	ecs_world.err = ecs.init(&ecs_world.units_db, UNIT_ENTITIES_CAP)

	if ecs_world.err != nil {
		return false
	}

	if !init_table(&ecs_world.positions, &ecs_world.units_db) {
		return false
	}

	if !init_table(&ecs_world.velocities, &ecs_world.units_db) {
		return false
	}

	if !init_table(&ecs_world.sprites, &ecs_world.units_db) {
		return false
	}

	if !init_table(&ecs_world.healths, &ecs_world.units_db) {
		return false
	}

	if !init_tag_table(&ecs_world.is_circle_sprites, &ecs_world.units_db) {
		return false
	}

	if !init_tag_table(&ecs_world.is_unit_selected, &ecs_world.units_db) {
		return false
	}

	if !init_table(&ecs_world.grid_positions, &ecs_world.units_db) {
		return false
	}

	ecs.view_init(
		&ecs_world.render_view,
		&ecs_world.units_db,
		{&ecs_world.is_circle_sprites, &ecs_world.positions},
	)

	ecs.view_init(
		&ecs_world.grid_position_view,
		&ecs_world.units_db,
		{&ecs_world.positions, &ecs_world.grid_positions},
	)

	return true
}

init_table :: proc(table: ^ecs.Table($T), db: ^ecs.Database) -> bool {
	err := ecs.table_init(table, db, UNIT_ENTITIES_CAP)
	if err != nil {
		report_error(err)
		return false
	}

	return true
}

init_tag_table :: proc(tag_table: ^ecs.Tag_Table, db: ^ecs.Database) -> bool {
	err := ecs.tag_table_init(tag_table, db, UNIT_ENTITIES_CAP)
	if err != nil {
		report_error(err)
		return false
	}

	return true
}

update_ecs_systems :: proc(ecs_world: ^Ecs_World) {
	renderable_eid := ecs.entities_slice(&ecs_world.render_view)
	pos_slice := ecs.slice(&ecs_world.render_view, Position)

	pos: ^Position
	grid_pos: ^Grid_Position
	for i in 0 ..< len(renderable_eid) {
		pos = pos_slice[i]

		rl.DrawCircle(i32(pos.x), i32(pos.y), 4.0, rl.BLUE)

		if ecs.has_tag(&ecs_world.is_unit_selected, renderable_eid[i]) {
			rl.DrawCircle(i32(pos.x), i32(pos.y), 5.0, rl.Color{125, 0, 0, 125})
		}
	}
}

terminate_ecs :: proc(ecs_world: ^Ecs_World) {
	ecs.view_terminate(&ecs_world.render_view)
	ecs.view_terminate(&ecs_world.grid_position_view)
	ecs.terminate(&ecs_world.units_db)
}
