package main

// ============================================================================
// Game of Life with traces — raylib rendering, microui settings panel,
// SDF metaball shader.
//
// Every cell has, besides its alive/dead state, a "trace" level: an
// accumulated artefact of past life at that spot. Living cells deposit
// trace, it decays over time and diffuses a little into neighbouring
// cells. The trace level defines one of three kinds of "soil": neutral /
// fertile (better odds of survival and birth) / exhausted (odds collapse).
// Good soil raises the odds but never guarantees the outcome — the result
// is always decided by a dice roll, capped below 100% (see
// survival_chance / birth_chance and settings.max_chance).
//
// When a living cell dies it does not vanish immediately: it lingers as
// a fading "ghost" for settings.death_fade_duration generations, turning
// increasingly grey and transparent until it disappears completely (see
// Cell.fade_ttl and the mode == 1 branch of the shader below). A ghost
// does not count as alive for any simulation rule — it is a purely
// visual echo of where something used to live.
//
// Rendering is done by a single fragment shader (BLOB_FRAGMENT_SHADER)
// applied twice per frame with different parameters — once for the soil
// layer (background), once for the living cells + ghosts layer (drawn on
// top). Cell state is packed into a small WIDTH x HEIGHT data texture
// (R = alive, G = normalised trace, B = stable-cell flag, A = "presence"
// used for ghost fading) and the shader treats each relevant cell as a
// soft "metaball": for every pixel it sums a smooth distance falloff
// over the neighbouring cells and thresholds the result, giving that
// soft, merging blob look instead of hard grid squares. The soil and
// cell layers have their own independent radius/threshold/edge settings,
// since a good look for one is usually a bad look for the other. Soil
// zone colours stay sharp (the shader always uses the single dominant
// cell's colour, only the outline is blobby); living cells blend colour
// smoothly across a blob depending on how much of it is alive, stable,
// or a fading ghost.
//
// A left click on the field places a "stable cell": it is forced alive
// and immune to the usual rules for settings.stable_cell_duration
// generations, after which it reverts to normal probabilistic rules. It
// still counts as an ordinary living neighbour to surrounding cells the
// whole time, and is rendered with a golden glow proportional to how
// much a given blob is made of stable cells.
//
// Every parameter that affects the field or the blob look is exposed as
// a slider in the microui panel on the right and applies immediately.
//
// Controls: mouse — drag sliders, click the field to place a stable
// cell; R — reseed the field; Esc / closing the window — quit.
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
PANEL_HEIGHT :: 850

GENERATIONS_PER_EPOCH :: 500 // the field reseeds itself after this many generations

// --- Tunable settings ---------------------------------------------------------
//
// Everything that affects the behaviour of the field, or the look of the
// metaball shader, lives here and is edited live through the panel on
// the right.

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
	step_every_frames:    f32, // rounded to int when used
	stable_cell_duration: f32, // N generations of guaranteed survival, rounded to int
	death_fade_duration:  f32, // N generations a dead cell lingers as a fading ghost

	cell_blob_radius:    f32, // living-cell metaball influence radius, in cell units
	cell_blob_threshold: f32, // living-cell iso-surface threshold
	cell_blob_edge:      f32, // living-cell smoothstep softness around the threshold

	soil_blob_radius:    f32, // soil metaball influence radius, in cell units
	soil_blob_threshold: f32, // soil iso-surface threshold
	soil_blob_edge:      f32, // soil smoothstep softness around the threshold
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
	stable_cell_duration = 15,
	death_fade_duration  = 8,

	cell_blob_radius    = 1.7,  // fairly large: neighbouring cells merge generously
	cell_blob_threshold = 0.45,
	cell_blob_edge      = 0.10,

	soil_blob_radius    = 1.4,
	soil_blob_threshold = 0.20, // low: even a single lightly-traced cell stays visible
	soil_blob_edge      = 0.15,
}

settings := default_settings

// --- Simulation data ------------------------------------------------------

Cell :: struct {
	alive:      bool,
	trace:      f32,
	stable_ttl: int, // remaining generations of guaranteed survival (0 = normal rules)
	fade_ttl:   int, // remaining generations a dead cell is shown as a fading ghost
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

// odds of survival for an already-living cell: depends on neighbour
// count and soil quality, but never reaches 100% (see settings.max_chance)
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

// odds of birth for a dead cell: same idea, applied to birth rules
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

			alive: bool
			ttl: int
			if cell.stable_ttl > 0 {
				// a stable cell survives unconditionally while its
				// lifespan lasts, regardless of neighbours or soil
				alive = true
				ttl = cell.stable_ttl - 1
			} else {
				alive = next_state(cell.alive, n, cell.trace)
			}

			fade: int
			switch {
			case alive:
				fade = 0 // alive cells never carry a ghost countdown
			case cell.alive:
				// just died this generation: start the fade-out countdown
				fade = int(settings.death_fade_duration + 0.5)
			case cell.fade_ttl > 0:
				fade = cell.fade_ttl - 1
			case:
				fade = 0
			}

			trace := cell.trace
			if cell.alive {
				trace += settings.trace_deposit
			}
			trace *= settings.trace_decay
			trace = trace*(1 - settings.trace_diffuse) + neighbor_trace_avg(cur, x, y)*settings.trace_diffuse
			if trace > settings.trace_max {
				trace = settings.trace_max
			}

			nxt[y][x] = Cell{alive = alive, trace = trace, stable_ttl = ttl, fade_ttl = fade}
		}
	}
}

