package tests

import ecs ".."
import "core:log"
import "core:testing"

@(test)
trait_tests :: proc(t: ^testing.T) {
	// a trait is a component added to a component
	world := ecs.create()
	defer ecs.destroy(world)

	foo := ecs.declare(world, Foo)
	bar := ecs.declare(world, Bar)
	plop := ecs.new(world)
	plap := ecs.new(world) // will be used as a trait

	ecs.add(world, foo, plap)
	ecs.add(world, plop, plap)

	testing.expect(t, ecs.has(world, foo, plap))
	testing.expect(t, ecs.has(world, plop, plap))
	testing.expect(t, !ecs.has(world, bar, plap))
}

@(test)
pairs_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	apple := ecs.new(world, "Apple")
	pear := ecs.new(world, "Pear")
	eats := ecs.new(world, "Eats")
	pair1 := ecs.build_pair(eats, apple)
	pair2 := ecs.build_pair(eats, pear)

	testing.expect(t, ecs.is_pair(pair1))
	testing.expect(t, ecs.is_pair(pair2))
	testing.expect_value(t, ecs.pair_first(pair1), eats)
	testing.expect_value(t, ecs.pair_first(pair2), eats)
	testing.expect_value(t, ecs.pair_second(pair1), apple)
	testing.expect_value(t, ecs.pair_second(pair2), pear)

	e1 := ecs.new(world, "E1")
	e2 := ecs.new(world, "E2")

	ecs.add_pair(world, e1, eats, apple)
	ecs.add_pair(world, e2, eats, pear)

	testing.expect(t, ecs.has_pair(world, e1, eats, apple))
	testing.expect(t, !ecs.has_pair(world, e1, eats, pear))
	testing.expect(t, !ecs.has_pair(world, e2, eats, apple))
	testing.expect(t, ecs.has_pair(world, e2, eats, pear))

	// pair1 and pair2 have two tags, so no data
	testing.expect_value(t, ecs.get_component_size(world, pair1), 0)
	testing.expect_value(t, ecs.get_component_size(world, pair2), 0)

	possesses := ecs.declare(world, Posseses, "Possesses")
	pair3 := ecs.build_pair(possesses, apple)
	pair4 := ecs.build_pair(possesses, pear)

	testing.expect_value(t, ecs.get_component_size(world, pair3), size_of(Posseses))
	testing.expect_value(t, ecs.get_component_size(world, pair4), size_of(Posseses))

	ecs.set_pair(world, e1, possesses, apple, &Posseses{5})
	ecs.set_pair(world, e2, possesses, pear, &Posseses{20})

	testing.expect(t, ecs.has_pair(world, e1, possesses, apple))
	testing.expect(t, !ecs.has_pair(world, e1, possesses, pear))
	testing.expect(t, ecs.has_pair(world, e2, possesses, pear))
	testing.expect(t, !ecs.has_pair(world, e2, possesses, apple))

	testing.expect_value(t, ecs.get_pair(world, e1, Posseses, apple).amount, 5)
	testing.expect_value(t, ecs.get_pair(world, e2, Posseses, pear).amount, 20)

	e1_possesses := ecs.get_pair_mut(world, e1, Posseses, apple)
	e2_possesses := ecs.get_pair_mut(world, e2, Posseses, pear)

	e1_possesses.amount *= 2
	e2_possesses.amount -= 5

	testing.expect_value(t, ecs.get_pair(world, e1, Posseses, apple).amount, 10)
	testing.expect_value(t, ecs.get_pair(world, e2, Posseses, pear).amount, 15)

	ecs.set_pair(world, e1, &Posseses{42}, apple)
	ecs.set_pair(world, e1, &Posseses{84}, pear)
	ecs.set_pair(world, e2, &Posseses{200}, apple)
	ecs.set_pair(world, e2, &Posseses{100}, pear)

	testing.expect_value(t, ecs.get_pair(world, e1, Posseses, apple).amount, 42)
	testing.expect_value(t, ecs.get_pair(world, e1, Posseses, pear).amount, 84)
	testing.expect_value(t, ecs.get_pair(world, e2, Posseses, apple).amount, 200)
	testing.expect_value(t, ecs.get_pair(world, e2, Posseses, pear).amount, 100)

	arch1 := expect_find_archetype(t, world, []ecs.EntityId{pair1})
	arch2 := expect_find_archetype(t, world, []ecs.EntityId{pair2})
	arch3 := expect_find_archetype(t, world, []ecs.EntityId{pair1, pair3})
	arch4 := expect_find_archetype(t, world, []ecs.EntityId{pair2, pair4})
	arch5 := expect_find_archetype(t, world, []ecs.EntityId{pair1, pair3, pair4})
	arch6 := expect_find_archetype(t, world, []ecs.EntityId{pair2, pair4, pair3})
	a1_chunk := arch1.chunks[0]
	a2_chunk := arch2.chunks[0]
	a3_chunk := arch3.chunks[0]
	a4_chunk := arch4.chunks[0]
	a5_chunk := arch5.chunks[0]
	a6_chunk := arch6.chunks[0]

	testing.expect_value(t, len(a1_chunk.entities), 0)
	testing.expect_value(t, len(a2_chunk.entities), 0)
	testing.expect_value(t, len(a3_chunk.entities), 0)
	testing.expect_value(t, len(a4_chunk.entities), 0)
	testing.expect_value(t, len(a5_chunk.entities), 1)
	testing.expect_value(t, len(a6_chunk.entities), 1)

	expect_archetype_index(
		t,
		world,
		ecs.build_pair(eats, ecs.Wildcard),
		[]^ecs.Archetype{arch1, arch2, arch3, arch4, arch5, arch6},
	)

	ecs.add_pair(world, e1, eats, pear)
	ecs.add_pair(world, e2, eats, apple)

	arch7 := expect_find_archetype(t, world, []ecs.EntityId{pair1, pair2, pair3, pair4})
	a7_chunk := arch7.chunks[0]

	testing.expect_value(t, len(a1_chunk.entities), 0)
	testing.expect_value(t, len(a2_chunk.entities), 0)
	testing.expect_value(t, len(a3_chunk.entities), 0)
	testing.expect_value(t, len(a4_chunk.entities), 0)
	testing.expect_value(t, len(a5_chunk.entities), 0)
	testing.expect_value(t, len(a6_chunk.entities), 0)
	testing.expect_value(t, len(a7_chunk.entities), 2)

	expect_archetype_index(
		t,
		world,
		ecs.build_pair(eats, ecs.Wildcard),
		[]^ecs.Archetype{arch1, arch2, arch3, arch4, arch5, arch6, arch7},
	)
	expect_archetype_index(
		t,
		world,
		ecs.build_pair(ecs.Wildcard, apple),
		[]^ecs.Archetype{arch1, arch3, arch5, arch6, arch7},
	)
}

