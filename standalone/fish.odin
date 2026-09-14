package main

// ============================================================================
// Fish with traces — raylib rendering, microui settings panel, SDF metaball
// shader.
//
// Cells are no longer a classic Game-of-Life neighbour-count automaton -
// each living cell is a small agent ("fish") that moves around the grid:
//
//   - With no food in sight, a fish wanders chaotically (a random step
//     each generation, including sometimes not moving at all).
//   - If food is within settings.fish_vision_radius cells, the fish
//     steers one cell towards the nearest food it can see.
//   - Reaching a food cell eats it: the fish becomes "well-fed" - immune
//     to death for settings.stable_cell_duration generations (the same
//     mechanic used by the manually-placed stable cell) - and attempts
//     to spawn settings.spawn_count new fish in empty cells around
//     itself.
//   - If the food a fish was chasing disappears before it gets there
//     (eaten by someone else, or simply out of range again), the fish
//     keeps coasting in the same direction for settings.fish_inertia
//     more generations before going back to chaotic wandering.
//   - Every fish ages every generation. Once its age reaches
//     settings.fish_lifespan (and it isn't currently well-fed), it dies
//     of old age - by design fish only live a modest number of
//     generations unless they keep finding food. A dead fish does not
//     vanish immediately: it lingers as a fading grey ghost for
//     settings.death_fade_duration generations (see the trace/fade
//     notes below), then disappears completely.
//
// A cell may only be claimed by a move or a spawn if it was empty both
// at the start of the generation and still unclaimed by anything else
// processed earlier this generation - this keeps the outcome independent
// of scan order and guarantees a fish's own cell is always free for it
// to stay on if its target is taken.
//
// Independently of the fish, every cell still has a "trace" level: an
// accumulated artefact of past life at that spot. Living cells deposit
// trace, it decays over time and diffuses a little into neighbouring
// cells, colouring the "soil" into neutral / fertile / exhausted zones.
// This is now a purely environmental/visual layer - it no longer affects
// fish survival odds directly.
//
// Rendering is done by a single fragment shader (BLOB_FRAGMENT_SHADER)
// applied twice per frame with independent parameters - once for the
// soil layer (background), once for the living cells + ghosts layer
// (drawn on top). Cell state is packed into a small WIDTH x HEIGHT data
// texture (R = alive, G = normalised trace, B = well-fed flag, A =
// "presence" used for ghost fading) and the shader treats each relevant
// cell as a soft "metaball". Food is rendered separately as small red
// markers drawn on top of everything else.
//
// Every parameter is exposed as a slider in the microui panel on the
// right and applies immediately.
//
// Controls: left click — place a well-fed fish; right click — place
// food; R — reseed the field; Esc / closing the window — quit.
// ============================================================================

import "core:c"
import "core:fmt"
import "core:math/rand"
import "core:strings"
import "core:unicode/utf8"
import rl "vendor:raylib"
import mu "vendor:microui"

// --- Field geometry (fixed; not exposed in the UI) ---------------------------

WIDTH     :: 70
HEIGHT    :: 35
CELL_SIZE :: 14

GRID_W :: WIDTH * CELL_SIZE
GRID_H :: HEIGHT * CELL_SIZE

PANEL_X      :: GRID_W + 10
PANEL_Y      :: 10
PANEL_WIDTH  :: 320
PANEL_HEIGHT :: 800

GENERATIONS_PER_EPOCH :: 500 // the field reseeds itself after this many generations

// --- Tunable settings ---------------------------------------------------------

Settings :: struct {
	seed_density:    f32,
	trace_deposit:   f32,
	trace_decay:     f32,
	trace_diffuse:   f32,
	trace_max:       f32,
	fertile_low:     f32,
	exhausted_level: f32,

	step_every_frames: f32, // rounded to int when used

	fish_lifespan:        f32, // max age before natural death, generations
	fish_vision_radius:   f32, // how far a fish can see food, in cells
	fish_inertia:         f32, // Y: generations of coasting after losing sight of food
	spawn_count:          f32, // fish spawned around a meal, if room allows
	stable_cell_duration: f32, // N: generations of guaranteed survival after eating (or manual placement)

	death_fade_duration: f32, // N generations a dead cell lingers as a fading ghost

	cell_blob_radius:    f32, // living-cell metaball influence radius, in cell units
	cell_blob_threshold: f32, // living-cell iso-surface threshold
	cell_blob_edge:      f32, // living-cell smoothstep softness around the threshold

	soil_blob_radius:    f32, // soil metaball influence radius, in cell units
	soil_blob_threshold: f32, // soil iso-surface threshold
	soil_blob_edge:      f32, // soil smoothstep softness around the threshold
}

