package tests

import ecs ".."
import "core:testing"

@(test)
entity_add_set_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo: ecs.EntityId = ecs.declare(world, Foo)
	bar: ecs.EntityId = ecs.declare(world, Bar)
	plop: ecs.EntityId = ecs.new(world)
	plap: ecs.EntityId = ecs.new(world)

	e1 := ecs.new(world)
	e2 := ecs.new(world)

	testing.expect(t, !ecs.has(world, e1, foo))
	testing.expect(t, !ecs.has(world, e1, bar))
	testing.expect(t, !ecs.has(world, e1, plop))
	testing.expect(t, !ecs.has(world, e1, plap))

	testing.expect(t, !ecs.has(world, e2, foo))
	testing.expect(t, !ecs.has(world, e2, bar))
	testing.expect(t, !ecs.has(world, e2, plop))
	testing.expect(t, !ecs.has(world, e2, plap))

	ecs.add(world, e1, plop)
	ecs.add(world, e2, plap)

	ecs.set(world, e1, &Foo{42})

	testing.expect(t, ecs.has(world, e1, foo))
	testing.expect(t, !ecs.has(world, e1, bar))
	testing.expect(t, ecs.has(world, e1, plop))
	testing.expect(t, !ecs.has(world, e1, plap))

	testing.expect(t, !ecs.has(world, e2, foo))
	testing.expect(t, !ecs.has(world, e2, bar))
	testing.expect(t, !ecs.has(world, e2, plop))
	testing.expect(t, ecs.has(world, e2, plap))

	testing.expect_value(t, ecs.get(world, e1, Foo).v, 42)

	ecs.add(world, e2, e1)

	testing.expect(t, !ecs.has(world, e2, foo))
	testing.expect(t, !ecs.has(world, e2, bar))
	testing.expect(t, !ecs.has(world, e2, plop))
	testing.expect(t, ecs.has(world, e2, plap))
	testing.expect(t, ecs.has(world, e2, e1))

	testing.expect(t, !ecs.add(world, e2, e1))

	ecs.set(world, e2, &Bar{100})

	testing.expect(t, !ecs.has(world, e2, foo))
	testing.expect(t, ecs.has(world, e2, bar))
	testing.expect(t, !ecs.has(world, e2, plop))
	testing.expect(t, ecs.has(world, e2, plap))
	testing.expect(t, ecs.has(world, e2, e1))

	testing.expect_value(t, ecs.get(world, e2, Bar).v, 100)

	ecs.get_mut(world, e2, Bar).v = 200

	testing.expect_value(t, ecs.get(world, e2, Bar).v, 200)

	ecs.set(world, e2, &Bar{300})

	testing.expect_value(t, ecs.get(world, e2, Bar).v, 300)
	testing.expect_value(t, len(world.archetypes.nodes), 8)
}

@(test)
entity_delete_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo: ecs.EntityId = ecs.declare(world, Foo)
	e1 := ecs.new(world)

	ecs.add(world, e1, foo)
	ecs.delete(world, e1)

	testing.expect(t, !ecs.is_valid(world, e1))
}

