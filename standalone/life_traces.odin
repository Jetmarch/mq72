package main

// ============================================================================
// Game of life with traces
// ============================================================================


import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"

WIDTH     :: 70
HEIGHT    :: 35
CELL_SIZE :: 14

GRID_W :: WIDTH * CELL_SIZE
GRID_H :: HEIGHT * CELL_SIZE

PANEL_WIDTH   :: 300
PANEL_PADDING :: 10
ROW_HEIGHT    :: 24
PANEL_TOP     :: 56

SCREEN_W :: GRID_W + PANEL_WIDTH
SCREEN_H :: 540

GENERATIONS_PER_EPOCH :: 500


Settings :: struct {
	seed_density:         f32,
	trace_deposit:        f32,
	trace_decay:          f32,
	trace_diffuse:        f32,
	trace_max:            f32,
	fertile_low:          f32,
	fertile_high:         f32,
	exhausted_level:      f32,
	base_survival_chance: f32,
	base_birth_chance:    f32,
	fertile_bonus:        f32,
	fertile_extra_chance: f32,
	exhausted_mult:       f32,
	rare_exhausted_event: f32,
	max_chance:           f32,
	step_every_frames:    f32, // округляется до целого при использовании
}

default_settings := Settings{
	seed_density         = 0.30,
	trace_deposit        = 1.0,
	trace_decay          = 0.94,
	trace_diffuse        = 0.06,
	trace_max            = 10.0,
	fertile_low          = 1.2,
	fertile_high         = 4.5,
	exhausted_level      = 7.0,
	base_survival_chance = 0.80,
	base_birth_chance    = 0.75,
	fertile_bonus        = 0.15,
	fertile_extra_chance = 0.35,
	exhausted_mult       = 0.30,
	rare_exhausted_event = 0.06,
	max_chance           = 0.95,
	step_every_frames    = 5,
}

settings := default_settings


Cell :: struct {
	alive: bool,
	trace: f32,
}

Grid :: [HEIGHT][WIDTH]Cell

count_neighbors :: proc(g: ^Grid, x, y: int) -> int {
	n := 0
	for dy := -1; dy <= 1; dy += 1 {
		for dx := -1; dx <= 1; dx += 1 {
			if dx == 0 && dy == 0 {
				continue
			}
			nx := (x + dx + WIDTH) % WIDTH
			ny := (y + dy + HEIGHT) % HEIGHT
			if g[ny][nx].alive {
				n += 1
			}
		}
	}
	return n
}

neighbor_trace_avg :: proc(g: ^Grid, x, y: int) -> f32 {
	sum := f32(0)
	for dy := -1; dy <= 1; dy += 1 {
		for dx := -1; dx <= 1; dx += 1 {
			if dx == 0 && dy == 0 {
				continue
			}
			nx := (x + dx + WIDTH) % WIDTH
			ny := (y + dy + HEIGHT) % HEIGHT
			sum += g[ny][nx].trace
		}
	}
	return sum / 8
}

survival_chance :: proc(neighbors: int, trace: f32) -> f32 {
	switch {
	case trace >= settings.exhausted_level:
		if neighbors == 3 {
			return settings.base_survival_chance * settings.exhausted_mult
		}
		return 0

	case trace >= settings.fertile_low && trace <= settings.fertile_high:
		switch neighbors {
		case 2, 3:
			return min(settings.base_survival_chance + settings.fertile_bonus, settings.max_chance)
		case 4:
			return settings.fertile_extra_chance
		}
		return 0

	case:
		if neighbors == 2 || neighbors == 3 {
			return settings.base_survival_chance
		}
		return 0
	}
}

birth_chance :: proc(neighbors: int, trace: f32) -> f32 {
	switch {
	case trace >= settings.exhausted_level:
		if neighbors == 6 {
			return settings.rare_exhausted_event
		}
		return 0

	case trace >= settings.fertile_low && trace <= settings.fertile_high:
		switch neighbors {
		case 3:
			return min(settings.base_birth_chance + settings.fertile_bonus, settings.max_chance)
		case 2:
			return settings.fertile_extra_chance
		}
		return 0

	case:
		if neighbors == 3 {
			return settings.base_birth_chance
		}
		return 0
	}
}

next_state :: proc(alive: bool, neighbors: int, trace: f32) -> bool {
	chance := survival_chance(neighbors, trace) if alive else birth_chance(neighbors, trace)
	chance = clamp(chance, 0, settings.max_chance)
	return rand.float32() < chance
}

