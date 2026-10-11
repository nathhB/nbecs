package tests

import ecs ".."
import "core:log"
import "core:testing"

System_Context :: struct {
	value: int,
}

@(test)
systems_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo := ecs.declare(world, Foo)
	bar := ecs.declare(world, Bar)

	e1 := ecs.new(world)
	e2 := ecs.new(world)

	ecs.set(world, e1, &Foo{10})

	ecs.set(world, e2, &Foo{100})
	ecs.set(world, e2, &Bar{200})

	ecs.system(world, system1, ecs.term(world, Foo))
	ecs.system(world, system2, ecs.term(world, Foo), ecs.term(world, Bar))

	ecs.update(world, 0)
	ecs.update(world, 0)

	testing.expect_value(t, ecs.get(world, e1, Foo).v, 40)
	testing.expect_value(t, ecs.get(world, e2, Foo).v, 550)
	testing.expect_value(t, ecs.get(world, e2, Bar).v, 400)
}

@(test)
system_pipelines_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo := ecs.declare(world, Foo)
	pip1 := ecs.pipeline(world, "CustomPipeline1")
	pip2 := ecs.pipeline(world, "CustomPipeline2")

	e1 := ecs.new(world)
	e2 := ecs.new(world)

	ecs.set(world, e1, &Foo{10})
	ecs.set(world, e2, &Foo{100})

	ecs.system(world, system1, ecs.term(world, Foo)) // default pipeline
	ecs.system(world, system3, pip1, ecs.term(world, Foo))
	ecs.system(world, system4, pip2, ecs.term(world, Foo))

	ecs.update(world, 0) // default pipeline

	testing.expect_value(t, ecs.get(world, e1, Foo).v, 20)
	testing.expect_value(t, ecs.get(world, e2, Foo).v, 200)

	ecs.update(world, 0, pip1)

	testing.expect_value(t, ecs.get(world, e1, Foo).v, 25)
	testing.expect_value(t, ecs.get(world, e2, Foo).v, 205)

	ecs.update(world, 0, pip2)

	testing.expect_value(t, ecs.get(world, e1, Foo).v, 15)
	testing.expect_value(t, ecs.get(world, e2, Foo).v, 195)
}

@(test)
system_contexts_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	ctx1 := System_Context{20}
	ctx2 := System_Context{40}

	ecs.system(world, system5, &ctx1)
	ecs.system(world, system6, &ctx2)

	log_debug_world(world)

	ecs.update(world, 0)
	ecs.update(world, 0)

	testing.expect_value(t, ctx1.value, 2000)
	testing.expect_value(t, ctx2.value, 400_000)
}

@(test)
systems_query_str_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo := ecs.declare(world, Foo, "Foo")
	bar := ecs.declare(world, Bar, "Bar")

	e1 := ecs.new(world)
	e2 := ecs.new(world)

	ecs.set(world, e1, &Foo{10})

	ecs.set(world, e2, &Foo{100})
	ecs.set(world, e2, &Bar{200})

	ecs.system(world, system1, "Foo")
	ecs.system(world, system2, "Foo Bar")

	ecs.update(world, 0)
	ecs.update(world, 0)

	testing.expect_value(t, ecs.get(world, e1, Foo).v, 40)
	testing.expect_value(t, ecs.get(world, e2, Foo).v, 550)
	testing.expect_value(t, ecs.get(world, e2, Bar).v, 400)
}

@(test)
system_pipelines_str_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo := ecs.declare(world, Foo, "Foo")
	pip1 := ecs.pipeline(world, "CustomPipeline1")
	pip2 := ecs.pipeline(world, "CustomPipeline2")

	e1 := ecs.new(world)
	e2 := ecs.new(world)

	ecs.set(world, e1, &Foo{10})
	ecs.set(world, e2, &Foo{100})

	ecs.system(world, system1, "Foo") // default pipeline
	ecs.system(world, system3, pip1, "Foo")
	ecs.system(world, system4, pip2, "Foo")

	ecs.update(world, 0) // default pipeline

	testing.expect_value(t, ecs.get(world, e1, Foo).v, 20)
	testing.expect_value(t, ecs.get(world, e2, Foo).v, 200)

	ecs.update(world, 0, pip1)

	testing.expect_value(t, ecs.get(world, e1, Foo).v, 25)
	testing.expect_value(t, ecs.get(world, e2, Foo).v, 205)

	ecs.update(world, 0, pip2)

	testing.expect_value(t, ecs.get(world, e1, Foo).v, 15)
	testing.expect_value(t, ecs.get(world, e2, Foo).v, 195)
}

system1 :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	foo_col := ecs.column(it, 0)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < chunk.count; row += 1 {
			foo := ecs.get_mut(chunk, foo_col, row, Foo)

			foo.v *= 2
		}
	}

	return true
}

system2 :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	foo_col := ecs.column(it, 0)
	bar_col := ecs.column(it, 1)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < chunk.count; row += 1 {
			foo := ecs.get_mut(chunk, foo_col, row, Foo)
			bar := ecs.get_mut(chunk, bar_col, row, Bar)

			foo.v += 50
			bar.v += 100
		}
	}

	return true
}

system3 :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	foo_col := ecs.column(it, 0)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < chunk.count; row += 1 {
			foo := ecs.get_mut(chunk, foo_col, row, Foo)

			foo.v += 5
		}
	}

	return true
}

system4 :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	foo_col := ecs.column(it, 0)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < chunk.count; row += 1 {
			foo := ecs.get_mut(chunk, foo_col, row, Foo)

			foo.v -= 10
		}
	}

	return true
}

system5 :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	system_ctx := (^System_Context)(ctx)

	system_ctx.value *= 10
	return true
}

system6 :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	system_ctx := (^System_Context)(ctx)

	system_ctx.value *= 100
	return true
}

