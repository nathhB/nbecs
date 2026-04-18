package tests

import ecs ".."
import "core:log"
import "core:testing"

@(test)
query_match_archetypes_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo: ecs.EntityId = ecs.new(world)
	bar: ecs.EntityId = ecs.new(world)
	plop: ecs.EntityId = ecs.new(world)
	plap: ecs.EntityId = ecs.new(world)

	e1 := ecs.new(world)
	e2 := ecs.new(world)
	e3 := ecs.new(world)

	ecs.add(world, e1, foo)

	ecs.add(world, e2, foo)
	ecs.add(world, e2, bar)

	ecs.add(world, e3, bar)
	ecs.add(world, e3, plop)

	testing.expect_value(t, len(world.archetypes.nodes), 7)

	arch1 := expect_find_archetype(t, world, []ecs.EntityId{foo})
	arch2 := expect_find_archetype(t, world, []ecs.EntityId{foo, bar})
	arch3 := expect_find_archetype(t, world, []ecs.EntityId{bar})
	arch4 := expect_find_archetype(t, world, []ecs.EntityId{bar, plop})

	q1 := ecs.query(world, ecs.term(world, foo))

	expect_query_matched_archetypes(t, q1, []^ecs.Archetype{arch1, arch2})

	q2 := ecs.query(world, ecs.term(world, foo), ecs.term(world, bar))

	expect_query_matched_archetypes(t, q2, []^ecs.Archetype{arch2})

	q3 := ecs.query(world, ecs.term(world, foo), ecs.term(world, bar), ecs.term(world, plop))

	expect_query_matched_archetypes(t, q3, []^ecs.Archetype{})

	q4 := ecs.query(world, ecs.term(world, bar), ecs.term(world, plop))

	expect_query_matched_archetypes(t, q4, []^ecs.Archetype{arch4})

	ecs.add(world, e3, foo)

	arch5 := expect_find_archetype(t, world, []ecs.EntityId{foo, bar, plop})

	expect_query_matched_archetypes(t, q3, []^ecs.Archetype{arch5})
	expect_query_matched_archetypes(t, q1, []^ecs.Archetype{arch1, arch2, arch5})
}

@(test)
query_match_entities_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo: ecs.EntityId = ecs.declare(world, Foo, "Foo")
	bar: ecs.EntityId = ecs.declare(world, Bar, "Bar")
	plop: ecs.EntityId = ecs.new(world, "Plop")
	plap: ecs.EntityId = ecs.new(world, "Plap")

	e1 := ecs.new(world, "E1")
	e2 := ecs.new(world, "E2")
	e3 := ecs.new(world, "E3")

	ecs.set(world, e1, &Foo{42})

	ecs.set(world, e2, &Foo{142})
	ecs.add(world, e2, bar)

	ecs.add(world, e3, bar)
	ecs.add(world, e3, plop)

	arch1 := expect_find_archetype(t, world, []ecs.EntityId{bar})
	arch2 := expect_find_archetype(t, world, []ecs.EntityId{foo, bar})
	arch3 := expect_find_archetype(t, world, []ecs.EntityId{bar, plop})

	expect_archetype_index(t, world, bar, []^ecs.Archetype{arch1, arch2, arch3})

	q1 := ecs.query(world, ecs.term(world, foo))

	expect_query_matched_entities(t, q1, []ecs.EntityId{e1, e2})

	q2 := ecs.query(world, ecs.term(world, bar))

	expect_query_matched_entities(t, q2, []ecs.EntityId{e2, e3})

	q3 := ecs.query(world, ecs.term(world, plop))

	expect_query_matched_entities(t, q3, []ecs.EntityId{e3})

	ecs.add(world, e1, bar)
	ecs.add(world, e1, plop)

	expect_query_matched_entities(t, q2, []ecs.EntityId{e1, e2, e3})
	expect_query_matched_entities(t, q3, []ecs.EntityId{e1, e3})

	ecs.delete(world, e1)
	ecs.delete(world, e3)

	expect_query_matched_entities(t, q2, []ecs.EntityId{e2})
	expect_query_matched_entities(t, q3, []ecs.EntityId{})
}

