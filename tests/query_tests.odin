package tests

import ecs ".."
import "core:log"
import "core:testing"

@(test)
query_match_archetypes_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo: ecs.EntityId = ecs.ecs_new(world)
	bar: ecs.EntityId = ecs.ecs_new(world)
	plop: ecs.EntityId = ecs.ecs_new(world)
	plap: ecs.EntityId = ecs.ecs_new(world)

	e1 := ecs.ecs_new(world)
	e2 := ecs.ecs_new(world)
	e3 := ecs.ecs_new(world)

	ecs.ecs_add(world, e1, foo)

	ecs.ecs_add(world, e2, foo)
	ecs.ecs_add(world, e2, bar)

	ecs.ecs_add(world, e3, bar)
	ecs.ecs_add(world, e3, plop)

	testing.expect_value(t, len(world.archetypes.nodes), 7)

	arch1 := expect_find_archetype(t, world, []ecs.EntityId{foo})
	arch2 := expect_find_archetype(t, world, []ecs.EntityId{foo, bar})
	arch3 := expect_find_archetype(t, world, []ecs.EntityId{bar})
	arch4 := expect_find_archetype(t, world, []ecs.EntityId{bar, plop})

	q1 := ecs.query_build(world, ecs.query_term(world, foo))

	expect_query_matched_archetypes(t, q1, []^ecs.Archetype{arch1, arch2})

	q2 := ecs.query_build(world, ecs.query_term(world, foo), ecs.query_term(world, bar))

	expect_query_matched_archetypes(t, q2, []^ecs.Archetype{arch2})

	q3 := ecs.query_build(
		world,
		ecs.query_term(world, foo),
		ecs.query_term(world, bar),
		ecs.query_term(world, plop),
	)

	expect_query_matched_archetypes(t, q3, []^ecs.Archetype{})

	q4 := ecs.query_build(world, ecs.query_term(world, bar), ecs.query_term(world, plop))

	expect_query_matched_archetypes(t, q4, []^ecs.Archetype{arch4})

	ecs.ecs_add(world, e3, foo)

	arch5 := expect_find_archetype(t, world, []ecs.EntityId{foo, bar, plop})

	expect_query_matched_archetypes(t, q3, []^ecs.Archetype{arch5})
	expect_query_matched_archetypes(t, q1, []^ecs.Archetype{arch1, arch2, arch5})
}

@(test)
query_match_entities_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo: ecs.EntityId = ecs.ecs_declare(world, Foo, "Foo")
	bar: ecs.EntityId = ecs.ecs_declare(world, Bar, "Bar")
	plop: ecs.EntityId = ecs.ecs_new(world, "Plop")
	plap: ecs.EntityId = ecs.ecs_new(world, "Plap")

	e1 := ecs.ecs_new(world, "E1")
	e2 := ecs.ecs_new(world, "E2")
	e3 := ecs.ecs_new(world, "E3")

	ecs.ecs_set(world, e1, &Foo{42})

	ecs.ecs_set(world, e2, &Foo{142})
	ecs.ecs_add(world, e2, bar)

	ecs.ecs_add(world, e3, bar)
	ecs.ecs_add(world, e3, plop)

	arch1 := expect_find_archetype(t, world, []ecs.EntityId{bar})
	arch2 := expect_find_archetype(t, world, []ecs.EntityId{foo, bar})
	arch3 := expect_find_archetype(t, world, []ecs.EntityId{bar, plop})

	expect_archetype_index(t, world, bar, []^ecs.Archetype{arch1, arch2, arch3})

	q1 := ecs.query_build(world, ecs.query_term(world, foo))

	expect_query_matched_entities(t, q1, []ecs.EntityId{e1, e2})

	q2 := ecs.query_build(world, ecs.query_term(world, bar))

	expect_query_matched_entities(t, q2, []ecs.EntityId{e2, e3})

	q3 := ecs.query_build(world, ecs.query_term(world, plop))

	expect_query_matched_entities(t, q3, []ecs.EntityId{e3})

	ecs.ecs_add(world, e1, bar)
	ecs.ecs_add(world, e1, plop)

	expect_query_matched_entities(t, q2, []ecs.EntityId{e1, e2, e3})
	expect_query_matched_entities(t, q3, []ecs.EntityId{e1, e3})

	ecs.ecs_delete(world, e1)
	ecs.ecs_delete(world, e3)

	expect_query_matched_entities(t, q2, []ecs.EntityId{e2})
	expect_query_matched_entities(t, q3, []ecs.EntityId{})
}

