package mq72

Position :: struct {
	x,y,z : i32
}

Velocity :: struct {
	dx, dy, dz : f32
}

Rotation :: struct {
	//Later
}

Sprite :: struct {
	// An id from local asset manager
	// It can change between runs. Need a better approach
	id : i16
}

Health :: struct {
	current: f32,
	max: f32
}

CircleSprite :: struct {}

Grid_Position :: struct {
	x, y: i32
}
