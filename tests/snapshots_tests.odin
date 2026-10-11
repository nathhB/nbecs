package tests

import ecs ".."
import snap "../snapshot"
import "core:testing"

// @(test)
// world_snapshot_tests :: proc(t: ^testing.T) {
// 	world := ecs.create()
// 	defer ecs.destroy(world)
//
// 	foo := ecs.declare(world, Foo, "Foo")
// 	bar := ecs.declare(world, Bar, "Bar")
//
// 	e1: ecs.Entity = 101
// 	e2: ecs.Entity = 102
// 	e3: ecs.Entity = 103
//
// 	ecs.new_with_id(world, e1, "E1")
// 	ecs.new_with_id(world, e2, "E2")
// 	ecs.new_with_id(world, e3, "E3")
//
// 	ecs.set(world, e1, &Foo{1})
// 	ecs.set(world, e1, &Bar{2})
//
// 	ecs.set(world, e2, &Foo{10})
//
// 	ecs.set(world, e3, &Bar{20})
//
// 	snapshot := snap.take_snapshot(world, context.temp_allocator)
// 	defer free_all(context.temp_allocator)
//
// 	clone_arch1 := expect_find_archetype(t, snapshot, []ecs.Entity{foo, bar})
// 	clone_arch2 := expect_find_archetype(t, snapshot, []ecs.Entity{foo})
// 	clone_arch3 := expect_find_archetype(t, snapshot, []ecs.Entity{bar})
//
// 	testing.expect_value(t, len(clone_arch1.chunks), 1)
// 	testing.expect_value(t, len(clone_arch2.chunks), 1)
// 	testing.expect_value(t, len(clone_arch3.chunks), 1)
//
// 	testing.expect_value(t, clone_arch1.chunks[0].entities[0], e1)
// 	testing.expect_value(t, clone_arch2.chunks[0].entities[0], e2)
// 	testing.expect_value(t, clone_arch3.chunks[0].entities[0], e3)
//
// 	expect_filter_matched_entities(t, snapshot, []ecs.Entity{e1, e2}, ecs.term(snapshot, foo))
// 	expect_filter_matched_entities(t, snapshot, []ecs.Entity{e1, e3}, ecs.term(snapshot, bar))
// 	expect_filter_matched_entities(
// 		t,
// 		snapshot,
// 		[]ecs.Entity{e1},
// 		ecs.term(snapshot, foo),
// 		ecs.term(snapshot, bar),
// 	)
// }

