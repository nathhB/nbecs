package tests

import ecs ".."
import "core:log"
import "core:testing"

System_Context :: struct {
	value: int,
}

@(test)
systems_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo := ecs.ecs_declare(world, Foo)
	bar := ecs.ecs_declare(world, Bar)

	e1 := ecs.ecs_new(world)
	e2 := ecs.ecs_new(world)

	ecs.ecs_set(world, e1, &Foo{10})

	ecs.ecs_set(world, e2, &Foo{100})
	ecs.ecs_set(world, e2, &Bar{200})

	ecs.ecs_system(world, system1, ecs.query_term(world, Foo))
	ecs.ecs_system(world, system2, ecs.query_term(world, Foo), ecs.query_term(world, Bar))

	ecs.ecs_update(world, 0)
	ecs.ecs_update(world, 0)

	testing.expect_value(t, ecs.ecs_get(world, e1, Foo).v, 40)
	testing.expect_value(t, ecs.ecs_get(world, e2, Foo).v, 550)
	testing.expect_value(t, ecs.ecs_get(world, e2, Bar).v, 400)
}

@(test)
system_pipelines_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo := ecs.ecs_declare(world, Foo)
	pip1 := ecs.ecs_pipeline(world, "CustomPipeline1")
	pip2 := ecs.ecs_pipeline(world, "CustomPipeline2")

	e1 := ecs.ecs_new(world)
	e2 := ecs.ecs_new(world)

	ecs.ecs_set(world, e1, &Foo{10})
	ecs.ecs_set(world, e2, &Foo{100})

	ecs.ecs_system(world, system1, ecs.query_term(world, Foo)) // default pipeline
	ecs.ecs_system(world, system3, pip1, ecs.query_term(world, Foo))
	ecs.ecs_system(world, system4, pip2, ecs.query_term(world, Foo))

	ecs.ecs_update(world, 0) // default pipeline

	testing.expect_value(t, ecs.ecs_get(world, e1, Foo).v, 20)
	testing.expect_value(t, ecs.ecs_get(world, e2, Foo).v, 200)

	ecs.ecs_update(world, 0, pip1)

	testing.expect_value(t, ecs.ecs_get(world, e1, Foo).v, 25)
	testing.expect_value(t, ecs.ecs_get(world, e2, Foo).v, 205)

	ecs.ecs_update(world, 0, pip2)

	testing.expect_value(t, ecs.ecs_get(world, e1, Foo).v, 15)
	testing.expect_value(t, ecs.ecs_get(world, e2, Foo).v, 195)
}

@(test)
system_contexts_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	ctx1 := System_Context{20}
	ctx2 := System_Context{40}

	ecs.ecs_system(world, system5, &ctx1)
	ecs.ecs_system(world, system6, &ctx2)

	log_debug_world(world)

	ecs.ecs_update(world, 0)
	ecs.ecs_update(world, 0)

	testing.expect_value(t, ctx1.value, 2000)
	testing.expect_value(t, ctx2.value, 400_000)
}

@(test)
systems_query_str_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo := ecs.ecs_declare(world, Foo, "Foo")
	bar := ecs.ecs_declare(world, Bar, "Bar")

	e1 := ecs.ecs_new(world)
	e2 := ecs.ecs_new(world)

	ecs.ecs_set(world, e1, &Foo{10})

	ecs.ecs_set(world, e2, &Foo{100})
	ecs.ecs_set(world, e2, &Bar{200})

	ecs.ecs_system(world, system1, "Foo")
	ecs.ecs_system(world, system2, "Foo Bar")

	ecs.ecs_update(world, 0)
	ecs.ecs_update(world, 0)

	testing.expect_value(t, ecs.ecs_get(world, e1, Foo).v, 40)
	testing.expect_value(t, ecs.ecs_get(world, e2, Foo).v, 550)
	testing.expect_value(t, ecs.ecs_get(world, e2, Bar).v, 400)
}

@(test)
system_pipelines_str_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo := ecs.ecs_declare(world, Foo, "Foo")
	pip1 := ecs.ecs_pipeline(world, "CustomPipeline1")
	pip2 := ecs.ecs_pipeline(world, "CustomPipeline2")

	e1 := ecs.ecs_new(world)
	e2 := ecs.ecs_new(world)

	ecs.ecs_set(world, e1, &Foo{10})
	ecs.ecs_set(world, e2, &Foo{100})

	ecs.ecs_system(world, system1, "Foo") // default pipeline
	ecs.ecs_system(world, system3, pip1, "Foo")
	ecs.ecs_system(world, system4, pip2, "Foo")

	ecs.ecs_update(world, 0) // default pipeline

	testing.expect_value(t, ecs.ecs_get(world, e1, Foo).v, 20)
	testing.expect_value(t, ecs.ecs_get(world, e2, Foo).v, 200)

	ecs.ecs_update(world, 0, pip1)

	testing.expect_value(t, ecs.ecs_get(world, e1, Foo).v, 25)
	testing.expect_value(t, ecs.ecs_get(world, e2, Foo).v, 205)

	ecs.ecs_update(world, 0, pip2)

	testing.expect_value(t, ecs.ecs_get(world, e1, Foo).v, 15)
	testing.expect_value(t, ecs.ecs_get(world, e2, Foo).v, 195)
}

system1 :: proc(world: ^ecs.World, it: ^ecs.QueryIterator, dt: f64, ctx: rawptr) -> bool {
	foo_col := ecs.query_column_index(it, 0)

	for entity in ecs.query_iter_next_entity(it) {
		foo := ecs.query_entity_data_mut(it, foo_col, Foo)

		foo.v *= 2
	}

	return true
}

system2 :: proc(world: ^ecs.World, it: ^ecs.QueryIterator, dt: f64, ctx: rawptr) -> bool {
	foo_col := ecs.query_column_index(it, 0)
	bar_col := ecs.query_column_index(it, 1)

	for entity in ecs.query_iter_next_entity(it) {
		foo := ecs.query_entity_data_mut(it, foo_col, Foo)
		bar := ecs.query_entity_data_mut(it, bar_col, Bar)

		foo.v += 50
		bar.v += 100
	}

	return true
}

system3 :: proc(world: ^ecs.World, it: ^ecs.QueryIterator, dt: f64, ctx: rawptr) -> bool {
	foo_col := ecs.query_column_index(it, 0)

	for entity in ecs.query_iter_next_entity(it) {
		foo := ecs.query_entity_data_mut(it, foo_col, Foo)

		foo.v += 5
	}

	return true
}

system4 :: proc(world: ^ecs.World, it: ^ecs.QueryIterator, dt: f64, ctx: rawptr) -> bool {
	foo_col := ecs.query_column_index(it, 0)

	for entity in ecs.query_iter_next_entity(it) {
		foo := ecs.query_entity_data_mut(it, foo_col, Foo)

		foo.v -= 10
	}

	return true
}

system5 :: proc(world: ^ecs.World, it: ^ecs.QueryIterator, dt: f64, ctx: rawptr) -> bool {
	system_ctx := (^System_Context)(ctx)

	system_ctx.value *= 10
	return true
}

system6 :: proc(world: ^ecs.World, it: ^ecs.QueryIterator, dt: f64, ctx: rawptr) -> bool {
	system_ctx := (^System_Context)(ctx)

	system_ctx.value *= 100
	return true
}