seed_random :: proc(g: ^Grid) {
	for y := 0; y < HEIGHT; y += 1 {
		for x := 0; x < WIDTH; x += 1 {
			g[y][x] = Cell{alive = rand.float32() < settings.seed_density, trace = 0, stable_ttl = 0, fade_ttl = 0}
		}
	}
}

// places a stable cell at grid coordinates (x, y): it will survive with
// 100% certainty for settings.stable_cell_duration generations, and
// counts as an ordinary living neighbour to surrounding cells the whole
// time
place_stable_cell :: proc(g: ^Grid, x, y: int) {
	if x < 0 || x >= WIDTH || y < 0 || y >= HEIGHT {
		return
	}
	g[y][x].alive = true
	g[y][x].stable_ttl = int(settings.stable_cell_duration + 0.5)
	g[y][x].fade_ttl = 0
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
//   B = stable-cell flag (0/255)
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


	rl.EndShaderMode()

	rl.BeginShaderMode(blob_shader)
	// living cells (and fading ghosts) drawn on top of the soil
	mode_cells := i32(1)
	rl.SetShaderValue(blob_shader, loc_mode, &mode_cells, .INT)
	rl.SetShaderValue(blob_shader, loc_blob_radius, &settings.cell_blob_radius, .FLOAT)
	rl.SetShaderValue(blob_shader, loc_blob_threshold, &settings.cell_blob_threshold, .FLOAT)
	rl.SetShaderValue(blob_shader, loc_blob_edge, &settings.cell_blob_edge, .FLOAT)
	rl.DrawTexturePro(cell_data_texture, src, dst, {0, 0}, 0, rl.WHITE)

	rl.EndShaderMode()
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

		mu.label(ctx, "Fertile to")
		mu.slider(ctx, &settings.fertile_high, 0.0, 15.0, fmt_string = "%.2f")

		mu.label(ctx, "Exhausted from")
		mu.slider(ctx, &settings.exhausted_level, 0.0, 20.0, fmt_string = "%.2f")

		mu.label(ctx, "Survival chance")
		mu.slider(ctx, &settings.base_survival_chance, 0.0, 1.0, fmt_string = "%.2f")

		mu.label(ctx, "Birth chance")
		mu.slider(ctx, &settings.base_birth_chance, 0.0, 1.0, fmt_string = "%.2f")

		mu.label(ctx, "Fertile bonus")
		mu.slider(ctx, &settings.fertile_bonus, 0.0, 0.50, fmt_string = "%.2f")

		mu.label(ctx, "Fertile extra")
		mu.slider(ctx, &settings.fertile_extra_chance, 0.0, 1.0, fmt_string = "%.2f")

		mu.label(ctx, "Exhausted mult.")
		mu.slider(ctx, &settings.exhausted_mult, 0.0, 1.0, fmt_string = "%.2f")

		mu.label(ctx, "Rare event")
		mu.slider(ctx, &settings.rare_exhausted_event, 0.0, 0.50, fmt_string = "%.2f")

		mu.label(ctx, "Chance ceiling")
		mu.slider(ctx, &settings.max_chance, 0.50, 1.0, fmt_string = "%.2f")

		mu.label(ctx, "Frames per tick")
		mu.slider(ctx, &settings.step_every_frames, 1.0, 20.0, fmt_string = "%.0f")

		mu.label(ctx, "Stable cell life")
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
		mu.slider(ctx, &settings.cell_blob_radius, 0.0, 3.0, fmt_string = "%.2f")

		mu.label(ctx, "Blob threshold")
		mu.slider(ctx, &settings.cell_blob_threshold, 0.0, 1.0, fmt_string = "%.2f")

		mu.label(ctx, "Blob edge")
		mu.slider(ctx, &settings.cell_blob_edge, 0.0, 1.0, fmt_string = "%.2f")

		mu.layout_row(ctx, {-1}, 0)
		mu.label(ctx, "-- Soil blobs --")
		mu.layout_row(ctx, {130, -1}, 0)

		mu.label(ctx, "Blob radius")
		mu.slider(ctx, &settings.soil_blob_radius, 0.0, 3.0, fmt_string = "%.2f")

		mu.label(ctx, "Blob threshold")
		mu.slider(ctx, &settings.soil_blob_threshold, 0.0, 1.0, fmt_string = "%.2f")

		mu.label(ctx, "Blob edge")
		mu.slider(ctx, &settings.soil_blob_edge, 0.01, 1.0, fmt_string = "%.2f")

		mu.layout_row(ctx, {-1}, 0)
		if .SUBMIT in mu.button(ctx, "Reset to defaults") {
			settings = default_settings
		}

		mu.label(ctx, "Click the field to place a stable cell.")
		mu.label(ctx, "Press R to reseed the field.")
	}
}

main :: proc() {
	rl.InitWindow(mu_state.screen_width, mu_state.screen_height, "Game of Life with Traces")
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

		// a left click on the field (outside the microui panel) places a
		// stable cell that survives unconditionally for N generations
		mouse_pos := rl.GetMousePosition()
		// if rl.IsMouseButtonPressed(.LEFT) && mouse_pos.x < f32(GRID_W) && mouse_pos.y < f32(GRID_H) {
		// 	cx := int(mouse_pos.x) / CELL_SIZE
		// 	cy := int(mouse_pos.y) / CELL_SIZE
		// 	place_stable_cell(cur, cx, cy)
		// }

		if rl.IsMouseButtonDown(.LEFT) && mouse_pos.x < f32(GRID_W) && mouse_pos.y < f32(GRID_H) {
			cx := int(mouse_pos.x) / CELL_SIZE
			cy := int(mouse_pos.y) / CELL_SIZE
			place_stable_cell(cur, cx, cy)
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
