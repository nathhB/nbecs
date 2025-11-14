package benchmark

import "core:time"
import "core:log"
import ecs ".."

world: ^ecs.World
WarmupRounds :: 10
InitialEntities :: 16_000

Position :: struct {
    x: int,
    y: int
}

Velocity :: struct {
    x: int,
    y: int
}

Data :: struct {
    foo: int,
    bar: f64,
    plop: bool
}

main :: proc() {
    context.logger = log.create_console_logger()
    options := time.Benchmark_Options{}

    options.setup = ecs_setup
    options.teardown = ecs_teardown
    options.bench = ecs_benchmark
    options.rounds = 10

    time.benchmark(&options)

    avg_round_duration_us := time.duration_microseconds(options.duration) / f64(options.rounds)
    log.infof("Rounds: %d, Total time: %d, Avg round time (us): %f", options.rounds, options.duration,
        avg_round_duration_us)
}

ecs_setup :: proc(options: ^time.Benchmark_Options, allocator := context.allocator) -> time.Benchmark_Error {
    world = ecs.ecs_create()

    ecs.ecs_declare(world, Position)
    ecs.ecs_declare(world, Velocity)

    ecs.ecs_system(world, move, ecs.query_term(world, Position), ecs.query_term(world, Velocity))

    for j := 0; j < InitialEntities; j += 1 {
        entity := ecs.ecs_new(world)

        ecs.ecs_set(world, entity, &Position{0, 0})
        ecs.ecs_set(world, entity, &Velocity{1, 0})
    }

    // do a few warmup rounds
    for i := 0; i < WarmupRounds; i += 1 {
        ecs_benchmark(options, allocator)
    } 

    return time.Benchmark_Error.Okay
}

ecs_teardown :: proc(options: ^time.Benchmark_Options, allocator := context.allocator) -> time.Benchmark_Error {
    ecs.ecs_destroy(world)

    return time.Benchmark_Error.Okay
}

ecs_benchmark :: proc(options: ^time.Benchmark_Options, allocator := context.allocator) -> time.Benchmark_Error {
    for i := 0; i < options.rounds; i += 1 {
        ecs.ecs_update(world, 0)
    }

    return time.Benchmark_Error.Okay
}

move :: proc(world: ^ecs.World, it: ^ecs.QueryIterator, dt: f64) -> bool {
    pos_col := ecs.query_column(it, 0, Position)
    vel_col := ecs.query_column(it, 1, Velocity)

    for entity in ecs.query_iter_next_entity(it) {
        pos := ecs.query_entity_data_mut(it, pos_col, Position)
        vel := ecs.query_entity_data(it, vel_col, Velocity)

        pos.x += vel.x
        pos.y += vel.y
    }

    return true
}