@(test)
simple_cleanup_delete_strategy_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	e1 := ecs.new(world, name = "E1")
	e2 := ecs.new(world, name = "E2")
	e3 := ecs.new(world, name = "E3")

	ecs.set_deletion_strategy(world, e2, ecs.DeleteStrategy_Delete)

	ecs.add(world, e1, e2)
	ecs.add(world, e1, e3)

	ecs.delete(world, e2)

	testing.expect(t, !ecs.is_valid(world, e1))
	testing.expect(t, !ecs.is_valid(world, e2))
	testing.expect(t, ecs.is_valid(world, e3))
}

@(test)
simple_cleanup_remove_strategy_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	e1 := ecs.new(world, name = "E1")
	e2 := ecs.new(world, name = "E2")
	e3 := ecs.new(world, name = "E3")

	ecs.set_deletion_strategy(world, e2, ecs.DeleteStrategy_Remove)

	ecs.add(world, e1, e2)
	ecs.add(world, e1, e3)

	log_debug_world(world)

	ecs.delete(world, e2)

	testing.expect(t, ecs.is_valid(world, e1))
	testing.expect(t, !ecs.is_valid(world, e2))
	testing.expect(t, ecs.is_valid(world, e3))

	arch := expect_find_archetype(t, world, []ecs.EntityId{e3})
	expect_entity_archetype(t, world, e1, arch)
}

