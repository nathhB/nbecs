package tests

import "core:testing"
import ecs ".."

@(test)
entity_add_set_tests :: proc(t: ^testing.T) {
    world := ecs.ecs_create()
    defer ecs.ecs_destroy(world)

    foo: ecs.EntityId = ecs.ecs_declare(world, Foo)
    bar: ecs.EntityId = ecs.ecs_declare(world, Bar)
    plop: ecs.EntityId = ecs.ecs_new(world)
    plap: ecs.EntityId = ecs.ecs_new(world)

    e1 := ecs.ecs_new(world)
    e2 := ecs.ecs_new(world)

    testing.expect(t, !ecs.ecs_has(world, e1, foo))
    testing.expect(t, !ecs.ecs_has(world, e1, bar))
    testing.expect(t, !ecs.ecs_has(world, e1, plop))
    testing.expect(t, !ecs.ecs_has(world, e1, plap))

    testing.expect(t, !ecs.ecs_has(world, e2, foo))
    testing.expect(t, !ecs.ecs_has(world, e2, bar))
    testing.expect(t, !ecs.ecs_has(world, e2, plop))
    testing.expect(t, !ecs.ecs_has(world, e2, plap))

    ecs.ecs_add(world, e1, plop)
    ecs.ecs_add(world, e2, plap)

    ecs.ecs_set(world, e1, &Foo{42})

    testing.expect(t, ecs.ecs_has(world, e1, foo))
    testing.expect(t, !ecs.ecs_has(world, e1, bar))
    testing.expect(t, ecs.ecs_has(world, e1, plop))
    testing.expect(t, !ecs.ecs_has(world, e1, plap))

    testing.expect(t, !ecs.ecs_has(world, e2, foo))
    testing.expect(t, !ecs.ecs_has(world, e2, bar))
    testing.expect(t, !ecs.ecs_has(world, e2, plop))
    testing.expect(t, ecs.ecs_has(world, e2, plap))

    testing.expect_value(t, ecs.ecs_get(world, e1, Foo).v, 42)

    ecs.ecs_add(world, e2, e1)

    testing.expect(t, !ecs.ecs_has(world, e2, foo))
    testing.expect(t, !ecs.ecs_has(world, e2, bar))
    testing.expect(t, !ecs.ecs_has(world, e2, plop))
    testing.expect(t, ecs.ecs_has(world, e2, plap))
    testing.expect(t, ecs.ecs_has(world, e2, e1))

    testing.expect(t, !ecs.ecs_add(world, e2, e1))

    ecs.ecs_set(world, e2, &Bar{100})

    testing.expect(t, !ecs.ecs_has(world, e2, foo))
    testing.expect(t, ecs.ecs_has(world, e2, bar))
    testing.expect(t, !ecs.ecs_has(world, e2, plop))
    testing.expect(t, ecs.ecs_has(world, e2, plap))
    testing.expect(t, ecs.ecs_has(world, e2, e1))

    testing.expect_value(t, ecs.ecs_get(world, e2, Bar).v, 100)

    ecs.ecs_get_mut(world, e2, Bar).v = 200

    testing.expect_value(t, ecs.ecs_get(world, e2, Bar).v, 200)

    ecs.ecs_set(world, e2, &Bar{300})

    testing.expect_value(t, ecs.ecs_get(world, e2, Bar).v, 300)
    testing.expect_value(t, len(world.archetypes.nodes), 8)
}

@(test)
entity_delete_tests :: proc(t: ^testing.T) {
    world := ecs.ecs_create()
    defer ecs.ecs_destroy(world)

    foo: ecs.EntityId = ecs.ecs_declare(world, Foo)
    e1 := ecs.ecs_new(world)

    ecs.ecs_add(world, e1, foo)
    ecs.ecs_delete(world, e1)

    testing.expect(t, !ecs.ecs_is_valid(world, e1))
}

