package tests

import ecs ".."
import "core:log"
import "core:testing"

// TODO:

Watcher_Context :: struct {
	foo_count: int,
	bar_count: int,
	e1:        ecs.Entity,
	e2:        ecs.Entity,
	t:         ^testing.T,
}

@(test)
watch_delete_events_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo := ecs.declare(world, Foo)
	bar := ecs.declare(world, Bar)

	e1 := ecs.new(world, "E1")
	e2 := ecs.new(world, "E2")

	ecs.set(world, e1, &Foo{10})

	ecs.set(world, e2, &Foo{100})
	ecs.set(world, e2, &Bar{200})

	ctx := Watcher_Context{0, 0, e1, e2, t}

	ecs.watch(world, ecs.Event_Deleted, on_deleted_foo, &ctx, ecs.term(world, Foo))
	ecs.watch(
		world,
		ecs.Event_Deleted,
		on_deleted_foo_bar,
		&ctx,
		ecs.term(world, Foo),
		ecs.term(world, Bar),
	)

	ecs.delete(world, e1)
	testing.expect_value(t, ctx.foo_count, 1)
	testing.expect_value(t, ctx.bar_count, 0)
	ecs.delete(world, e2)
	testing.expect_value(t, ctx.foo_count, 3)
	testing.expect_value(t, ctx.bar_count, 1)
}

on_deleted_foo :: proc(
	world: ^ecs.World,
	entity: ecs.Entity,
	it: ^ecs.Query_Iterator,
	row: int,
	ctx: rawptr,
	data: rawptr,
) {
	ctx := (^Watcher_Context)(ctx)
	chunk := it.current_chunk
	foo_col := ecs.column(it, 0)
	foo := ecs.get(chunk, foo_col, row, Foo)

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
	entity: ecs.Entity,
	it: ^ecs.Query_Iterator,
	row: int,
	ctx: rawptr,
	data: rawptr,
) {
	ctx := (^Watcher_Context)(ctx)
	chunk := it.current_chunk
	foo_col := ecs.column(it, 0)
	bar_col := ecs.column(it, 1)
	foo := ecs.get(chunk, foo_col, row, Foo)
	bar := ecs.get(chunk, bar_col, row, Bar)

	testing.expect(ctx.t, entity == ctx.e2)

	if entity == ctx.e2 {
		testing.expect_value(ctx.t, foo.v, 100)
		testing.expect_value(ctx.t, bar.v, 200)
	}

	ctx.foo_count += 1
	ctx.bar_count += 1
}

