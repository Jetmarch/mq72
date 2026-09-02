/*
	2026 j3s2
*/

package mq72

import rl "vendor:raylib"
import "core:log"

CONSOLE_LOG :: #config(FILE_LOG, true)

SCREEN_WIDTH :: 600
SCREEN_HEIGHT :: 420
SCREEN_NAME :: "mq72"


Game :: struct {
	state: Game_State,
	logger: log.Logger
}

Game_State :: enum {
	Not_Initialized = 0,
	Running,
	Terminated
}


init_game :: proc(game: ^Game) {
	game.state = .Running
	game.logger = log.create_console_logger()
}

process_frame :: proc(game: ^Game) {

}

render_frame :: proc(game: ^Game) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.DARKGRAY)

	rl.DrawText(SCREEN_NAME,
		rl.GetScreenWidth() / 2 - rl.MeasureText(SCREEN_NAME, 20) / 2,
		rl.GetScreenHeight() / 2 - 50, 20, rl.GRAY
	)

	// Draw enviroment
	// Draw entities
	// Draw UI
}

terminate_game :: proc(game: ^Game) {
	if game.state == .Terminated {
		return
	}

	game.state = .Terminated
}