default_settings := Settings{
	seed_density    = 0.20, // lower than before: fish now multiply on their own by feeding
	trace_deposit   = 1.0,
	trace_decay     = 0.94,
	trace_diffuse   = 0.06,
	trace_max       = 10.0,
	fertile_low     = 1.2,
	exhausted_level = 7.0,

	step_every_frames = 5,

	fish_lifespan        = 50,
	fish_vision_radius   = 5,
	fish_inertia         = 6,
	spawn_count          = 2,
	stable_cell_duration = 15,

	death_fade_duration = 8,

	cell_blob_radius    = 1.7,
	cell_blob_threshold = 0.45,
	cell_blob_edge      = 0.10,

	soil_blob_radius    = 1.4,
	soil_blob_threshold = 0.20,
	soil_blob_edge      = 0.15,
}

settings := default_settings

// --- Simulation data ------------------------------------------------------

Cell :: struct {
	alive:       bool,
	trace:       f32,
	stable_ttl:  int, // remaining generations of guaranteed survival (well-fed)
	fade_ttl:    int, // remaining generations a dead cell is shown as a fading ghost
	food:        bool, // does this cell contain food
	age:         int, // generations since birth or since this fish last ate
	dir_x:       int, // current movement direction, -1/0/1
	dir_y:       int, // current movement direction, -1/0/1
	inertia_ttl: int, // generations left to keep moving in dir_x/dir_y once food is out of sight
}

Grid :: [HEIGHT][WIDTH]Cell

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

sign_int :: proc(v: int) -> int {
	if v > 0 {
		return 1
	}
	if v < 0 {
		return -1
	}
	return 0
}

// finds the nearest food within `radius` cells of (x, y) and returns its
// offset from (x, y); the offset (not absolute coordinates) is returned
// so the caller doesn't have to worry about toroidal wraparound when
// turning it into a direction
find_nearest_food_dir :: proc(g: ^Grid, x, y, radius: int) -> (ddx, ddy: int, found: bool) {
	best_dist_sq := radius*radius + 1
	for dy := -radius; dy <= radius; dy += 1 {
		for dx := -radius; dx <= radius; dx += 1 {
			if dx == 0 && dy == 0 {
				continue
			}
			dist_sq := dx*dx + dy*dy
			if dist_sq > radius*radius {
				continue
			}
			nx := (x + dx + WIDTH) % WIDTH
			ny := (y + dy + HEIGHT) % HEIGHT
			if g[ny][nx].food && dist_sq < best_dist_sq {
				best_dist_sq = dist_sq
				ddx, ddy = dx, dy
				found = true
			}
		}
	}
	return
}

// spawns up to settings.spawn_count new fish in empty cells around
// (x, y); a candidate cell must be free in both cur and nxt so a spawn
// can never overwrite a not-yet-processed fish
try_spawn :: proc(cur: ^Grid, nxt: ^Grid, x, y: int) {
	spawn_n := int(settings.spawn_count + 0.5)
	spawned := 0
	for dy := -1; dy <= 1 && spawned < spawn_n; dy += 1 {
		for dx := -1; dx <= 1 && spawned < spawn_n; dx += 1 {
			if dx == 0 && dy == 0 {
				continue
			}
			sx := (x + dx + WIDTH) % WIDTH
			sy := (y + dy + HEIGHT) % HEIGHT
			if !cur[sy][sx].alive && !nxt[sy][sx].alive {
				nxt[sy][sx].alive = true
				nxt[sy][sx].stable_ttl = 0
				nxt[sy][sx].fade_ttl = 0
				nxt[sy][sx].age = 0
				nxt[sy][sx].dir_x = 0
				nxt[sy][sx].dir_y = 0
				nxt[sy][sx].inertia_ttl = 0
				spawned += 1
			}
		}
	}
}