@(test)
pair_cleanup_remove_strategy_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	eats := ecs.new(world, "Eats")
	likes := ecs.new(world, "Likes")
	apple := ecs.new(world, "Apple")
	pear := ecs.new(world, "Pear")
	pair1 := ecs.build_pair(eats, apple)
	pair2 := ecs.build_pair(eats, pear)
	pair3 := ecs.build_pair(likes, apple)
	pair4 := ecs.build_pair(likes, pear)
	e1 := ecs.new(world, "E1")
	e2 := ecs.new(world, "E2")

	ecs.set_deletion_strategy(world, apple, ecs.DeleteStrategy_Remove)
	ecs.set_deletion_strategy(world, likes, ecs.DeleteStrategy_Remove)

	ecs.add_pair(world, e1, eats, apple)
	ecs.add_pair(world, e1, eats, pear)
	ecs.add_pair(world, e1, likes, apple)

	ecs.add_pair(world, e2, eats, pear)
	ecs.add_pair(world, e2, likes, apple)
	ecs.add_pair(world, e2, likes, pear)

	// log_debug_world(world)

	ecs.delete(world, apple)

	testing.expect(t, ecs.is_valid(world, e1))
	testing.expect(t, ecs.is_valid(world, e2))
	testing.expect(t, !ecs.has(world, e1, pair1))
	testing.expect(t, ecs.has(world, e1, pair2))
	testing.expect(t, !ecs.has(world, e1, pair3))
	testing.expect(t, !ecs.has(world, e1, pair4))
	testing.expect(t, !ecs.has(world, e2, pair1))
	testing.expect(t, ecs.has(world, e2, pair2))
	testing.expect(t, !ecs.has(world, e2, pair3))
	testing.expect(t, ecs.has(world, e2, pair4))

	arch1 := expect_find_archetype(t, world, []ecs.EntityId{pair2, pair4})
	arch2 := expect_find_archetype(t, world, []ecs.EntityId{pair2})

	expect_entity_archetype(t, world, e1, arch2)
	expect_entity_archetype(t, world, e2, arch1)

	// log_debug_world(world)

	ecs.delete(world, likes)

	// log_debug_world(world)

	testing.expect(t, ecs.is_valid(world, e1))
	testing.expect(t, ecs.is_valid(world, e2))
	testing.expect(t, !ecs.has(world, e1, pair1))
	testing.expect(t, ecs.has(world, e1, pair2))
	testing.expect(t, !ecs.has(world, e1, pair3))
	testing.expect(t, !ecs.has(world, e1, pair4))
	testing.expect(t, !ecs.has(world, e2, pair1))
	testing.expect(t, ecs.has(world, e2, pair2))
	testing.expect(t, !ecs.has(world, e2, pair3))
	testing.expect(t, !ecs.has(world, e2, pair4))

	arch3 := expect_find_archetype(t, world, []ecs.EntityId{pair2})
	expect_entity_archetype(t, world, e1, arch3)
	expect_entity_archetype(t, world, e2, arch3)
}

@(test)
cleanup_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	ecs.set_default_delete_strategy(world, ecs.DeleteStrategy_Delete)

	e1 := ecs.new(world, name = "E1")
	e2 := ecs.new(world, name = "E2")
	e3 := ecs.new(world, name = "E3")
	e4 := ecs.new(world, name = "E4")
	e5 := ecs.new(world, name = "E5")

	ecs.add(world, e1, e2)
	ecs.add(world, e1, e3)
	ecs.add(world, e2, e3)
	ecs.add(world, e4, e5)
	ecs.add(world, e5, e2)
	ecs.add(world, e5, e3)

	testing.expect(t, ecs.has(world, e1, e2))
	testing.expect(t, ecs.has(world, e1, e3))
	testing.expect(t, ecs.has(world, e2, e3))
	testing.expect(t, ecs.has(world, e4, e5))
	testing.expect(t, ecs.has(world, e5, e2))
	testing.expect(t, ecs.has(world, e5, e3))

	// log_debug_world(world)

	testing.expect_value(t, len(world.archetypes.nodes), 7)

	arch1 := expect_find_archetype(t, world, []ecs.EntityId{e2})
	arch2 := expect_find_archetype(t, world, []ecs.EntityId{e2, e3})
	arch3 := expect_find_archetype(t, world, []ecs.EntityId{e3})
	arch4 := expect_find_archetype(t, world, []ecs.EntityId{e5})

	expect_archetype_index(t, world, e2, []^ecs.Archetype{arch1, arch2})
	expect_archetype_index(t, world, e3, []^ecs.Archetype{arch2, arch3})
	expect_archetype_index(t, world, e5, []^ecs.Archetype{arch4})

	expect_entity_archetype(t, world, e1, arch2)
	expect_entity_archetype(t, world, e2, arch3)
	expect_entity_archetype(t, world, e3, &world.archetypes.root.archetype)
	expect_entity_archetype(t, world, e4, arch4)
	expect_entity_archetype(t, world, e5, arch2)

	q := ecs.query(world, ecs.term(world, e2))
	q2 := ecs.query(world, ecs.term(world, e3))

	expect_query_matched_entities(t, q, []ecs.EntityId{e1, e5})
	expect_query_matched_entities(t, q2, []ecs.EntityId{e1, e2, e5})

	log_debug_world(world)

	ecs.delete(world, e2)

	// log_debug_world(world)

	// entities that had e2 entity should be deleted
	testing.expect(t, !ecs.is_valid(world, e1))
	testing.expect(t, !ecs.is_valid(world, e2))
	testing.expect(t, ecs.is_valid(world, e3))
	testing.expect(t, !ecs.is_valid(world, e4))
	testing.expect(t, !ecs.is_valid(world, e5))

	// archetypes are properly cleaned up
	testing.expect_value(t, len(world.archetypes.nodes), 4)
	arch1 = expect_find_archetype(t, world, []ecs.EntityId{e3})
	a1_chunk := arch1.chunks[0]
	testing.expect_value(t, len(a1_chunk.entities), 0)
	expect_archetype_index(t, world, e1, []^ecs.Archetype{})
	expect_archetype_index(t, world, e2, []^ecs.Archetype{})
	expect_archetype_index(t, world, e3, []^ecs.Archetype{arch1})
	expect_archetype_index(t, world, e4, []^ecs.Archetype{})
	expect_archetype_index(t, world, e5, []^ecs.Archetype{})

	// queries are properly updated

	expect_query_matched_entities(t, q, []ecs.EntityId{})
	expect_query_matched_entities(t, q2, []ecs.EntityId{})
}