@(test)
query_match_relationships_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	apple := ecs.new(world)
	pear := ecs.new(world)
	eats := ecs.new(world)
	possesses := ecs.declare(world, Posseses)
	pair1 := ecs.build_pair(eats, apple)
	pair2 := ecs.build_pair(eats, pear)
	pair3 := ecs.build_pair(possesses, apple)

	e1 := ecs.new(world)
	e2 := ecs.new(world)

	ecs.add_pair(world, e1, eats, apple)
	ecs.add_pair(world, e2, eats, pear)

	q1 := ecs.query(world, ecs.term(world, eats, apple))

	expect_query_matched_entities(t, q1, []ecs.EntityId{e1})

	q2 := ecs.query(world, ecs.term(world, eats, pear))

	expect_query_matched_entities(t, q2, []ecs.EntityId{e2})

	ecs.add_pair(world, e2, eats, apple)

	expect_query_matched_entities(t, q1, []ecs.EntityId{e1, e2})
	expect_query_matched_entities(t, q2, []ecs.EntityId{e2})

	ecs.remove(world, e1, pair1)

	expect_query_matched_entities(t, q1, []ecs.EntityId{e2})
	expect_query_matched_entities(t, q2, []ecs.EntityId{e2})

	q3 := ecs.query(world, ecs.term(world, ecs.build_pair(eats, ecs.Wildcard)))

	expect_query_matched_entities(t, q3, []ecs.EntityId{e2})

	e3 := ecs.new(world)
	e4 := ecs.new(world)
	e5 := ecs.new(world)

	ecs.add_pair(world, e3, eats, apple)
	ecs.add_pair(world, e3, eats, pear)
	ecs.add_pair(world, e5, eats, apple)

	expect_query_matched_entities(t, q3, []ecs.EntityId{e2, e3, e5})

	q4 := ecs.query(world, ecs.term(world, ecs.build_pair(ecs.Wildcard, pear)))

	expect_query_matched_entities(t, q4, []ecs.EntityId{e2, e3})

	q5 := ecs.query(world, ecs.term(world, ecs.build_pair(ecs.Wildcard, apple)))

	expect_query_matched_entities(t, q5, []ecs.EntityId{e2, e3, e5})

	ecs.set_pair(world, e4, &Posseses{42}, apple)

	expect_query_matched_entities(t, q4, []ecs.EntityId{e2, e3})
	expect_query_matched_entities(t, q5, []ecs.EntityId{e2, e3, e4, e5})

	ecs.delete(world, e3)
	ecs.delete(world, e4)

	expect_query_matched_entities(t, q4, []ecs.EntityId{e2})
	expect_query_matched_entities(t, q5, []ecs.EntityId{e2, e5})
}

@(test)
row_data_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	apple := ecs.new(world)
	pear := ecs.new(world)
	possesses := ecs.declare(world, Posseses)

	e1 := ecs.new(world)
	e2 := ecs.new(world)
	e3 := ecs.new(world)
	e4 := ecs.new(world)

	ecs.set_pair(world, e1, &Posseses{10}, apple)
	ecs.set_pair(world, e2, &Posseses{10}, pear)
	ecs.set_pair(world, e3, &Posseses{100}, apple)
	ecs.set_pair(world, e4, &Posseses{100}, pear)

	q1 := ecs.query(world, ecs.term(world, Posseses, apple))

	expect_query_matched_entities(t, q1, []ecs.EntityId{e1, e3})

	it := ecs.query_iter(q1)

	for ecs.iter_next_match(&it) {
		col := ecs.column(&it, 0)

		for chunk in ecs.iter_next_chunk(&it) {
			for row := 0; row < len(chunk.entities); row += 1 {
				p := ecs.row_data_mut(chunk, col, row, Posseses)

				p.amount *= 2
			}
		}
	}

	testing.expect_value(t, ecs.get_pair(world, e1, Posseses, apple).amount, 20)
	testing.expect_value(t, ecs.get_pair(world, e2, Posseses, pear).amount, 10)
	testing.expect_value(t, ecs.get_pair(world, e3, Posseses, apple).amount, 200)
	testing.expect_value(t, ecs.get_pair(world, e4, Posseses, pear).amount, 100)
}

