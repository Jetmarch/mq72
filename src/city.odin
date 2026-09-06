package mq72


City :: struct {
	goods: [dynamic]Goods,
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
