package tests

import "core:testing"
import "core:log"
import ecs ".."

@(test)
archetype_graph_tests :: proc(t: ^testing.T) {
    world := ecs.ecs_create()
    defer ecs.ecs_destroy(world)

    foo: ecs.EntityId = ecs.ecs_new(world)
    bar: ecs.EntityId = ecs.ecs_new(world)
    plop: ecs.EntityId = ecs.ecs_new(world)
    plap: ecs.EntityId = ecs.ecs_new(world)

    testing.expect_value(t, len(world.archetypes.nodes), 3)
    testing.expect(t, world.archetypes.root == world.archetypes.nodes[0])

    n1 := ecs.archetype_graph_add(world, &world.archetypes, world.archetypes.root, foo)
    n2 := ecs.archetype_graph_add(world, &world.archetypes, world.archetypes.root, bar)
    n3 := ecs.archetype_graph_add(world, &world.archetypes, world.archetypes.root, plop)
    n4 := ecs.archetype_graph_add(world, &world.archetypes, world.archetypes.root, plap)

    testing.expect_value(t, len(world.archetypes.nodes), 7)
    testing.expect_value(t, len(world.archetypes.root.add_nodes), 6)

    expect_archetype_columns(t, &n1.archetype, []ecs.EntityId{foo})
    expect_archetype_columns(t, &n2.archetype, []ecs.EntityId{bar})
    expect_archetype_columns(t, &n3.archetype, []ecs.EntityId{plop})
    expect_archetype_columns(t, &n4.archetype, []ecs.EntityId{plap})

    n5 := ecs.archetype_graph_add(world, &world.archetypes, n1, bar)

    testing.expect_value(t, len(world.archetypes.nodes), 8)
    expect_archetype_columns(t, &n5.archetype, []ecs.EntityId{foo, bar})

    n6 := ecs.archetype_graph_add(world, &world.archetypes, n5, plop)

    testing.expect_value(t, len(world.archetypes.nodes), 9)
    expect_archetype_columns(t, &n6.archetype, []ecs.EntityId{foo, bar, plop})

    expect_archetype_index(t, world, foo, []^ecs.Archetype{&n1.archetype, &n5.archetype, &n6.archetype})
    expect_archetype_index(t, world, bar, []^ecs.Archetype{&n2.archetype, &n5.archetype, &n6.archetype})
    expect_archetype_index(t, world, plop, []^ecs.Archetype{&n3.archetype, &n6.archetype})
    expect_archetype_index(t, world, plap, []^ecs.Archetype{&n4.archetype})
}