step :: proc(cur: ^Grid, nxt: ^Grid) {
	for y := 0; y < HEIGHT; y += 1 {
		for x := 0; x < WIDTH; x += 1 {
			cell := cur[y][x]
			n := count_neighbors(cur, x, y)
			alive := next_state(cell.alive, n, cell.trace)

			trace := cell.trace
			if cell.alive {
				trace += settings.trace_deposit
			}
			trace *= settings.trace_decay
			trace = trace*(1 - settings.trace_diffuse) + neighbor_trace_avg(cur, x, y)*settings.trace_diffuse
			if trace > settings.trace_max {
				trace = settings.trace_max
			}

			nxt[y][x] = Cell{alive = alive, trace = trace}
		}
	}
}

seed_random :: proc(g: ^Grid) {
	for y := 0; y < HEIGHT; y += 1 {
		for x := 0; x < WIDTH; x += 1 {
			g[y][x].alive = rand.float32() < settings.seed_density
			g[y][x].trace = 0
		}
	}
}

trace_color :: proc(trace: f32) -> rl.Color {
	switch {
	case trace >= settings.exhausted_level:
		return rl.Color{210, 90, 40, 255}
	case trace >= settings.fertile_low:
		return rl.Color{90, 200, 120, 255}
	case:
		return rl.Color{150, 150, 160, 255}
	}
}

clamp01 :: proc(v: f32) -> f32 {
	if v < 0 {
		return 0
	}
	if v > 1 {
		return 1
	}
	return v
}

draw_grid :: proc(g: ^Grid) {
	for y := 0; y < HEIGHT; y += 1 {
		for x := 0; x < WIDTH; x += 1 {
			cell := g[y][x]
			px := i32(x * CELL_SIZE)
			py := i32(y * CELL_SIZE)

			if cell.alive {
				rl.DrawRectangle(px, py, CELL_SIZE - 1, CELL_SIZE - 1, rl.Color{235, 250, 235, 255})
			} else if cell.trace > 0.05 {
				alpha := clamp01(cell.trace / settings.trace_max)
				col := rl.Fade(trace_color(cell.trace), alpha)
				rl.DrawRectangle(px, py, CELL_SIZE - 1, CELL_SIZE - 1, col)
			}
		}
	}
}


Param :: struct {
	name:   string,
	value:  ^f32,
	min:    f32,
	max:    f32,
	is_int: bool,
}

make_params :: proc() -> [16]Param {
	return [16]Param{
		{"Seed density", &settings.seed_density, 0.05, 0.60, false},
		{"Trace deposit", &settings.trace_deposit, 0.0, 3.0, false},
		{"Trace decay", &settings.trace_decay, 0.50, 0.995, false},
		{"Trace diffuse", &settings.trace_diffuse, 0.0, 0.30, false},
		{"Trace max", &settings.trace_max, 2.0, 20.0, false},
		{"Fertile low", &settings.fertile_low, 0.0, 10.0, false},
		{"Fertile high", &settings.fertile_high, 0.0, 15.0, false},
		{"Exhausted level", &settings.exhausted_level, 0.0, 20.0, false},
		{"Base survival chance", &settings.base_survival_chance, 0.0, 1.0, false},
		{"Base birth chance", &settings.base_birth_chance, 0.0, 1.0, false},
		{"Fertile bonus", &settings.fertile_bonus, 0.0, 0.50, false},
		{"Fertile extra chance", &settings.fertile_extra_chance, 0.0, 1.0, false},
		{"Exchausted mult", &settings.exhausted_mult, 0.0, 1.0, false},
		{"Rare exhausted event", &settings.rare_exhausted_event, 0.0, 0.50, false},
		{"Max chance", &settings.max_chance, 0.50, 1.0, false},
		{"Step every frame", &settings.step_every_frames, 1.0, 20.0, true},
	}
}

