package mq72

import rl "vendor:raylib"


main :: proc() {
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, SCREEN_NAME)
	defer rl.CloseWindow()

	game: Game
	defer terminate_game(&game)

	init_game(&game)

	for !rl.WindowShouldClose() {
		process_frame(&game)
		render_frame(&game)
	}
}
