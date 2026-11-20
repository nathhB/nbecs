package tests

import ecs ".."
import "core:testing"

expect_prefab_storage_consistent :: proc(t: ^testing.T, world: ^ecs.World) {
	rows := 0
	for _, node in world.archetypes.nodes {
		for chunk in node.archetype.chunks {
			for row in 0 ..< chunk.count {
				entity := chunk.entities[row]
				entry, exists := world.entities[entity]
				testing.expect(t, exists)
				testing.expect_value(t, entry.chunk, chunk)
				testing.expect_value(t, entry.row, row)
				rows += 1
			}
		}
	}
	testing.expect_value(t, rows, len(world.entities))
}

@(test)
prefab_instance_storage_survives_unrelated_moves :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)
	ecs.declare(world, Foo)
	ecs.declare(world, Bar)
	prefab := ecs.prefab(world)
	ecs.set(world, prefab, &Foo{42})
	ecs.set(world, prefab, &Bar{24})
	blank := ecs.new(world)
	instance := ecs.new_instance_of(world, prefab)
	expect_prefab_storage_consistent(t, world)

	// This used to swap a ghost row into blank's slot and corrupt instance.row.
	ecs.set(world, blank, &Foo{1})
	expect_prefab_storage_consistent(t, world)
	testing.expect_value(t, ecs.get(world, instance, Foo).v, 42)
	ecs.remove(world, instance, Bar)
	ecs.delete(world, instance)
	ecs.delete(world, blank)
	expect_prefab_storage_consistent(t, world)
}

@(test)
prefab_instances_cross_chunk_boundaries_and_delete :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)
	ecs.declare(world, Foo)
	ecs.declare(world, Bar)
	prefab := ecs.prefab(world)
	ecs.set(world, prefab, &Foo{42})
	ecs.set(world, prefab, &Bar{24})
	instances: [2500]ecs.Entity
	for &instance in instances {
		instance = ecs.new_instance_of(world, prefab)
	}
	expect_prefab_storage_consistent(t, world)
	for instance, i in instances {
		ecs.set(world, instance, &Foo{i})
		testing.expect_value(t, ecs.get(world, instance, Bar).v, 24)
	}
	// Alternating deletions exercise swap removal, empty chunks, and row updates.
	for instance, i in instances {
		if i % 2 == 0 {ecs.delete(world, instance)}
	}
	expect_prefab_storage_consistent(t, world)
	for instance, i in instances {
		if i % 2 != 0 {
			testing.expect_value(t, ecs.get(world, instance, Foo).v, i)
			ecs.delete(world, instance)
		}
	}
	expect_prefab_storage_consistent(t, world)
	testing.expect_value(t, ecs.get(world, prefab, Foo).v, 42)
}

@(test)
empty_prefab_instances_have_one_row :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)
	prefab := ecs.prefab(world)
	first := ecs.new_instance_of(world, prefab)
	second := ecs.new_instance_of(world, prefab)
	expect_prefab_storage_consistent(t, world)
	ecs.delete(world, first)
	ecs.delete(world, second)
	expect_prefab_storage_consistent(t, world)
}

collect_prefab_iterator_entities :: proc(it: ecs.Query_Iterator) -> []ecs.Entity {
	it := it
	entities := make([dynamic]ecs.Entity, context.temp_allocator)
	for ecs.iter_next_match(&it) {
		for chunk in ecs.iter_next_chunk(&it) {
			append(&entities, ..chunk.entities[:chunk.count])
		}
	}
	return entities[:]
}