@(test)
entity_remove_tests :: proc(t: ^testing.T) {
    world := ecs.ecs_create()
    defer ecs.ecs_destroy(world)

    foo: ecs.EntityId = ecs.ecs_declare(world, Foo)
    bar: ecs.EntityId = ecs.ecs_declare(world, Bar)
    plop: ecs.EntityId = ecs.ecs_new(world)
    plap: ecs.EntityId = ecs.ecs_new(world)

    e1 := ecs.ecs_new(world)
    e2 := ecs.ecs_new(world)

    ecs.ecs_set(world, e1, &Foo{24})
    ecs.ecs_add(world, e1, plop)

    ecs.ecs_set(world, e2, &Foo{24})
    ecs.ecs_set(world, e2, &Bar{42})
    ecs.ecs_add(world, e2, plap)

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

    testing.expect(t, ecs.ecs_remove(world, e2, plap))
    testing.expect(t, !ecs.ecs_remove(world, e2, plap))

    testing.expect(t, ecs.ecs_has(world, e2, foo))
    testing.expect(t, ecs.ecs_has(world, e2, bar))
    testing.expect(t, !ecs.ecs_has(world, e2, plop))
    testing.expect(t, !ecs.ecs_has(world, e2, plap)) 

    testing.expect_value(t, len(a1_chunk.entities), 1)
    testing.expect_value(t, len(a2_chunk.entities), 1)
    testing.expect_value(t, len(a3_chunk.entities), 0)
    testing.expect_value(t, len(a4_chunk.entities), 0)

    testing.expect(t, ecs.ecs_remove(world, e1, foo))

    testing.expect_value(t, len(world.archetypes.nodes), 8)

    arch5 := expect_find_archetype(t, world, []ecs.EntityId{plop})
    a5_chunk := arch5.chunks[0]

    testing.expect_value(t, len(a1_chunk.entities), 0)
    testing.expect_value(t, len(a2_chunk.entities), 1)
    testing.expect_value(t, len(a3_chunk.entities), 0)
    testing.expect_value(t, len(a4_chunk.entities), 0)
    testing.expect_value(t, len(a5_chunk.entities), 1)

    testing.expect(t, ecs.ecs_remove(world, e2, foo))
    testing.expect(t, ecs.ecs_remove(world, e2, bar))

    testing.expect_value(t, len(world.archetypes.nodes), 9)

    arch6 := expect_find_archetype(t, world, []ecs.EntityId{bar})
    a6_chunk := arch6.chunks[0]

    testing.expect_value(t, len(a1_chunk.entities), 0)
    testing.expect_value(t, len(a2_chunk.entities), 0)
    testing.expect_value(t, len(a3_chunk.entities), 0)
    testing.expect_value(t, len(a4_chunk.entities), 0)
    testing.expect_value(t, len(a5_chunk.entities), 1)
    testing.expect_value(t, len(a6_chunk.entities), 0)

    testing.expect(t, ecs.ecs_add(world, e2, plop))

    testing.expect_value(t, len(a1_chunk.entities), 0)
    testing.expect_value(t, len(a2_chunk.entities), 0)
    testing.expect_value(t, len(a3_chunk.entities), 0)
    testing.expect_value(t, len(a4_chunk.entities), 0)
    testing.expect_value(t, len(a5_chunk.entities), 2)
    testing.expect_value(t, len(a6_chunk.entities), 0)
}