@(test)
query_unique_pair_entity_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	apple := ecs.new(world)
	pear := ecs.new(world)
	possesses := ecs.declare(world, Posseses)

	ecs.add(world, possesses, ecs.UniquePair)

	e1 := ecs.new(world)
	e2 := ecs.new(world)

	ecs.set_pair(world, e1, &Posseses{10}, apple)
	ecs.set_pair(world, e2, &Posseses{10}, pear)

	q := ecs.query(world, ecs.term(world, Posseses, ecs.Wildcard))

	expect_query_matched_entities(t, q, []ecs.EntityId{e1, e2})

	it := ecs.query_iter(q)

	for ecs.iter_next_match(&it) {
		possessed_entity := ecs.unique_pair_entity(&it, 0)

		for chunk in ecs.iter_next_chunk(&it) {
			for row := 0; row < len(chunk.entities); row += 1 {
				entity := chunk.entities[row]

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
}

@(test)
query_not_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo: ecs.EntityId = ecs.declare(world, Foo)
	bar: ecs.EntityId = ecs.declare(world, Bar)
	plop: ecs.EntityId = ecs.new(world)
	plap: ecs.EntityId = ecs.new(world)

	e1 := ecs.new(world)
	e2 := ecs.new(world)
	e3 := ecs.new(world)

	ecs.set(world, e1, &Foo{42})
	ecs.add(world, e1, plop)

	ecs.set(world, e2, &Foo{142})
	ecs.set(world, e2, &Bar{200})
	ecs.add(world, e2, plap)

	ecs.set(world, e3, &Foo{300})

	q1 := ecs.query(world, ecs.term(world, Foo), ecs.not_term(world, Bar))
	q2 := ecs.query(world, ecs.term(world, Foo), ecs.not_term(world, plop))
	q3 := ecs.query(world, ecs.term(world, Foo), ecs.not_term(world, plap))
	q4 := ecs.query(
		world,
		ecs.term(world, Foo),
		ecs.not_term(world, Bar),
		ecs.not_term(world, plop),
	)

	expect_query_matched_entities(t, q1, []ecs.EntityId{e1, e3})
	expect_query_matched_entities(t, q2, []ecs.EntityId{e2, e3})
	expect_query_matched_entities(t, q3, []ecs.EntityId{e1, e3})
	expect_query_matched_entities(t, q4, []ecs.EntityId{e3})
}

@(test)
query_optional_term_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo: ecs.EntityId = ecs.declare(world, Foo)
	bar: ecs.EntityId = ecs.declare(world, Bar)
	plop: ecs.EntityId = ecs.new(world)
	plap: ecs.EntityId = ecs.new(world)

	e1 := ecs.new(world)
	e2 := ecs.new(world)
	e3 := ecs.new(world)

	ecs.set(world, e1, &Foo{42})
	ecs.add(world, e1, plop)

	ecs.set(world, e2, &Foo{142})
	ecs.set(world, e2, &Bar{200})
	ecs.add(world, e2, plap)

	ecs.set(world, e3, &Foo{300})

	q1 := ecs.query(world, ecs.term(world, Foo), ecs.term(world, Bar, optional = true))
	q2 := ecs.query(
		world,
		ecs.term(world, Foo),
		ecs.term(world, Bar, optional = true),
		ecs.term(world, plap),
	)

	expect_query_matched_entities(t, q1, []ecs.EntityId{e1, e2, e3})
	expect_query_matched_entities(t, q2, []ecs.EntityId{e2})
}

@(test)
query_fetch_optional_data :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo: ecs.EntityId = ecs.declare(world, Foo)
	bar: ecs.EntityId = ecs.declare(world, Bar)
	plop: ecs.EntityId = ecs.new(world)
	plap: ecs.EntityId = ecs.new(world)

	e1 := ecs.new(world)
	e2 := ecs.new(world)
	e3 := ecs.new(world)

	ecs.set(world, e1, &Foo{42})
	ecs.add(world, e1, plop)

	ecs.set(world, e2, &Foo{142})
	ecs.set(world, e2, &Bar{200})
	ecs.add(world, e2, plap)

	ecs.set(world, e3, &Foo{300})

	q := ecs.query(world, ecs.term(world, Foo), ecs.term(world, Bar, optional = true))
	it := ecs.iter(q)

	for ecs.iter_next_match(&it) {
		foo_col := ecs.column(&it, 0)
		bar_col, bar_exists := ecs.column_maybe(&it, 1)

		for chunk in ecs.iter_next_chunk(&it) {
			for row := 0; row < len(chunk.entities); row += 1 {
				entity := chunk.entities[row]

				if bar_exists {
					bar := ecs.row_data(chunk, bar_col, row, Bar)

					testing.expect_value(t, chunk.entities[row], e2)
				} else {
					testing.expect(t, entity == e1 || entity == e3)
				}
			}
		}
	}
}