@(test)
entity_remove_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo: ecs.EntityId = ecs.declare(world, Foo)
	bar: ecs.EntityId = ecs.declare(world, Bar)
	plop: ecs.EntityId = ecs.new(world)
	plap: ecs.EntityId = ecs.new(world)

	e1 := ecs.new(world)
	e2 := ecs.new(world)

	ecs.set(world, e1, &Foo{24})
	ecs.add(world, e1, plop)

	ecs.set(world, e2, &Foo{24})
	ecs.set(world, e2, &Bar{42})
	ecs.add(world, e2, plap)

	testing.expect_value(t, len(world.archetypes.nodes), 7)

	arch1 := expect_find_archetype(t, world, []ecs.EntityId{foo, plop})
	arch2 := expect_find_archetype(t, world, []ecs.EntityId{foo, bar})
	arch3 := expect_find_archetype(t, world, []ecs.EntityId{foo})
	arch4 := expect_find_archetype(t, world, []ecs.EntityId{foo, bar, plap})
	a1_chunk := arch1.chunks[0]
	a2_chunk := arch2.chunks[0]
	a3_chunk := arch3.chunks[0]
	a4_chunk := arch4.chunks[0]

	testing.expect_value(t, len(a1_chunk.entities), 1)
	testing.expect_value(t, len(a2_chunk.entities), 0)
	testing.expect_value(t, len(a3_chunk.entities), 0)
	testing.expect_value(t, len(a4_chunk.entities), 1)

	testing.expect(t, ecs.remove(world, e2, plap))
	testing.expect(t, !ecs.remove(world, e2, plap))

	testing.expect(t, ecs.has(world, e2, foo))
	testing.expect(t, ecs.has(world, e2, bar))
	testing.expect(t, !ecs.has(world, e2, plop))
	testing.expect(t, !ecs.has(world, e2, plap))

	testing.expect_value(t, len(a1_chunk.entities), 1)
	testing.expect_value(t, len(a2_chunk.entities), 1)
	testing.expect_value(t, len(a3_chunk.entities), 0)
	testing.expect_value(t, len(a4_chunk.entities), 0)

	testing.expect(t, ecs.remove(world, e1, foo))

	testing.expect_value(t, len(world.archetypes.nodes), 8)

	arch5 := expect_find_archetype(t, world, []ecs.EntityId{plop})
	a5_chunk := arch5.chunks[0]

	testing.expect_value(t, len(a1_chunk.entities), 0)
	testing.expect_value(t, len(a2_chunk.entities), 1)
	testing.expect_value(t, len(a3_chunk.entities), 0)
	testing.expect_value(t, len(a4_chunk.entities), 0)
	testing.expect_value(t, len(a5_chunk.entities), 1)

	testing.expect(t, ecs.remove(world, e2, foo))
	testing.expect(t, ecs.remove(world, e2, bar))

	testing.expect_value(t, len(world.archetypes.nodes), 9)

	arch6 := expect_find_archetype(t, world, []ecs.EntityId{bar})
	a6_chunk := arch6.chunks[0]

	testing.expect_value(t, len(a1_chunk.entities), 0)
	testing.expect_value(t, len(a2_chunk.entities), 0)
	testing.expect_value(t, len(a3_chunk.entities), 0)
	testing.expect_value(t, len(a4_chunk.entities), 0)
	testing.expect_value(t, len(a5_chunk.entities), 1)
	testing.expect_value(t, len(a6_chunk.entities), 0)

	testing.expect(t, ecs.add(world, e2, plop))

	testing.expect_value(t, len(a1_chunk.entities), 0)
	testing.expect_value(t, len(a2_chunk.entities), 0)
	testing.expect_value(t, len(a3_chunk.entities), 0)
	testing.expect_value(t, len(a4_chunk.entities), 0)
	testing.expect_value(t, len(a5_chunk.entities), 2)
	testing.expect_value(t, len(a6_chunk.entities), 0)
}