update_ui :: proc(params: []Param, dragging: ^int) {
	mouse := rl.GetMousePosition()
	panel_x := i32(GRID_W)
	track_x0 := f32(panel_x + PANEL_PADDING)
	track_w := f32(PANEL_WIDTH - PANEL_PADDING*2)

	if rl.IsMouseButtonPressed(.LEFT) {
		for i in 0 ..< len(params) {
			row_y := PANEL_TOP + i32(i)*ROW_HEIGHT
			if mouse.x >= f32(panel_x) && mouse.x < f32(panel_x+PANEL_WIDTH) &&
			   mouse.y >= f32(row_y) && mouse.y < f32(row_y+ROW_HEIGHT) {
				dragging^ = i
			}
		}
	}
	if rl.IsMouseButtonReleased(.LEFT) {
		dragging^ = -1
	}
	if dragging^ >= 0 && rl.IsMouseButtonDown(.LEFT) {
		p := &params[dragging^]
		t := clamp((mouse.x - track_x0) / track_w, 0, 1)
		p.value^ = p.min + t*(p.max - p.min)
	}
}

draw_ui :: proc(params: []Param, dragging: int, gen: int) {
	panel_x := i32(GRID_W)

	rl.DrawRectangle(panel_x, 0, PANEL_WIDTH, SCREEN_H, rl.Color{24, 24, 28, 255})
	rl.DrawLine(panel_x, 0, panel_x, SCREEN_H, rl.Color{60, 60, 66, 255})

	rl.DrawText("Life traces", panel_x+PANEL_PADDING, 10, 18, rl.RAYWHITE)
	rl.DrawText(fmt.ctprintf("Generation: %d", gen), panel_x+PANEL_PADDING, 32, 14, rl.Color{170, 170, 180, 255})

	for i in 0 ..< len(params) {
		p := params[i]
		row_y := PANEL_TOP + i32(i)*ROW_HEIGHT
		track_x := panel_x + PANEL_PADDING
		track_w := i32(PANEL_WIDTH - PANEL_PADDING*2)

		t := clamp01((p.value^ - p.min) / (p.max - p.min))
		fill_w := i32(f32(track_w) * t)

		track_col := rl.Color{50, 50, 58, 255}
		fill_col := rl.Color{140, 200, 255, 255} if i == dragging else rl.Color{100, 170, 220, 255}

		rl.DrawRectangle(track_x, row_y+2, track_w, ROW_HEIGHT-6, track_col)
		rl.DrawRectangle(track_x, row_y+2, fill_w, ROW_HEIGHT-6, fill_col)

		if p.is_int {
			rl.DrawText(fmt.ctprintf("%s: %d", p.name, int(p.value^ + 0.5)), track_x+4, row_y+3, 12, rl.RAYWHITE)
		} else {
			rl.DrawText(fmt.ctprintf("%s: %.2f", p.name, p.value^), track_x+4, row_y+3, 12, rl.RAYWHITE)
		}
	}

	reset_y := PANEL_TOP + i32(len(params))*ROW_HEIGHT + 14
	reset_rect := rl.Rectangle{f32(panel_x+PANEL_PADDING), f32(reset_y), f32(PANEL_WIDTH-PANEL_PADDING*2), 28}
	mouse := rl.GetMousePosition()
	hovered := rl.CheckCollisionPointRec(mouse, reset_rect)
	btn_col := rl.Color{100, 65, 65, 255} if hovered else rl.Color{70, 45, 45, 255}
	rl.DrawRectangleRec(reset_rect, btn_col)
	rl.DrawText("Restore defaults", i32(reset_rect.x)+10, i32(reset_rect.y)+7, 12, rl.RAYWHITE)

	if hovered && rl.IsMouseButtonPressed(.LEFT) {
		settings = default_settings
	}

	rl.DrawText("R - reset field", panel_x+PANEL_PADDING, reset_y+40, 12, rl.Color{150, 150, 160, 255})
}

main :: proc() {
	rl.InitWindow(SCREEN_W, SCREEN_H, "Life traces (raylib)")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	a: Grid
	b: Grid
	cur := &a
	nxt := &b
	seed_random(cur)

	params := make_params()
	dragging := -1

	gen := 0
	frame := 0

	for !rl.WindowShouldClose() {
		update_ui(params[:], &dragging)

		if rl.IsKeyPressed(.R) {
			seed_random(cur)
			gen = 0
		}

		step_n := int(settings.step_every_frames + 0.5)
		if step_n < 1 {
			step_n = 1
		}

		frame += 1
		if frame % step_n == 0 {
			step(cur, nxt)
			cur, nxt = nxt, cur
			gen += 1

			if gen >= GENERATIONS_PER_EPOCH {
				seed_random(cur)
				gen = 0
			}
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{16, 16, 20, 255})
		draw_grid(cur)
		draw_ui(params[:], dragging, gen)
		rl.EndDrawing()
	}
}