@(test)
parent_children_tests :: proc(t: ^testing.T) {
    world := ecs.ecs_create()
    defer ecs.ecs_destroy(world)

    e1 := ecs.ecs_new(world, "E1")
    e2 := ecs.ecs_new(world, "E2")
    e3 := ecs.ecs_new(world, "E3")
    e4 := ecs.ecs_new(world, "E4")
    e5 := ecs.ecs_new(world, "E5")
    e6 := ecs.ecs_new(world, "E6")

    testing.expect_value(t, ecs.ecs_get_parent(world, e1), 0)
    testing.expect_value(t, ecs.ecs_get_parent(world, e2), 0)
    testing.expect_value(t, ecs.ecs_get_parent(world, e3), 0)
    testing.expect_value(t, ecs.ecs_get_parent(world, e4), 0)

    ecs.ecs_set_parent(world, e2, e1)
    ecs.ecs_set_parent(world, e3, e1)
    ecs.ecs_set_parent(world, e4, e3)
    ecs.ecs_set_parent(world, e5, e6)

    testing.expect_value(t, ecs.ecs_get_parent(world, e1), 0)
    testing.expect_value(t, ecs.ecs_get_parent(world, e2), e1)
    testing.expect_value(t, ecs.ecs_get_parent(world, e3), e1)
    testing.expect_value(t, ecs.ecs_get_parent(world, e4), e3)
    testing.expect_value(t, ecs.ecs_get_parent(world, e5), e6)

    testing.expect(t, ecs.ecs_has_pair(world, e2, ecs.ChildOf, e1))
    testing.expect(t, ecs.ecs_has_pair(world, e3, ecs.ChildOf, e1))
    testing.expect(t, ecs.ecs_has_pair(world, e4, ecs.ChildOf, e3))
    testing.expect(t, ecs.ecs_has_pair(world, e5, ecs.ChildOf, e6))

    // log_debug_world(world)

    ecs.ecs_delete(world, e1)

    // log_debug_world(world)

    testing.expect(t, !ecs.ecs_is_valid(world, e1))
    testing.expect(t, ecs.ecs_is_valid(world, e2))
    testing.expect(t, ecs.ecs_is_valid(world, e3))
    testing.expect(t, ecs.ecs_is_valid(world, e4))
    testing.expect(t, ecs.ecs_is_valid(world, e5))
    testing.expect(t, ecs.ecs_is_valid(world, e6))

    testing.expect_value(t, ecs.ecs_get_parent(world, e2), 0)
    testing.expect_value(t, ecs.ecs_get_parent(world, e3), 0)
    testing.expect_value(t, ecs.ecs_get_parent(world, e4), e3)
    testing.expect_value(t, ecs.ecs_get_parent(world, e5), e6)
}

@(test)
change_entity_parent_tests :: proc(t: ^testing.T) {
    world := ecs.ecs_create()
    defer ecs.ecs_destroy(world)

    e1 := ecs.ecs_new(world, "E1")
    e2 := ecs.ecs_new(world, "E2")
    e3 := ecs.ecs_new(world, "E3")
    e4 := ecs.ecs_new(world, "E4")
    e5 := ecs.ecs_new(world, "E5")
    e6 := ecs.ecs_new(world, "E6")

    testing.expect_value(t, ecs.ecs_get_parent(world, e2), 0)
    ecs.ecs_set_parent(world, e2, e1)
    testing.expect_value(t, ecs.ecs_get_parent(world, e2), e1)
    ecs.ecs_set_parent(world, e2, e3)
    testing.expect_value(t, ecs.ecs_get_parent(world, e2), e3)
    ecs.ecs_set_parent(world, e2, e4)
    testing.expect_value(t, ecs.ecs_get_parent(world, e2), e4)
    ecs.ecs_delete(world, e4)
    testing.expect_value(t, ecs.ecs_get_parent(world, e2), 0)
}

@(test)
find_tests :: proc(t: ^testing.T) {
    world := ecs.ecs_create()
    defer ecs.ecs_destroy(world)

    e1 := ecs.ecs_new(world, "E1")
    e2 := ecs.ecs_new(world, "E2")
    e3 := ecs.ecs_new(world, "E3")

    e, exists := ecs.ecs_find(world, "E1")
    testing.expect(t, exists)
    testing.expect_value(t, e, e1)
    e, exists = ecs.ecs_find(world, "E2")
    testing.expect(t, exists)
    testing.expect_value(t, e, e2)
    e, exists = ecs.ecs_find(world, "E3")
    testing.expect(t, exists)
    testing.expect_value(t, e, e3)
    e, exists = ecs.ecs_find(world, "E4")
    testing.expect(t, !exists)
    testing.expect_value(t, e, 0)

    ecs.ecs_delete(world, e2)

    e, exists = ecs.ecs_find(world, "E2")
    testing.expect(t, !exists)
    testing.expect_value(t, e, 0)
}