@(test)
query_match_relationships_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	apple := ecs.ecs_new(world)
	pear := ecs.ecs_new(world)
	eats := ecs.ecs_new(world)
	possesses := ecs.ecs_declare(world, Posseses)
	pair1 := ecs.ecs_build_pair(eats, apple)
	pair2 := ecs.ecs_build_pair(eats, pear)
	pair3 := ecs.ecs_build_pair(possesses, apple)

	e1 := ecs.ecs_new(world)
	e2 := ecs.ecs_new(world)

	ecs.ecs_add_pair(world, e1, eats, apple)
	ecs.ecs_add_pair(world, e2, eats, pear)

	q1 := ecs.query_build(world, ecs.query_term(world, eats, apple))

	expect_query_matched_entities(t, q1, []ecs.EntityId{e1})

	q2 := ecs.query_build(world, ecs.query_term(world, eats, pear))

	expect_query_matched_entities(t, q2, []ecs.EntityId{e2})

	ecs.ecs_add_pair(world, e2, eats, apple)

	expect_query_matched_entities(t, q1, []ecs.EntityId{e1, e2})
	expect_query_matched_entities(t, q2, []ecs.EntityId{e2})

	ecs.ecs_remove(world, e1, pair1)

	expect_query_matched_entities(t, q1, []ecs.EntityId{e2})
	expect_query_matched_entities(t, q2, []ecs.EntityId{e2})

	q3 := ecs.query_build(world, ecs.query_term(world, ecs.ecs_build_pair(eats, ecs.Wildcard)))

	expect_query_matched_entities(t, q3, []ecs.EntityId{e2})

	e3 := ecs.ecs_new(world)
	e4 := ecs.ecs_new(world)
	e5 := ecs.ecs_new(world)

	ecs.ecs_add_pair(world, e3, eats, apple)
	ecs.ecs_add_pair(world, e3, eats, pear)
	ecs.ecs_add_pair(world, e5, eats, apple)

	expect_query_matched_entities(t, q3, []ecs.EntityId{e2, e3, e5})

	q4 := ecs.query_build(world, ecs.query_term(world, ecs.ecs_build_pair(ecs.Wildcard, pear)))

	expect_query_matched_entities(t, q4, []ecs.EntityId{e2, e3})

	q5 := ecs.query_build(world, ecs.query_term(world, ecs.ecs_build_pair(ecs.Wildcard, apple)))

	expect_query_matched_entities(t, q5, []ecs.EntityId{e2, e3, e5})

	ecs.ecs_set_pair(world, e4, &Posseses{42}, apple)

	expect_query_matched_entities(t, q4, []ecs.EntityId{e2, e3})
	expect_query_matched_entities(t, q5, []ecs.EntityId{e2, e3, e4, e5})

	ecs.ecs_delete(world, e3)
	ecs.ecs_delete(world, e4)

	expect_query_matched_entities(t, q4, []ecs.EntityId{e2})
	expect_query_matched_entities(t, q5, []ecs.EntityId{e2, e5})
}

@(test)
query_entity_data_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	apple := ecs.ecs_new(world)
	pear := ecs.ecs_new(world)
	possesses := ecs.ecs_declare(world, Posseses)

	e1 := ecs.ecs_new(world)
	e2 := ecs.ecs_new(world)
	e3 := ecs.ecs_new(world)
	e4 := ecs.ecs_new(world)

	ecs.ecs_set_pair(world, e1, &Posseses{10}, apple)
	ecs.ecs_set_pair(world, e2, &Posseses{10}, pear)
	ecs.ecs_set_pair(world, e3, &Posseses{100}, apple)
	ecs.ecs_set_pair(world, e4, &Posseses{100}, pear)

	q1 := ecs.query_build(world, ecs.query_term(world, Posseses, apple))

	expect_query_matched_entities(t, q1, []ecs.EntityId{e1, e3})

	it := ecs.query_iter(q1)

	for ecs.query_iter_next_match(&it) {
		col := ecs.query_column_index(&it, 0)

		for entity in ecs.query_iter_next_entity(&it) {
			p := ecs.query_entity_data_mut(&it, col, Posseses)

			p.amount *= 2
		}
	}

	testing.expect_value(t, ecs.ecs_get_pair(world, e1, Posseses, apple).amount, 20)
	testing.expect_value(t, ecs.ecs_get_pair(world, e2, Posseses, pear).amount, 10)
	testing.expect_value(t, ecs.ecs_get_pair(world, e3, Posseses, apple).amount, 200)
	testing.expect_value(t, ecs.ecs_get_pair(world, e4, Posseses, pear).amount, 100)
}

@(test)
query_unique_pair_entity_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	apple := ecs.ecs_new(world)
	pear := ecs.ecs_new(world)
	possesses := ecs.ecs_declare(world, Posseses)

	ecs.ecs_add(world, possesses, ecs.UniquePair)

	e1 := ecs.ecs_new(world)
	e2 := ecs.ecs_new(world)

	ecs.ecs_set_pair(world, e1, &Posseses{10}, apple)
	ecs.ecs_set_pair(world, e2, &Posseses{10}, pear)

	q := ecs.query_build(world, ecs.query_term(world, Posseses, ecs.Wildcard))

	expect_query_matched_entities(t, q, []ecs.EntityId{e1, e2})

	it := ecs.query_iter(q)

	for ecs.query_iter_next_match(&it) {
		possessed_entity := ecs.query_unique_pair_entity(&it, 0)

		for entity in ecs.query_iter_next_entity(&it) {
			if entity == e1 {
				testing.expect_value(t, possessed_entity, apple)
			} else if entity == e2 {
				testing.expect_value(t, possessed_entity, pear)
			} else {
				unreachable()
			}
		}
	}
}

