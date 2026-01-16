package tests

import ecs ".."
import ecs_snap "../snapshot"
import "core:testing"

@(test)
world_snapshot_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo := ecs.ecs_declare(world, Foo, "Foo")
	bar := ecs.ecs_declare(world, Bar, "Bar")

	e1: ecs.EntityId = 101
	e2: ecs.EntityId = 102
	e3: ecs.EntityId = 103

	ecs.ecs_new_with_id(world, e1, "E1")
	ecs.ecs_new_with_id(world, e2, "E2")
	ecs.ecs_new_with_id(world, e3, "E3")

	ecs.ecs_set(world, e1, &Foo{1})
	ecs.ecs_set(world, e1, &Bar{2})

	ecs.ecs_set(world, e2, &Foo{10})

	ecs.ecs_set(world, e3, &Bar{20})

	snapshot := ecs_snap.take_snapshot(world, context.temp_allocator)
	defer free_all(context.temp_allocator)

	clone_arch1 := expect_find_archetype(t, snapshot, []ecs.EntityId{foo, bar})
	clone_arch2 := expect_find_archetype(t, snapshot, []ecs.EntityId{foo})
	clone_arch3 := expect_find_archetype(t, snapshot, []ecs.EntityId{bar})

	testing.expect_value(t, len(clone_arch1.chunks), 1)
	testing.expect_value(t, len(clone_arch2.chunks), 1)
	testing.expect_value(t, len(clone_arch3.chunks), 1)

	testing.expect_value(t, clone_arch1.chunks[0].entities[0], e1)
	testing.expect_value(t, clone_arch2.chunks[0].entities[0], e2)
	testing.expect_value(t, clone_arch3.chunks[0].entities[0], e3)

	expect_filter_matched_entities(
		t,
		snapshot,
		[]ecs.EntityId{e1, e2},
		ecs.query_term(snapshot, foo),
	)
	expect_filter_matched_entities(
		t,
		snapshot,
		[]ecs.EntityId{e1, e3},
		ecs.query_term(snapshot, bar),
	)
	expect_filter_matched_entities(
		t,
		snapshot,
		[]ecs.EntityId{e1},
		ecs.query_term(snapshot, foo),
		ecs.query_term(snapshot, bar),
	)
}