@(test)
prefab_query_filter_policy :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)
	ecs.declare(world, Foo, "Foo")
	prefab := ecs.prefab(world)
	ecs.set(world, prefab, &Foo{42})
	instance := ecs.new_instance_of(world, prefab)

	cached := ecs.query(world, ecs.term(world, Foo))
	expect_query_matched_entities(t, cached, []ecs.Entity{instance})
	expect_filter_matched_entities(
		t,
		world,
		[]ecs.Entity{instance},
		ecs.term(world, Foo),
	)

	cached_all := ecs.query(world, ecs.term(world, Foo), include_prefabs = true)
	expect_query_matched_entities(t, cached_all, []ecs.Entity{prefab, instance})
	it := ecs.iter(world, ecs.term(world, Foo), include_prefabs = true)
	entities := collect_prefab_iterator_entities(it)
	testing.expect_value(t, len(entities), 2)

	templates := ecs.query(world, "Foo Prefab", include_prefabs = true)
	expect_query_matched_entities(t, templates, []ecs.Entity{prefab})
	it = ecs.iter(
		world,
		ecs.term(world, Foo),
		ecs.term(world, ecs.Prefab),
		include_prefabs = true,
	)
	entities = collect_prefab_iterator_entities(it)
	testing.expect_value(t, len(entities), 1)
	testing.expect_value(t, entities[0], prefab)

	// Cached queries must apply the same policy to archetypes created later.
	ecs.declare(world, Bar)
	later := ecs.prefab(world)
	ecs.set(world, later, &Bar{1})
	ecs.set(world, later, &Foo{2})
	expect_query_matched_entities(t, cached, []ecs.Entity{instance})
	expect_query_matched_entities(
		t,
		cached_all,
		[]ecs.Entity{prefab, instance, later},
	)
	expect_query_matched_entities(t, templates, []ecs.Entity{prefab, later})
}

@(test)
prefab_queries_without_positive_terms :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)
	prefab := ecs.prefab(world)
	blank := ecs.new(world)
	for include_prefabs in ([2]bool{false, true}) {
		cached := ecs.query(world, include_prefabs = include_prefabs)
		entities := collect_prefab_iterator_entities(ecs.iter(cached))
		expected := len(world.entities) - (include_prefabs ? 0 : 1)
		testing.expect_value(t, len(entities), expected)
		filtered := collect_prefab_iterator_entities(
			ecs.iter(world, include_prefabs = include_prefabs),
		)
		testing.expect_value(t, len(filtered), expected)
	}
	// A negative-only query must consider entities outside the excluded index.
	q := ecs.query(world, ecs.not_term(world, ecs.Prefab), include_prefabs = true)
	entities := collect_prefab_iterator_entities(ecs.iter(q))
	testing.expect_value(t, len(entities), len(world.entities) - 1)
}

@(test)
prefab_hierarchy_traversal_and_multiple_instances :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)
	ecs.declare(world, Foo)
	prefab := ecs.prefab(world)
	child := ecs.prefab(world)
	grandchild := ecs.prefab(world)
	ecs.set_parent(world, child, prefab)
	ecs.set_parent(world, grandchild, child)
	ecs.set(world, child, &Foo{12})
	ecs.set(world, grandchild, &Foo{34})
	hidden := ecs.get_children(world, prefab, allocator = context.temp_allocator)
	testing.expect_value(t, len(hidden), 0)
	visible := ecs.get_children(
		world,
		prefab,
		allocator = context.temp_allocator,
		include_prefabs = true,
	)
	testing.expect_value(t, len(visible), 1)
	testing.expect_value(t, visible[0], child)

	for _ in 0 ..< 3 {
		instance := ecs.new_instance_of(world, prefab)
		children := ecs.get_children(
			world,
			instance,
			allocator = context.temp_allocator,
		)
		testing.expect_value(t, len(children), 1)
		cloned_child := children[0]
		testing.expect_value(t, ecs.get_parent(world, cloned_child), instance)
		testing.expect_value(t, ecs.get(world, cloned_child, Foo).v, 12)
		grandchildren := ecs.get_children(
			world,
			cloned_child,
			allocator = context.temp_allocator,
		)
		testing.expect_value(t, len(grandchildren), 1)
		testing.expect_value(t, ecs.get(world, grandchildren[0], Foo).v, 34)
		testing.expect_value(t, ecs.get_entity_depth(world, grandchildren[0]), 2)
		ecs.set(world, cloned_child, &Foo{99})
	}
	testing.expect_value(t, ecs.get(world, child, Foo).v, 12)
	expect_prefab_storage_consistent(t, world)
}
