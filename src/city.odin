package mq72

Faction_ID :: struct {
	id: i32,
}

City_ID :: struct {
	id: i32,
}

City :: struct {
	id:      i32,
	goods:   [dynamic]Goods,
	economy: City_Economy,
}

Road :: struct {
	from_city: City_ID,
	to_city:   City_ID,
	capacity:  i32,
	distance:  i32,
}

City_Economy :: struct {
	population: i32,
}

MAX_REQUIRED_RESOURCES_PER_PRODUCTION :: 4

Production :: struct {
	outcome_type:             Resource_Type,
	outcome:                  i32,
	required_resources:       [MAX_REQUIRED_RESOURCES_PER_PRODUCTION]Required_Resource,
	required_resource_amount: u8,
}

Required_Resource :: struct {
	type:   Resource_Type,
	amount: i32,
}

Resource_Type :: enum byte {
	Garbage,
	Provision,
	Ammunition,
	Machinery,
	Weaponry,
}

Goods :: struct {
	goods_type:       Goods_Type,
	income_per_turn:  i32,
	outcome_per_turn: i32,
}

Goods_Type :: enum byte {
	Garbage,
	Provision,
	Ammunition,
	Machinery,
	Weaponry,
}
