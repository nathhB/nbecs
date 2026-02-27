package benchmark_single_system

import ecs "../.."
import "core:log"
import rand "core:math/rand"
import "core:time"

world: ^ecs.World
Warmup_Rounds :: 10
Entity_Count :: 1_000_000

Position :: struct {
	x: int,
	y: int,
}

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

Health_Status :: enum {
	Dead,
	Alive,
	Spawn,
}

main :: proc() {
	context.logger = log.create_console_logger()
	options := time.Benchmark_Options{}

	options.setup = ecs_setup
	options.teardown = ecs_teardown
	options.bench = ecs_benchmark
	options.rounds = 1

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

ecs_setup :: proc(
	options: ^time.Benchmark_Options,
	allocator := context.allocator,
) -> time.Benchmark_Error {
	world = ecs.ecs_create()

	ecs.ecs_declare(world, Position, "Position")
	ecs.ecs_declare(world, Velocity, "Velocity")
	ecs.ecs_declare(world, Damage, "Damage")
	ecs.ecs_declare(world, Health, "Health")
	ecs.ecs_declare(world, Data, "Data")

	ecs.ecs_system(world, move, nil, "Position Velocity")
	ecs.ecs_system(world, damage, nil, "Health Damage")
	ecs.ecs_system(world, health, nil, "Health")
	ecs.ecs_system(world, data, nil, "Data")
	ecs.ecs_system(world, move, nil, "Position Velocity")
	ecs.ecs_system(world, move, nil, "Position Velocity")
	ecs.ecs_system(world, move, nil, "Position Velocity")

	for j := 0; j < Entity_Count; j += 1 {
		entity := ecs.ecs_new(world)

		ecs.ecs_set(world, entity, &Position{0, 0})
		ecs.ecs_set(world, entity, &Velocity{1, 0})
		ecs.ecs_set(world, entity, &Damage{10, 5})
		ecs.ecs_set(world, entity, &Health{100, 100, .Alive})
		ecs.ecs_set(world, entity, &Data{})
	}

	// do a few warmup rounds
	for i := 0; i < Warmup_Rounds; i += 1 {
		ecs_benchmark(options, allocator)
	}

	return time.Benchmark_Error.Okay
}

ecs_teardown :: proc(
	options: ^time.Benchmark_Options,
	allocator := context.allocator,
) -> time.Benchmark_Error {
	ecs.ecs_destroy(world)

	return time.Benchmark_Error.Okay
}

ecs_benchmark :: proc(
	options: ^time.Benchmark_Options,
	allocator := context.allocator,
) -> time.Benchmark_Error {
	for i := 0; i < options.rounds; i += 1 {
		ecs.ecs_update(world, 0.016)
	}

	return time.Benchmark_Error.Okay
}

move :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	pos_col := ecs.column(it, 0)
	vel_col := ecs.column(it, 1)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < len(chunk.entities); row += 1 {
			pos := ecs.row_data_mut(pos_col, row, Position)
			vel := ecs.row_data(vel_col, row, Velocity)

			pos.x += vel.x
			pos.y += vel.y
		}
	}

	return true
}

damage :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	damage_col := ecs.column(it, 0)
	health_col := ecs.column(it, 1)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < len(chunk.entities); row += 1 {
			health := ecs.row_data_mut(health_col, row, Health)
			damage := ecs.row_data(health_col, row, Damage)

			total_dmg := damage.atk - damage.def

			if health.hp > 0 && total_dmg > 0 {
				health.hp -= max(health.hp - total_dmg, 0)
			}
		}
	}

	return true
}

health :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	health_col := ecs.column(it, 0)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < len(chunk.entities); row += 1 {
			health := ecs.row_data_mut(health_col, row, Health)

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
	data_col := ecs.column(it, 0)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < len(chunk.entities); row += 1 {
			data := ecs.row_data_mut(data_col, row, Data)

			data.thingy = data.thingy + 1 % 1_000_000
			data.dingy += 0.0001 * dt
			data.mingy = !data.mingy
			data.numgy = rand.int31()
		}
	}

	return true
}
