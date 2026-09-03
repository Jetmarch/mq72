package mq72

import rl "vendor:raylib"
import "core:mem"
import "core:log"

import oc "../vendor/ode_ecs/src/ode_core"

main :: proc() {

	mem_track: oc.Mem_Track

    context.allocator = oc.mem_track__init(&mem_track, context.allocator)
    defer oc.mem_track__terminate(&mem_track)
    defer oc.mem_track__panic_if_bad_frees_or_leaks(&mem_track) // Defers run in reverse declaration order

    context.logger = log.create_console_logger()
    defer log.destroy_console_logger(context.logger)

	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, SCREEN_NAME)
	defer rl.CloseWindow()

	game: Game
	defer terminate_game(&game)

	if !init_game(&game, context.allocator) {
		report_error("Init game failure");
		return;
	}

	for !rl.WindowShouldClose() {
		process_frame(&game)
		render_frame(&game)
	}
}