@(test)
cleanup_pairs_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	ecs.set_default_delete_strategy(world, ecs.DeleteStrategy_Delete)

	eats := ecs.new(world, "Eats")
	apple := ecs.new(world, "Apple")
	pear := ecs.new(world, "Pear")
	pair1 := ecs.build_pair(eats, apple)
	pair2 := ecs.build_pair(eats, pear)
	e1 := ecs.new(world, "E1")
	e2 := ecs.new(world, "E2")

	ecs.add_pair(world, e1, eats, apple)
	ecs.add_pair(world, e2, eats, apple)
	ecs.add_pair(world, e2, eats, pear)

	testing.expect(t, ecs.has_pair(world, e1, eats, apple))
	testing.expect(t, ecs.has_pair(world, e2, eats, apple))
	testing.expect(t, ecs.has_pair(world, e2, eats, pear))

	// log_debug_world(world)

	arch1 := expect_find_archetype(t, world, []ecs.EntityId{pair1, pair2})
	arch2 := expect_find_archetype(t, world, []ecs.EntityId{pair1})

	expect_archetype_index(
		t,
		world,
		ecs.build_pair(eats, ecs.Wildcard),
		[]^ecs.Archetype{arch1, arch2},
	)
	expect_archetype_index(
		t,
		world,
		ecs.build_pair(ecs.Wildcard, apple),
		[]^ecs.Archetype{arch1, arch2},
	)
	expect_archetype_index(t, world, ecs.build_pair(ecs.Wildcard, pear), []^ecs.Archetype{arch1})

	q := ecs.query(world, ecs.term(world, ecs.build_pair(eats, ecs.Wildcard)))

	expect_query_matched_archetypes(t, q, []^ecs.Archetype{arch1, arch2})
	expect_query_matched_entities(t, q, []ecs.EntityId{e1, e2})

	ecs.delete(world, pear)

	testing.expect(t, ecs.is_valid(world, e1))
	testing.expect(t, !ecs.is_valid(world, e2))

	expect_no_archetype(t, world, []ecs.EntityId{pair1, pair2})
	expect_no_archetype(t, world, []ecs.EntityId{pair2})

	// log_debug_world(world)

	arch1 = expect_find_archetype(t, world, []ecs.EntityId{pair1})

	expect_archetype_index(t, world, ecs.build_pair(eats, ecs.Wildcard), []^ecs.Archetype{arch1})
	expect_archetype_index(t, world, ecs.build_pair(ecs.Wildcard, apple), []^ecs.Archetype{arch1})
	expect_archetype_index(t, world, ecs.build_pair(ecs.Wildcard, pear), []^ecs.Archetype{})
	expect_archetype_index(t, world, ecs.build_pair(pear, ecs.Wildcard), []^ecs.Archetype{})

	// queries are properly updated

	expect_query_matched_archetypes(t, q, []^ecs.Archetype{arch1})
	expect_query_matched_entities(t, q, []ecs.EntityId{e1})
}