step :: proc(cur: ^Grid, nxt: ^Grid) {
	// pass 1: trace decay/diffusion and food carry-over for every cell,
	// independent of fish movement
	for y := 0; y < HEIGHT; y += 1 {
		for x := 0; x < WIDTH; x += 1 {
			trace := cur[y][x].trace
			if cur[y][x].alive {
				trace += settings.trace_deposit
			}
			trace *= settings.trace_decay
			trace = trace*(1 - settings.trace_diffuse) + neighbor_trace_avg(cur, x, y)*settings.trace_diffuse
			if trace > settings.trace_max {
				trace = settings.trace_max
			}
			nxt[y][x] = Cell{trace = trace, food = cur[y][x].food}
		}
	}

	// pass 2: age, feed and move every currently living fish. A cell may
	// only be claimed (by movement or by spawning) if it was empty in
	// cur AND has not already been claimed in nxt this generation - that
	// keeps the outcome independent of processing order and guarantees a
	// fish's own starting cell is always free for it to fall back to.
	for y := 0; y < HEIGHT; y += 1 {
		for x := 0; x < WIDTH; x += 1 {
			cell := cur[y][x]
			if !cell.alive {
				continue
			}

			stable_ttl := cell.stable_ttl
			age := cell.age + 1

			if stable_ttl > 0 {
				stable_ttl -= 1
			} else if age >= int(settings.fish_lifespan + 0.5) {
				// old age claims this fish; it leaves a fading ghost
				// behind instead of moving
				nxt[y][x].fade_ttl = int(settings.death_fade_duration + 0.5)
				continue
			}

			ddx, ddy, food_seen := find_nearest_food_dir(cur, x, y, int(settings.fish_vision_radius + 0.5))

			dx, dy, inertia: int
			switch {
			case food_seen:
				// steer straight for the nearest visible food, and keep
				// the inertia reserve topped up while actively chasing
				dx, dy = sign_int(ddx), sign_int(ddy)
				inertia = int(settings.fish_inertia + 0.5)
			case cell.inertia_ttl > 0:
				// coast in the last chase direction for a while longer
				dx, dy = cell.dir_x, cell.dir_y
				inertia = cell.inertia_ttl - 1
			case:
				// chaotic wandering
				dx = int(rand.float32() * 3) - 1
				dy = int(rand.float32() * 3) - 1
			}

			tx := (x + dx + WIDTH) % WIDTH
			ty := (y + dy + HEIGHT) % HEIGHT

			if (tx != x || ty != y) && (cur[ty][tx].alive || nxt[ty][tx].alive) {
				// target occupied - stay put; (x, y) itself is always
				// free since nothing else may move into or spawn on a
				// cell that is currently occupied
				tx, ty = x, y
			}

			if nxt[ty][tx].food {
				nxt[ty][tx].food = false
				stable_ttl = int(settings.stable_cell_duration + 0.5)
				age = 0
				try_spawn(cur, nxt, tx, ty)
			}

			nxt[ty][tx].alive = true
			nxt[ty][tx].stable_ttl = stable_ttl
			nxt[ty][tx].fade_ttl = 0
			nxt[ty][tx].age = age
			nxt[ty][tx].dir_x = dx
			nxt[ty][tx].dir_y = dy
			nxt[ty][tx].inertia_ttl = inertia
		}
	}
}

seed_random :: proc(g: ^Grid) {
	for y := 0; y < HEIGHT; y += 1 {
		for x := 0; x < WIDTH; x += 1 {
			g[y][x] = Cell{alive = rand.float32() < settings.seed_density, trace = 0}
		}
	}
}

// places a well-fed fish at grid coordinates (x, y): immune to death for
// settings.stable_cell_duration generations, exactly as if it had just
// eaten
place_stable_cell :: proc(g: ^Grid, x, y: int) {
	if x < 0 || x >= WIDTH || y < 0 || y >= HEIGHT {
		return
	}
	g[y][x].alive = true
	g[y][x].stable_ttl = int(settings.stable_cell_duration + 0.5)
	g[y][x].fade_ttl = 0
	g[y][x].age = 0
	g[y][x].dir_x = 0
	g[y][x].dir_y = 0
	g[y][x].inertia_ttl = 0
}

