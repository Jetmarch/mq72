package mq72

import ecs "../vendor/ode_ecs/src"

import "core:fmt"

create_base_unit_entity :: proc(x: i32, y: i32, world: ^Ecs_World) -> ecs.entity_id {

	err: ecs.Error
	eid: ecs.entity_id
	pos: ^Position


	eid, err = ecs.create_entity(&world.units_db)
	if err != nil {
		report_error(err);
		return eid
	}

	pos, err = ecs.add_component(&world.positions, eid)
	if err != nil {
		report_error(err);
		return eid
	}

	pos.x = x;
	pos.y = y;

	_, err = ecs.add_component(&world.grid_positions, eid)
	if err != nil {
		report_error(err);
		return eid
	}

	_, err = ecs.add_component(&world.velocities, eid)
	if err != nil {
		report_error(err);
		return eid
	}

	_, err = ecs.add_component(&world.healths, eid)
	if err != nil {
		report_error(err);
		return eid
	}

	_, err = ecs.add_component(&world.sprites, eid)
	if err != nil {
		report_error(err);
		return eid
	}

	ecs.tag(&world.is_circle_sprites, eid)


	return eid
}
