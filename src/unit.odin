package mq72

import ecs "../vendor/ode_ecs/src"

import "core:fmt"

create_base_unit_entity :: proc(x: i32, y: i32, world: ^EcsWorld) -> ecs.entity_id {


	eid, err1 := ecs.create_entity(&world.units_db)
	if err1 != nil {
		report_error(err1);
		return eid
	}

	fmt.println(eid)

	pos, err2 := ecs.add_component(&world.positions, eid)
	if err2 != nil {
		report_error(err2);
		return eid
	}

	pos.x = x;
	pos.y = y;

	fmt.println(pos)

	vel, err3 := ecs.add_component(&world.velocities, eid)
	if err3 != nil {
		report_error(err3);
		return eid
	}

	fmt.println(vel)


	health, err4 := ecs.add_component(&world.healths, eid)
	if err4 != nil {
		report_error(err4);
		return eid
	}

	fmt.println(health)


	sprite, err5 := ecs.add_component(&world.sprites, eid)
	if err5 != nil {
		report_error(err5);
		return eid
	}

	fmt.println(sprite)


	ecs.tag(&world.is_circle_sprites, eid)


	return eid
}