// places food at grid coordinates (x, y); the next fish that reaches it
// will eat it
place_food :: proc(g: ^Grid, x, y: int) {
	if x < 0 || x >= WIDTH || y < 0 || y >= HEIGHT {
		return
	}
	g[y][x].food = true
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

// --- SDF metaball shader --------------------------------------------------
//
// One fragment shader, applied twice per frame (soil pass, then living
// cells pass) via the "mode" uniform, with independent blob parameters
// per pass. Cell state is packed into a small WIDTH x HEIGHT data
// texture every frame:
//   R = alive (0/255)
//   G = trace normalised to settings.trace_max (0-255)
//   B = well-fed flag, i.e. stable_ttl > 0 (0/255)
//   A = "presence": 255 while alive, fading down to 0 over
//       settings.death_fade_duration generations after death
// The shader reconstructs a smooth scalar field around each screen pixel
// from the handful of grid cells near it, and thresholds that field to
// get the blobby metaball silhouette.

BLOB_FRAGMENT_SHADER :: `
#version 330

in vec2 fragTexCoord;

uniform sampler2D texture0;
uniform vec2 gridSize;       // (WIDTH, HEIGHT) in cells
uniform int mode;            // 0 = soil, 1 = living cells + fading ghosts
uniform float blobRadius;    // influence radius of one cell, in cell units
uniform float blobThreshold; // iso-surface threshold
uniform float blobEdge;      // smoothstep softness around the threshold
uniform float traceMax;      // current settings.trace_max, decodes the G channel
uniform float fertileLow;
uniform float exhaustedLevel;

out vec4 finalColor;

const vec3 COLOR_ALIVE     = vec3(0.92, 0.98, 0.92);
const vec3 COLOR_STABLE    = vec3(1.00, 0.84, 0.35);
const vec3 COLOR_GHOST     = vec3(0.45, 0.45, 0.47);
const vec3 COLOR_NEUTRAL   = vec3(0.59, 0.59, 0.63);
const vec3 COLOR_FERTILE   = vec3(0.35, 0.78, 0.47);
const vec3 COLOR_EXHAUSTED = vec3(0.82, 0.35, 0.16);

const int SAMPLE_RADIUS = 3; // neighbourhood checked around each pixel, in cells

float falloff(float d, float r)
{
    float t = clamp(1.0 - (d * d) / (r * r), 0.0, 1.0);
    return t * t * t; // soft-object / metaball style falloff
}

void main()
{
    vec2 cellPos = fragTexCoord * gridSize; // position in cell units
    ivec2 baseCell = ivec2(floor(cellPos));

    float totalField = 0.0;
    vec3 colorSum = vec3(0.0);
    float bestWeight = 0.0;
    float bestTrace = 0.0;

    for (int dy = -SAMPLE_RADIUS; dy <= SAMPLE_RADIUS; dy++)
    {
        for (int dx = -SAMPLE_RADIUS; dx <= SAMPLE_RADIUS; dx++)
        {
            ivec2 c = baseCell + ivec2(dx, dy);
            if (c.x < 0 || c.y < 0 || c.x >= int(gridSize.x) || c.y >= int(gridSize.y))
                continue;

            vec2 cellCenter = vec2(c) + vec2(0.5);
            float d = distance(cellPos, cellCenter);
            vec4 texel = texelFetch(texture0, c, 0);

            if (mode == 1)
            {
                // living cells + ghosts: "presence" is 1.0 while alive
                // and fades toward 0.0 for a dying cell's afterglow; it
                // scales both the field weight (so ghosts shrink) and
                // the colour mix (so ghosts grey out)
                bool isAlive = texel.r > 0.5;
                float presence = isAlive ? 1.0 : texel.a;
                if (presence > 0.01)
                {
                    float w = falloff(d, blobRadius) * presence;
                    vec3 cellColor = isAlive
                        ? (texel.b > 0.5 ? COLOR_STABLE : COLOR_ALIVE)
                        : mix(COLOR_GHOST, COLOR_ALIVE, presence);
                    colorSum += cellColor * w;
                    totalField += w;
                }
            }
            else
            {
                // soil: shape/presence is NOT weighted by trace strength
                // (any non-zero trace counts fully toward the blob shape),
                // only the final alpha is scaled by trace intensity - this
                // keeps faint, isolated trace patches visible instead of
                // disappearing below the iso-surface threshold. We also
                // remember which single cell dominates locally so zone
                // colours stay sharp instead of blending.
                float traceRaw = texel.g * traceMax;
                if (traceRaw > 0.05)
                {
                    float w = falloff(d, blobRadius);
                    totalField += w;
                    if (w > bestWeight)
                    {
                        bestWeight = w;
                        bestTrace = traceRaw;
                    }
                }
            }
        }
    }

    float alpha = smoothstep(blobThreshold - blobEdge, blobThreshold + blobEdge, totalField);
    if (alpha <= 0.001)
        discard;

    vec3 color;
    if (mode == 1)
    {
        color = totalField > 0.0 ? colorSum / totalField : vec3(0.0);
    }
    else
    {
        if (bestTrace >= exhaustedLevel)
            color = COLOR_EXHAUSTED;
        else if (bestTrace >= fertileLow)
            color = COLOR_FERTILE;
        else
            color = COLOR_NEUTRAL;
        alpha *= clamp(bestTrace / traceMax, 0.0, 1.0);
    }

    finalColor = vec4(color, alpha);
}
`

blob_shader:         rl.Shader
cell_data_texture:   rl.Texture2D
cell_texture_pixels: [WIDTH * HEIGHT * 4]u8

loc_mode:            i32
loc_grid_size:       i32
loc_blob_radius:     i32
loc_blob_threshold:  i32
loc_blob_edge:       i32
loc_trace_max:       i32
loc_fertile_low:     i32
loc_exhausted_level: i32

init_blob_shader :: proc() {
	blob_shader = rl.LoadShaderFromMemory(nil, BLOB_FRAGMENT_SHADER)

	loc_mode = i32(rl.GetShaderLocation(blob_shader, "mode"))
	loc_grid_size = i32(rl.GetShaderLocation(blob_shader, "gridSize"))
	loc_blob_radius = i32(rl.GetShaderLocation(blob_shader, "blobRadius"))
	loc_blob_threshold = i32(rl.GetShaderLocation(blob_shader, "blobThreshold"))
	loc_blob_edge = i32(rl.GetShaderLocation(blob_shader, "blobEdge"))
	loc_trace_max = i32(rl.GetShaderLocation(blob_shader, "traceMax"))
	loc_fertile_low = i32(rl.GetShaderLocation(blob_shader, "fertileLow"))
	loc_exhausted_level = i32(rl.GetShaderLocation(blob_shader, "exhaustedLevel"))

	image := rl.GenImageColor(c.int(WIDTH), c.int(HEIGHT), rl.BLACK)
	defer rl.UnloadImage(image)
	cell_data_texture = rl.LoadTextureFromImage(image)
	rl.SetTextureFilter(cell_data_texture, .POINT)
}

shutdown_blob_shader :: proc() {
	rl.UnloadShader(blob_shader)
	rl.UnloadTexture(cell_data_texture)
}

// packs the current grid state into cell_texture_pixels and uploads it
update_cell_texture :: proc(g: ^Grid) {
	for y := 0; y < HEIGHT; y += 1 {
		for x := 0; x < WIDTH; x += 1 {
			cell := g[y][x]
			i := (y*WIDTH + x) * 4
			cell_texture_pixels[i+0] = 255 if cell.alive else 0
			cell_texture_pixels[i+1] = u8(clamp01(cell.trace/settings.trace_max) * 255)
			cell_texture_pixels[i+2] = 255 if cell.stable_ttl > 0 else 0

			presence: f32
			switch {
			case cell.alive:
				presence = 1.0
			case settings.death_fade_duration > 0:
				presence = clamp01(f32(cell.fade_ttl) / settings.death_fade_duration)
			case:
				presence = 0
			}
			cell_texture_pixels[i+3] = u8(presence * 255)
		}
	}
	rl.UpdateTexture(cell_data_texture, raw_data(cell_texture_pixels[:]))
}

// draws the soil layer and then the living-cells layer (living cells on
// top of soil), both through BLOB_FRAGMENT_SHADER but with independent
// blob parameters, onto whatever render target is currently active
draw_grid_shaded :: proc(g: ^Grid) {
	update_cell_texture(g)

	src := rl.Rectangle{0, 0, f32(WIDTH), f32(HEIGHT)}
	dst := rl.Rectangle{0, 0, f32(GRID_W), f32(GRID_H)}
	grid_size := [2]f32{f32(WIDTH), f32(HEIGHT)}

	rl.SetShaderValue(blob_shader, loc_grid_size, &grid_size, .VEC2)
	rl.SetShaderValue(blob_shader, loc_trace_max, &settings.trace_max, .FLOAT)
	rl.SetShaderValue(blob_shader, loc_fertile_low, &settings.fertile_low, .FLOAT)
	rl.SetShaderValue(blob_shader, loc_exhausted_level, &settings.exhausted_level, .FLOAT)

	rl.BeginShaderMode(blob_shader)

	// soil first, as the background layer
	mode_soil := i32(0)
	rl.SetShaderValue(blob_shader, loc_mode, &mode_soil, .INT)
	rl.SetShaderValue(blob_shader, loc_blob_radius, &settings.soil_blob_radius, .FLOAT)
	rl.SetShaderValue(blob_shader, loc_blob_threshold, &settings.soil_blob_threshold, .FLOAT)
	rl.SetShaderValue(blob_shader, loc_blob_edge, &settings.soil_blob_edge, .FLOAT)
	rl.DrawTexturePro(cell_data_texture, src, dst, {0, 0}, 0, rl.WHITE)

	// living cells (and fading ghosts) drawn on top of the soil
	mode_cells := i32(1)
	rl.SetShaderValue(blob_shader, loc_mode, &mode_cells, .INT)
	rl.SetShaderValue(blob_shader, loc_blob_radius, &settings.cell_blob_radius, .FLOAT)
	rl.SetShaderValue(blob_shader, loc_blob_threshold, &settings.cell_blob_threshold, .FLOAT)
	rl.SetShaderValue(blob_shader, loc_blob_edge, &settings.cell_blob_edge, .FLOAT)
	rl.DrawTexturePro(cell_data_texture, src, dst, {0, 0}, 0, rl.WHITE)

	rl.EndShaderMode()
}

// draws a small marker on every cell that currently holds food, on top
// of the soil and living-cell layers
draw_food_markers :: proc(g: ^Grid) {
	for y := 0; y < HEIGHT; y += 1 {
		for x := 0; x < WIDTH; x += 1 {
			if !g[y][x].food {
				continue
			}
			cx := f32(x*CELL_SIZE) + f32(CELL_SIZE)*0.5
			cy := f32(y*CELL_SIZE) + f32(CELL_SIZE)*0.5
			r := f32(CELL_SIZE) * 0.32
			rl.DrawCircleV({cx, cy}, r, rl.Color{255, 90, 90, 235})
			rl.DrawCircleLines(i32(cx), i32(cy), r, rl.Color{255, 200, 200, 255})
		}
	}
}

// --- microui plumbing ---------------------------------------------------------
//
// Adapted from the official Odin raylib+microui example
// (odin-lang/examples: raylib/microui/microui_raylib_demo.odin).

MuState :: struct {
	ctx:            mu.Context,
	bg:             mu.Color,
	atlas_texture:  rl.RenderTexture2D,
	screen_width:   c.int,
	screen_height:  c.int,
	screen_texture: rl.RenderTexture2D,
}

mu_state := MuState{
	screen_width  = GRID_W + PANEL_WIDTH + 30,
	screen_height = PANEL_HEIGHT + 30,
	bg            = {16, 16, 20, 255},
}

mouse_buttons_map := [mu.Mouse]rl.MouseButton{
	.LEFT   = .LEFT,
	.RIGHT  = .RIGHT,
	.MIDDLE = .MIDDLE,
}

key_map := [mu.Key][2]rl.KeyboardKey{
	.SHIFT     = {.LEFT_SHIFT, .RIGHT_SHIFT},
	.CTRL      = {.LEFT_CONTROL, .RIGHT_CONTROL},
	.ALT       = {.LEFT_ALT, .RIGHT_ALT},
	.BACKSPACE = {.BACKSPACE, .KEY_NULL},
	.DELETE    = {.DELETE, .KEY_NULL},
	.RETURN    = {.ENTER, .KP_ENTER},
	.LEFT      = {.LEFT, .KEY_NULL},
	.RIGHT     = {.RIGHT, .KEY_NULL},
	.HOME      = {.HOME, .KEY_NULL},
	.END       = {.END, .KEY_NULL},
	.A         = {.A, .KEY_NULL},
	.X         = {.X, .KEY_NULL},
	.C         = {.C, .KEY_NULL},
	.V         = {.V, .KEY_NULL},
}

init_microui :: proc() {
	ctx := &mu_state.ctx
	mu.init(ctx,
		set_clipboard = proc(user_data: rawptr, text: string) -> (ok: bool) {
			cstr := strings.clone_to_cstring(text)
			rl.SetClipboardText(cstr)
			delete(cstr)
			return true
		},
		get_clipboard = proc(user_data: rawptr) -> (text: string, ok: bool) {
			cstr := rl.GetClipboardText()
			if cstr != nil {
				text = string(cstr)
				ok = true
			}
			return
		},
	)
	ctx.text_width = mu.default_atlas_text_width
	ctx.text_height = mu.default_atlas_text_height

	mu_state.atlas_texture = rl.LoadRenderTexture(c.int(mu.DEFAULT_ATLAS_WIDTH), c.int(mu.DEFAULT_ATLAS_HEIGHT))

	image := rl.GenImageColor(c.int(mu.DEFAULT_ATLAS_WIDTH), c.int(mu.DEFAULT_ATLAS_HEIGHT), rl.Color{0, 0, 0, 0})
	defer rl.UnloadImage(image)

	for alpha, i in mu.default_atlas_alpha {
		x := i % mu.DEFAULT_ATLAS_WIDTH
		y := i / mu.DEFAULT_ATLAS_WIDTH
		color := rl.Color{255, 255, 255, alpha}
		rl.ImageDrawPixel(&image, c.int(x), c.int(y), color)
	}

	rl.BeginTextureMode(mu_state.atlas_texture)
	rl.UpdateTexture(mu_state.atlas_texture.texture, rl.LoadImageColors(image))
	rl.EndTextureMode()

	mu_state.screen_texture = rl.LoadRenderTexture(mu_state.screen_width, mu_state.screen_height)
}

shutdown_microui :: proc() {
	rl.UnloadRenderTexture(mu_state.atlas_texture)
	rl.UnloadRenderTexture(mu_state.screen_texture)
}

poll_microui_input :: proc(ctx: ^mu.Context) {
	mouse_pos := rl.GetMousePosition()
	mouse_x, mouse_y := i32(mouse_pos.x), i32(mouse_pos.y)
	mu.input_mouse_move(ctx, mouse_x, mouse_y)

	wheel := rl.GetMouseWheelMoveV()
	mu.input_scroll(ctx, i32(wheel.x)*30, i32(wheel.y)*-30)

	for button_rl, button_mu in mouse_buttons_map {
		switch {
		case rl.IsMouseButtonPressed(button_rl):
			mu.input_mouse_down(ctx, mouse_x, mouse_y, button_mu)
		case rl.IsMouseButtonReleased(button_rl):
			mu.input_mouse_up(ctx, mouse_x, mouse_y, button_mu)
		}
	}

	for keys_rl, key_mu in key_map {
		for key_rl in keys_rl {
			switch {
			case key_rl == .KEY_NULL:
			// ignore
			case rl.IsKeyPressed(key_rl), rl.IsKeyPressedRepeat(key_rl):
				mu.input_key_down(ctx, key_mu)
			case rl.IsKeyReleased(key_rl):
				mu.input_key_up(ctx, key_mu)
			}
		}
	}

	{
		buf: [512]byte
		n := 0
		for n < len(buf) {
			ch := rl.GetCharPressed()
			if ch == 0 {
				break
			}
			b, w := utf8.encode_rune(ch)
			n += copy(buf[n:], b[:w])
		}
		mu.input_text(ctx, string(buf[:n]))
	}
}

render :: proc(ctx: ^mu.Context, grid: ^Grid) {
	render_texture :: proc(renderer: rl.RenderTexture2D, dst: ^rl.Rectangle, src: mu.Rect, color: rl.Color) {
		dst.width = f32(src.w)
		dst.height = f32(src.h)
		rl.DrawTextureRec(
			texture  = mu_state.atlas_texture.texture,
			source   = {f32(src.x), f32(src.y), f32(src.w), f32(src.h)},
			position = {dst.x, dst.y},
			tint     = color,
		)
	}

	to_rl_color :: proc(in_color: mu.Color) -> (out_color: rl.Color) {
		return {in_color.r, in_color.g, in_color.b, in_color.a}
	}

	height := rl.GetScreenHeight()

	rl.BeginTextureMode(mu_state.screen_texture)
	rl.EndScissorMode()
	rl.ClearBackground(to_rl_color(mu_state.bg))

	draw_grid_shaded(grid)
	draw_food_markers(grid)

	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(ctx, &command_backing) {
		switch cmd in variant {
		case ^mu.Command_Text:
			dst := rl.Rectangle{f32(cmd.pos.x), f32(cmd.pos.y), 0, 0}
			for ch in cmd.str {
				if ch&0xc0 != 0x80 {
					r := min(int(ch), 127)
					src := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
					render_texture(mu_state.screen_texture, &dst, src, to_rl_color(cmd.color))
					dst.x += dst.width
				}
			}
		case ^mu.Command_Rect:
			rl.DrawRectangle(cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h, to_rl_color(cmd.color))
		case ^mu.Command_Icon:
			src := mu.default_atlas[cmd.id]
			x := cmd.rect.x + (cmd.rect.w-src.w)/2
			y := cmd.rect.y + (cmd.rect.h-src.h)/2
			render_texture(mu_state.screen_texture, &rl.Rectangle{f32(x), f32(y), 0, 0}, src, to_rl_color(cmd.color))
		case ^mu.Command_Clip:
			rl.BeginScissorMode(cmd.rect.x, height-(cmd.rect.y+cmd.rect.h), cmd.rect.w, cmd.rect.h)
		case ^mu.Command_Jump:
			unreachable()
		}
	}

	rl.EndTextureMode()

	rl.BeginDrawing()
	rl.ClearBackground(rl.BLACK)
	rl.DrawTextureRec(
		texture  = mu_state.screen_texture.texture,
		source   = {0, 0, f32(mu_state.screen_width), -f32(mu_state.screen_height)},
		position = {0, 0},
		tint     = rl.WHITE,
	)
	rl.EndDrawing()
}

// --- settings panel content -----------------------------------------------

settings_window :: proc(ctx: ^mu.Context, gen: int) {
	if mu.window(ctx, "Settings", {PANEL_X, PANEL_Y, PANEL_WIDTH, PANEL_HEIGHT}, {.NO_CLOSE}) {
		mu.layout_row(ctx, {-1}, 0)
		mu.label(ctx, fmt.tprintf("Generation: %d", gen))
		mu.label(ctx, "Drag a slider - it applies instantly.")

		mu.layout_row(ctx, {130, -1}, 0)

		mu.label(ctx, "Seed density")
		mu.slider(ctx, &settings.seed_density, 0.05, 0.60, fmt_string = "%.2f")

		mu.label(ctx, "Trace deposit")
		mu.slider(ctx, &settings.trace_deposit, 0.0, 3.0, fmt_string = "%.2f")

		mu.label(ctx, "Trace decay")
		mu.slider(ctx, &settings.trace_decay, 0.50, 0.995, fmt_string = "%.3f")

		mu.label(ctx, "Trace diffusion")
		mu.slider(ctx, &settings.trace_diffuse, 0.0, 0.30, fmt_string = "%.2f")

		mu.label(ctx, "Trace max")
		mu.slider(ctx, &settings.trace_max, 2.0, 20.0, fmt_string = "%.1f")

		mu.label(ctx, "Fertile from")
		mu.slider(ctx, &settings.fertile_low, 0.0, 10.0, fmt_string = "%.2f")

		mu.label(ctx, "Exhausted from")
		mu.slider(ctx, &settings.exhausted_level, 0.0, 20.0, fmt_string = "%.2f")

		mu.label(ctx, "Frames per tick")
		mu.slider(ctx, &settings.step_every_frames, 1.0, 20.0, fmt_string = "%.0f")

		mu.layout_row(ctx, {-1}, 0)
		mu.label(ctx, "-- Fish behaviour --")
		mu.layout_row(ctx, {130, -1}, 0)

		mu.label(ctx, "Lifespan (gen)")
		mu.slider(ctx, &settings.fish_lifespan, 5.0, 200.0, fmt_string = "%.0f")

		mu.label(ctx, "Vision radius")
		mu.slider(ctx, &settings.fish_vision_radius, 1.0, 15.0, fmt_string = "%.0f")

		mu.label(ctx, "Inertia (gen)")
		mu.slider(ctx, &settings.fish_inertia, 0.0, 30.0, fmt_string = "%.0f")

		mu.label(ctx, "Spawn count")
		mu.slider(ctx, &settings.spawn_count, 0.0, 8.0, fmt_string = "%.0f")

		mu.label(ctx, "Well-fed duration")
		mu.slider(ctx, &settings.stable_cell_duration, 1.0, 100.0, fmt_string = "%.0f")

		mu.layout_row(ctx, {-1}, 0)
		mu.label(ctx, "-- Death fade --")
		mu.layout_row(ctx, {130, -1}, 0)

		mu.label(ctx, "Fade duration (gen)")
		mu.slider(ctx, &settings.death_fade_duration, 0.0, 30.0, fmt_string = "%.0f")

		mu.layout_row(ctx, {-1}, 0)
		mu.label(ctx, "-- Living cell blobs --")
		mu.layout_row(ctx, {130, -1}, 0)

		mu.label(ctx, "Blob radius")
		mu.slider(ctx, &settings.cell_blob_radius, 0.5, 3.0, fmt_string = "%.2f")

		mu.label(ctx, "Blob threshold")
		mu.slider(ctx, &settings.cell_blob_threshold, 0.05, 0.90, fmt_string = "%.2f")

		mu.label(ctx, "Blob edge")
		mu.slider(ctx, &settings.cell_blob_edge, 0.01, 0.30, fmt_string = "%.2f")

		mu.layout_row(ctx, {-1}, 0)
		mu.label(ctx, "-- Soil blobs --")
		mu.layout_row(ctx, {130, -1}, 0)

		mu.label(ctx, "Blob radius")
		mu.slider(ctx, &settings.soil_blob_radius, 0.5, 3.0, fmt_string = "%.2f")

		mu.label(ctx, "Blob threshold")
		mu.slider(ctx, &settings.soil_blob_threshold, 0.05, 0.90, fmt_string = "%.2f")

		mu.label(ctx, "Blob edge")
		mu.slider(ctx, &settings.soil_blob_edge, 0.01, 0.30, fmt_string = "%.2f")

		mu.layout_row(ctx, {-1}, 0)
		if .SUBMIT in mu.button(ctx, "Reset to defaults") {
			settings = default_settings
		}

		mu.label(ctx, "Left click: place a well-fed fish.")
		mu.label(ctx, "Right click: place food.")
		mu.label(ctx, "Press R to reseed the field.")
	}
}

main :: proc() {
	rl.InitWindow(mu_state.screen_width, mu_state.screen_height, "Fish with Traces")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	init_microui()
	defer shutdown_microui()
	ctx := &mu_state.ctx

	init_blob_shader()
	defer shutdown_blob_shader()

	a: Grid
	b: Grid
	cur := &a
	nxt := &b
	seed_random(cur)

	gen := 0
	frame := 0

	for !rl.WindowShouldClose() {
		free_all(context.temp_allocator)

		poll_microui_input(ctx)

		mouse_pos := rl.GetMousePosition()
		on_field := mouse_pos.x < f32(GRID_W) && mouse_pos.y < f32(GRID_H)

		// left click: place a well-fed fish. Right click: place food.
		if on_field {
			cx := int(mouse_pos.x) / CELL_SIZE
			cy := int(mouse_pos.y) / CELL_SIZE
			if rl.IsMouseButtonPressed(.LEFT) {
				place_stable_cell(cur, cx, cy)
			}
			if rl.IsMouseButtonPressed(.RIGHT) {
				place_food(cur, cx, cy)
			}
		}

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

		mu.begin(ctx)
		settings_window(ctx, gen)
		mu.end(ctx)

		render(ctx, cur)
	}
}