@(test)
parent_children_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	e1 := ecs.new(world, "E1")
	e2 := ecs.new(world, "E2")
	e3 := ecs.new(world, "E3")
	e4 := ecs.new(world, "E4")
	e5 := ecs.new(world, "E5")
	e6 := ecs.new(world, "E6")
	e7 := ecs.new(world, "E7")

	testing.expect_value(t, ecs.get_parent(world, e1), 0)
	testing.expect_value(t, ecs.get_parent(world, e2), 0)
	testing.expect_value(t, ecs.get_parent(world, e3), 0)
	testing.expect_value(t, ecs.get_parent(world, e4), 0)

	ecs.set_parent(world, e2, e1)
	ecs.set_parent(world, e3, e1)
	ecs.set_parent(world, e4, e3)
	ecs.set_parent(world, e5, e6)
	ecs.set_parent(world, e7, e4)

	testing.expect_value(t, ecs.get_parent(world, e1), 0)
	testing.expect_value(t, ecs.get_parent(world, e2), e1)
	testing.expect_value(t, ecs.get_parent(world, e3), e1)
	testing.expect_value(t, ecs.get_parent(world, e4), e3)
	testing.expect_value(t, ecs.get_parent(world, e5), e6)

	testing.expect_value(t, ecs.get_entity_depth(world, e1), 0)
	testing.expect_value(t, ecs.get_entity_depth(world, e2), 1)
	testing.expect_value(t, ecs.get_entity_depth(world, e3), 1)
	testing.expect_value(t, ecs.get_entity_depth(world, e4), 2)
	testing.expect_value(t, ecs.get_entity_depth(world, e5), 1)
	testing.expect_value(t, ecs.get_entity_depth(world, e6), 0)
	testing.expect_value(t, ecs.get_entity_depth(world, e7), 3)

	testing.expect(t, ecs.has_pair(world, e2, ecs.ChildOf_Id, e1))
	testing.expect(t, ecs.has_pair(world, e3, ecs.ChildOf_Id, e1))
	testing.expect(t, ecs.has_pair(world, e4, ecs.ChildOf_Id, e3))
	testing.expect(t, ecs.has_pair(world, e5, ecs.ChildOf_Id, e6))
	testing.expect(t, ecs.has_pair(world, e7, ecs.ChildOf_Id, e4))

	// log_debug_world(world)

	ecs.delete(world, e1)

	// log_debug_world(world)

	testing.expect(t, !ecs.is_valid(world, e1))
	testing.expect(t, ecs.is_valid(world, e2))
	testing.expect(t, ecs.is_valid(world, e3))
	testing.expect(t, ecs.is_valid(world, e4))
	testing.expect(t, ecs.is_valid(world, e5))
	testing.expect(t, ecs.is_valid(world, e6))

	testing.expect_value(t, ecs.get_parent(world, e2), 0)
	testing.expect_value(t, ecs.get_parent(world, e3), 0)
	testing.expect_value(t, ecs.get_parent(world, e4), e3)
	testing.expect_value(t, ecs.get_parent(world, e5), e6)
}

@(test)
change_entity_parent_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	e1 := ecs.new(world, "E1")
	e2 := ecs.new(world, "E2")
	e3 := ecs.new(world, "E3")
	e4 := ecs.new(world, "E4")
	e5 := ecs.new(world, "E5")
	e6 := ecs.new(world, "E6")

	testing.expect_value(t, ecs.get_parent(world, e2), 0)
	ecs.set_parent(world, e2, e1)
	testing.expect_value(t, ecs.get_parent(world, e2), e1)
	ecs.set_parent(world, e2, e3)
	testing.expect_value(t, ecs.get_parent(world, e2), e3)
	ecs.set_parent(world, e2, e4)
	testing.expect_value(t, ecs.get_parent(world, e2), e4)
	ecs.delete(world, e4)
	testing.expect_value(t, ecs.get_parent(world, e2), 0)
}

@(test)
find_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	e1 := ecs.new(world, "E1")
	e2 := ecs.new(world, "E2")
	e3 := ecs.new(world, "E3")

	e, exists := ecs.find(world, "E1")
	testing.expect(t, exists)
	testing.expect_value(t, e, e1)
	e, exists = ecs.find(world, "E2")
	testing.expect(t, exists)
	testing.expect_value(t, e, e2)
	e, exists = ecs.find(world, "E3")
	testing.expect(t, exists)
	testing.expect_value(t, e, e3)
	e, exists = ecs.find(world, "E4")
	testing.expect(t, !exists)
	testing.expect_value(t, e, 0)

	ecs.delete(world, e2)

	e, exists = ecs.find(world, "E2")
	testing.expect(t, !exists)
	testing.expect_value(t, e, 0)
}