@(test)
query_not_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo: ecs.EntityId = ecs.ecs_declare(world, Foo)
	bar: ecs.EntityId = ecs.ecs_declare(world, Bar)
	plop: ecs.EntityId = ecs.ecs_new(world)
	plap: ecs.EntityId = ecs.ecs_new(world)

	e1 := ecs.ecs_new(world)
	e2 := ecs.ecs_new(world)
	e3 := ecs.ecs_new(world)

	ecs.ecs_set(world, e1, &Foo{42})
	ecs.ecs_add(world, e1, plop)

	ecs.ecs_set(world, e2, &Foo{142})
	ecs.ecs_set(world, e2, &Bar{200})
	ecs.ecs_add(world, e2, plap)

	ecs.ecs_set(world, e3, &Foo{300})

	q1 := ecs.query_build(world, ecs.query_term(world, Foo), ecs.query_not_term(world, Bar))
	q2 := ecs.query_build(world, ecs.query_term(world, Foo), ecs.query_not_term(world, plop))
	q3 := ecs.query_build(world, ecs.query_term(world, Foo), ecs.query_not_term(world, plap))
	q4 := ecs.query_build(
		world,
		ecs.query_term(world, Foo),
		ecs.query_not_term(world, Bar),
		ecs.query_not_term(world, plop),
	)

	expect_query_matched_entities(t, q1, []ecs.EntityId{e1, e3})
	expect_query_matched_entities(t, q2, []ecs.EntityId{e2, e3})
	expect_query_matched_entities(t, q3, []ecs.EntityId{e1, e3})
	expect_query_matched_entities(t, q4, []ecs.EntityId{e3})
}

@(test)
query_optional_term_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo: ecs.EntityId = ecs.ecs_declare(world, Foo)
	bar: ecs.EntityId = ecs.ecs_declare(world, Bar)
	plop: ecs.EntityId = ecs.ecs_new(world)
	plap: ecs.EntityId = ecs.ecs_new(world)

	e1 := ecs.ecs_new(world)
	e2 := ecs.ecs_new(world)
	e3 := ecs.ecs_new(world)

	ecs.ecs_set(world, e1, &Foo{42})
	ecs.ecs_add(world, e1, plop)

	ecs.ecs_set(world, e2, &Foo{142})
	ecs.ecs_set(world, e2, &Bar{200})
	ecs.ecs_add(world, e2, plap)

	ecs.ecs_set(world, e3, &Foo{300})

	q1 := ecs.query_build(
		world,
		ecs.query_term(world, Foo),
		ecs.query_term(world, Bar, optional = true),
	)
	q2 := ecs.query_build(
		world,
		ecs.query_term(world, Foo),
		ecs.query_term(world, Bar, optional = true),
		ecs.query_term(world, plap),
	)

	expect_query_matched_entities(t, q1, []ecs.EntityId{e1, e2, e3})
	expect_query_matched_entities(t, q2, []ecs.EntityId{e2})
}

@(test)
query_parent_component_test :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo: ecs.EntityId = ecs.ecs_declare(world, Foo)
	bar: ecs.EntityId = ecs.ecs_declare(world, Bar)

	e1 := ecs.ecs_new(world)
	e2 := ecs.ecs_new(world)
	e3 := ecs.ecs_new(world)

	ecs.ecs_set(world, e1, &Foo{42})

	ecs.ecs_set(world, e2, &Foo{12})
	ecs.ecs_set(world, e2, &Bar{142})

	ecs.ecs_set(world, e3, &Foo{242})

	ecs.ecs_set_parent(world, e2, e1)
	ecs.ecs_set_parent(world, e3, e2)

	q1 := ecs.query_build(world, ecs.query_term(world, Foo))
	it := ecs.query_iter(q1)

	expect_query_matched_entities(t, q1, []ecs.EntityId{e1, e2, e3})

	for i := 0; i < len(it.matches); i += 1 {
		ecs.query_iter_next_match(&it)

		if it.current_match.archetype == world.entities[e1].chunk.archetype {
			testing.expect_value(t, it.current_match.parent, 0)
		}

		if it.current_match.archetype == world.entities[e2].chunk.archetype {
			testing.expect_value(t, it.current_match.parent, e1)
		}

		if it.current_match.archetype == world.entities[e3].chunk.archetype {
			testing.expect_value(t, it.current_match.parent, e2)
		}
	}
}
