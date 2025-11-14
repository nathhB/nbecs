package tests

import ecs ".."
import "core:log"
import "core:testing"

Watcher_Context :: struct {
	foo_count: int,
	bar_count: int,
	e1:        ecs.EntityId,
	e2:        ecs.EntityId,
	t:         ^testing.T,
}

@(test)
watch_delete_events_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo := ecs.ecs_declare(world, Foo)
	bar := ecs.ecs_declare(world, Bar)

	e1 := ecs.ecs_new(world, "E1")
	e2 := ecs.ecs_new(world, "E2")

	ecs.ecs_set(world, e1, &Foo{10})

	ecs.ecs_set(world, e2, &Foo{100})
	ecs.ecs_set(world, e2, &Bar{200})

	ctx := Watcher_Context{0, 0, e1, e2, t}

	ecs.ecs_watch(world, ecs.Event_Deleted, on_deleted_foo, &ctx, ecs.query_term(world, Foo))
	ecs.ecs_watch(
		world,
		ecs.Event_Deleted,
		on_deleted_foo_bar,
		&ctx,
		ecs.query_term(world, Foo),
		ecs.query_term(world, Bar),
	)

	ecs.ecs_delete(world, e1)
	testing.expect_value(t, ctx.foo_count, 1)
	testing.expect_value(t, ctx.bar_count, 0)
	ecs.ecs_delete(world, e2)
	testing.expect_value(t, ctx.foo_count, 3)
	testing.expect_value(t, ctx.bar_count, 1)
}

on_deleted_foo :: proc(
	world: ^ecs.World,
	entity: ecs.EntityId,
	it: ^ecs.QueryIterator,
	ctx: rawptr,
	data: rawptr,
) {
	ctx := (^Watcher_Context)(ctx)

	foo_col := ecs.query_column_index(it, 0)
	foo := ecs.query_entity_data(it, foo_col, Foo)

	testing.expect(ctx.t, entity == ctx.e1 || entity == ctx.e2)

	if entity == ctx.e1 {
		testing.expect_value(ctx.t, foo.v, 10)
	} else if entity == ctx.e2 {
		testing.expect_value(ctx.t, foo.v, 100)
	}

	ctx.foo_count += 1
}

on_deleted_foo_bar :: proc(
	world: ^ecs.World,
	entity: ecs.EntityId,
	it: ^ecs.QueryIterator,
	ctx: rawptr,
	data: rawptr,
) {
	ctx := (^Watcher_Context)(ctx)

	foo_col := ecs.query_column_index(it, 0)
	bar_col := ecs.query_column_index(it, 1)
	foo := ecs.query_entity_data(it, foo_col, Foo)
	bar := ecs.query_entity_data(it, bar_col, Bar)

	testing.expect(ctx.t, entity == ctx.e2)

	if entity == ctx.e2 {
		testing.expect_value(ctx.t, foo.v, 100)
		testing.expect_value(ctx.t, bar.v, 200)
	}

	ctx.foo_count += 1
	ctx.bar_count += 1
}
