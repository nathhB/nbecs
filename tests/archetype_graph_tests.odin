package tests

import ecs ".."
import "core:log"
import "core:testing"

@(test)
archetype_graph_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	foo: ecs.Entity = ecs.new(world)
	bar: ecs.Entity = ecs.new(world)
	plop: ecs.Entity = ecs.new(world)
	plap: ecs.Entity = ecs.new(world)

	testing.expect_value(t, len(world.archetypes.nodes), 3)
	testing.expect(t, world.archetypes.root == world.archetypes.nodes[0])

	n1 := ecs.archetype_graph_add(world, &world.archetypes, world.archetypes.root, foo)
	n2 := ecs.archetype_graph_add(world, &world.archetypes, world.archetypes.root, bar)
	n3 := ecs.archetype_graph_add(world, &world.archetypes, world.archetypes.root, plop)
	n4 := ecs.archetype_graph_add(world, &world.archetypes, world.archetypes.root, plap)

	testing.expect_value(t, len(world.archetypes.nodes), 7)
	testing.expect_value(t, len(world.archetypes.root.add_nodes), 5)

	expect_archetype_columns(t, &n1.archetype, []ecs.Entity{foo})
	expect_archetype_columns(t, &n2.archetype, []ecs.Entity{bar})
	expect_archetype_columns(t, &n3.archetype, []ecs.Entity{plop})
	expect_archetype_columns(t, &n4.archetype, []ecs.Entity{plap})

	n5 := ecs.archetype_graph_add(world, &world.archetypes, n1, bar)

	testing.expect_value(t, len(world.archetypes.nodes), 8)
	expect_archetype_columns(t, &n5.archetype, []ecs.Entity{foo, bar})

	n6 := ecs.archetype_graph_add(world, &world.archetypes, n5, plop)

	testing.expect_value(t, len(world.archetypes.nodes), 9)
	expect_archetype_columns(t, &n6.archetype, []ecs.Entity{foo, bar, plop})

	expect_archetype_index(
		t,
		world,
		foo,
		[]^ecs.Archetype{&n1.archetype, &n5.archetype, &n6.archetype},
	)
	expect_archetype_index(
		t,
		world,
		bar,
		[]^ecs.Archetype{&n2.archetype, &n5.archetype, &n6.archetype},
	)
	expect_archetype_index(t, world, plop, []^ecs.Archetype{&n3.archetype, &n6.archetype})
	expect_archetype_index(t, world, plap, []^ecs.Archetype{&n4.archetype})
}