@(test)
query_parent_component_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo: ecs.EntityId = ecs.declare(world, Foo)
	bar: ecs.EntityId = ecs.declare(world, Bar)

	e1 := ecs.new(world)
	e2 := ecs.new(world)
	e3 := ecs.new(world)

	ecs.set(world, e1, &Foo{42})

	ecs.set(world, e2, &Foo{12})
	ecs.set(world, e2, &Bar{142})

	ecs.set(world, e3, &Foo{242})

	ecs.set_parent(world, e2, e1)
	ecs.set_parent(world, e3, e2)

	q1 := ecs.query(world, ecs.term(world, Foo))
	it := ecs.query_iter(q1)

	expect_query_matched_entities(t, q1, []ecs.EntityId{e1, e2, e3})

	for i := 0; i < len(it.matches); i += 1 {
		ecs.iter_next_match(&it)

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

@(test)
query_cascade_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	ecs.declare(world, Foo)

	e2 := ecs.new(world)
	e5 := ecs.new(world)
	e1 := ecs.new(world)
	e4 := ecs.new(world)
	e3 := ecs.new(world)

	ecs.set_parent(world, e2, e1)
	ecs.set_parent(world, e3, e2)
	ecs.set_parent(world, e4, e3)
	ecs.set_parent(world, e5, e4)

	ecs.set(world, e1, &Foo{0})
	ecs.set(world, e2, &Foo{0})
	ecs.set(world, e3, &Foo{0})
	ecs.set(world, e4, &Foo{0})
	ecs.set(world, e5, &Foo{0})

	q1 := ecs.query(world, ecs.term(world, Foo), cascade = true)

	expect_query_matched_entities_in_order(t, q1, []ecs.EntityId{e1, e2, e3, e4, e5})
}

@(test)
filter_match_entities_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo: ecs.EntityId = ecs.declare(world, Foo, "Foo")
	bar: ecs.EntityId = ecs.declare(world, Bar, "Bar")
	plop: ecs.EntityId = ecs.new(world, "Plop")
	plap: ecs.EntityId = ecs.new(world, "Plap")

	e1 := ecs.new(world, "E1")
	e2 := ecs.new(world, "E2")
	e3 := ecs.new(world, "E3")

	ecs.set(world, e1, &Foo{42})
	ecs.set(world, e1, &Bar{4242})

	ecs.set(world, e2, &Foo{24})
	ecs.set(world, e2, &Bar{2424})

	ecs.add(world, e3, bar)
	ecs.add(world, e3, plop)

	expect_filter_matched_entities(
		t,
		world,
		[]ecs.EntityId{e3},
		ecs.term(world, bar),
		ecs.term(world, plop),
	)

	expect_filter_matched_entities(
		t,
		world,
		[]ecs.EntityId{e1, e2},
		ecs.term(world, Foo),
		ecs.term(world, Bar),
	)

	it := ecs.iter(
		world,
		ecs.term(world, Foo),
		ecs.term(world, Bar),
		allocator = context.temp_allocator,
	)

	for ecs.iter_next_match(&it) {
		foo_col := ecs.column(&it, 0)
		bar_col := ecs.column(&it, 1)

		for chunk in ecs.iter_next_chunk(&it) {
			for row := 0; row < len(chunk.entities); row += 1 {
				entity := chunk.entities[row]

				if entity == e1 {
					foo := ecs.row_data(chunk, foo_col, row, Foo)
					bar := ecs.row_data(chunk, bar_col, row, Bar)

					testing.expect_value(t, 42, foo.v)
					testing.expect_value(t, 4242, bar.v)
				} else if entity == e2 {
					foo := ecs.row_data(chunk, foo_col, row, Foo)
					bar := ecs.row_data(chunk, bar_col, row, Bar)

					testing.expect_value(t, 24, foo.v)
					testing.expect_value(t, 2424, bar.v)
				}
			}
		}
	}
}
