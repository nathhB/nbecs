package benchmark_single_system

import ecs "../.."
import "core:log"
import rand "core:math/rand"
import "core:time"

world: ^ecs.World
Warmup_Rounds :: 10
Benchmark_Rounds :: 1
Entity_Count :: 1_000_000

Position :: [2]int

Velocity :: struct {
	x: int,
	y: int,
}

Health :: struct {
	hp:     int,
	max_hp: int,
	status: Health_Status,
}

Damage :: struct {
	atk: int,
	def: int,
}

Data :: struct {
	thingy: int,
	dingy:  f64,
	mingy:  bool,
	numgy:  i32,
}

Player :: struct {
	type: Player_Type,
}

Sprite :: struct {
	sprite: u8,
}

Health_Status :: enum {
	Dead,
	Alive,
	Spawn,
}

Player_Type :: enum {
	NPC,
	Monster,
	Hero,
}

Context :: struct {
	move_process_count:   int,
	damage_process_count: int,
	health_process_count: int,
	data_process_count:   int,
	sprite_process_count: int,
	render_process_count: int,
}

main :: proc() {
	context.logger = log.create_console_logger()
	options := time.Benchmark_Options{}

	options.setup = setup
	options.teardown = teardown
	options.bench = benchmark
	options.rounds = Benchmark_Rounds

	time.benchmark(&options)

	avg_round_duration_us := time.duration_microseconds(options.duration) / f64(options.rounds)
	log.infof(
		"Rounds: %d, Entities: %d, Total time: %d, Avg round time (us): %f",
		options.rounds,
		Entity_Count,
		options.duration,
		avg_round_duration_us,
	)
}

setup :: proc(
	options: ^time.Benchmark_Options,
	allocator := context.allocator,
) -> time.Benchmark_Error {
	world = ecs.create()

	ecs.declare(world, Position, "Position")
	ecs.declare(world, Velocity, "Velocity")
	ecs.declare(world, Damage, "Damage")
	ecs.declare(world, Health, "Health")
	ecs.declare(world, Data, "Data")
	ecs.declare(world, Player, "Player")
	ecs.declare(world, Sprite, "Sprite")

	ecs.system(world, move, nil, "Position Velocity")
	ecs.system(world, damage, nil, "Health Damage")
	ecs.system(world, health, nil, "Health")
	ecs.system(world, data, nil, "Data")
	ecs.system(world, sprite, nil, "Sprite Player Health")
	ecs.system(world, render, nil, "Sprite Position")
	// ecs.system(world, move, nil, "Position Velocity")

	for j := 0; j < Entity_Count; j += 1 {
		entity := ecs.new(world)

		ecs.set(world, entity, &Position{0, 0})
		ecs.set(world, entity, &Velocity{1, 0})
		ecs.set(world, entity, &Damage{10, 5})
		ecs.set(world, entity, &Health{100, 100, .Alive})
		ecs.set(world, entity, &Data{})
		ecs.set(world, entity, &Player{.Hero})
		ecs.set(world, entity, &Sprite{})
	}

	// do a few warmup rounds
	for i := 0; i < Warmup_Rounds; i += 1 {
		benchmark(options, allocator)
	}

	return time.Benchmark_Error.Okay
}

teardown :: proc(
	options: ^time.Benchmark_Options,
	allocator := context.allocator,
) -> time.Benchmark_Error {
	ecs.destroy(world)

	return time.Benchmark_Error.Okay
}

benchmark :: proc(
	options: ^time.Benchmark_Options,
	allocator := context.allocator,
) -> time.Benchmark_Error {
	for i := 0; i < options.rounds; i += 1 {
		ctx := Context{}
		ecs.set_context(world, &ctx)
		ecs.update(world, 0.016)
		assert(ctx.move_process_count == Entity_Count)
		assert(ctx.damage_process_count == Entity_Count)
		assert(ctx.health_process_count == Entity_Count)
		assert(ctx.data_process_count == Entity_Count)
		assert(ctx.sprite_process_count == Entity_Count)
		assert(ctx.render_process_count == Entity_Count)
	}

	return time.Benchmark_Error.Okay
}

move :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	ctx := (^Context)(world.ctx)
	pos_col := ecs.column(it, 0)
	vel_col := ecs.column(it, 1)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < len(chunk.entities); row += 1 {
			ctx.move_process_count += 1

			pos := ecs.row_data_mut(chunk, pos_col, row, Position)
			vel := ecs.row_data(chunk, vel_col, row, Velocity)

			pos.x += vel.x
			pos.y += vel.y
		}
	}

	return true
}

damage :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	ctx := (^Context)(world.ctx)
	damage_col := ecs.column(it, 0)
	health_col := ecs.column(it, 1)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < len(chunk.entities); row += 1 {
			ctx.damage_process_count += 1

			health := ecs.row_data_mut(chunk, health_col, row, Health)
			damage := ecs.row_data(chunk, health_col, row, Damage)

			total_dmg := damage.atk - damage.def

			if health.hp > 0 && total_dmg > 0 {
				health.hp -= max(health.hp - total_dmg, 0)
			}
		}
	}

	return true
}

health :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	ctx := (^Context)(world.ctx)
	health_col := ecs.column(it, 0)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < len(chunk.entities); row += 1 {
			ctx.health_process_count += 1

			health := ecs.row_data_mut(chunk, health_col, row, Health)

			if health.hp <= 0 && health.status != .Dead {
				health.status = .Dead
			} else if health.hp <= 0 && health.status == .Dead {
				health.status = .Spawn
				health.hp = health.max_hp
			} else if health.hp >= health.max_hp && health.status != .Alive {
				health.status = .Alive
			} else {
				health.status = .Alive
			}
		}
	}

	return true
}

data :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	ctx := (^Context)(world.ctx)
	data_col := ecs.column(it, 0)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < len(chunk.entities); row += 1 {
			ctx.data_process_count += 1

			data := ecs.row_data_mut(chunk, data_col, row, Data)

			data.thingy = data.thingy + 1 % Entity_Count
			data.dingy += 0.0001 * dt
			data.mingy = !data.mingy
			data.numgy = rand.int31()
		}
	}

	return true
}

sprite :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	ctx := (^Context)(world.ctx)
	sprite_col := ecs.column(it, 0)
	player_col := ecs.column(it, 1)
	health_col := ecs.column(it, 2)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < len(chunk.entities); row += 1 {
			ctx.sprite_process_count += 1

			player := ecs.row_data(chunk, player_col, row, Player)
			health := ecs.row_data(chunk, health_col, row, Health)
			sprite := ecs.row_data_mut(chunk, sprite_col, row, Sprite)

			switch health.status {
			case .Alive:
				switch player.type {
				case .NPC:
					sprite.sprite = 'N'
				case .Monster:
					sprite.sprite = 'M'
				case .Hero:
					sprite.sprite = 'H'
				}
			case .Spawn:
				sprite.sprite = 'S'
			case .Dead:
				sprite.sprite = 'D'
			}
		}
	}

	return true
}

render :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	ctx := (^Context)(world.ctx)
	sprite_col := ecs.column(it, 0)
	pos_col := ecs.column(it, 1)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < len(chunk.entities); row += 1 {
			ctx.render_process_count += 1

			sprite := ecs.row_data(chunk, sprite_col, row, Sprite)
			pos := ecs.row_data(chunk, pos_col, row, Position)
		}
	}

	return true
}
