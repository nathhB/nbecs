package tests

import "core:testing"
import ecs ".."

@(test)
simple_prefab_tests :: proc(t: ^testing.T) {
    world := ecs.ecs_create()
    defer ecs.ecs_destroy(world)

    foo: ecs.EntityId = ecs.ecs_declare(world, Foo)
    bar: ecs.EntityId = ecs.ecs_declare(world, Bar)
    plop: ecs.EntityId = ecs.ecs_new(world)
    plap: ecs.EntityId = ecs.ecs_new(world)
    prefab1 := ecs.ecs_prefab(world, "Prefab1")

    ecs.ecs_set(world, prefab1, &Foo{42})
    ecs.ecs_set(world, prefab1, &Bar{1000})

    testing.expect(t, ecs.ecs_is_prefab(world, prefab1))

    // log_debug_world(world)

    instance1 := ecs.ecs_new_instance_of(world, prefab1, "Instance1")
    instance2 := ecs.ecs_new_instance_of(world, prefab1, "Instance2")

    ecs.ecs_set(world, instance1, &Bar{2000})

    ecs.ecs_set(world, instance2, &Foo{150})
    ecs.ecs_set(world, instance2, &Bar{300})

    // log_debug_world(world)

    testing.expect(t, !ecs.ecs_is_prefab(world, instance1))
    testing.expect(t, !ecs.ecs_is_prefab(world, instance2))
    testing.expect(t, ecs.ecs_has(world, instance1, Foo))
    testing.expect(t, ecs.ecs_has(world, instance1, Bar))
    testing.expect(t, ecs.ecs_has(world, instance2, Foo))
    testing.expect(t, ecs.ecs_has(world, instance2, Bar))

    i1_foo := ecs.ecs_get(world, instance1, Foo)
    i1_bar := ecs.ecs_get(world, instance1, Bar)
    i2_foo := ecs.ecs_get(world, instance2, Foo)
    i2_bar := ecs.ecs_get(world, instance2, Bar)

    testing.expect_value(t, i1_foo.v, 42)
    testing.expect_value(t, i1_bar.v, 2000)
    testing.expect_value(t, i2_foo.v, 150)
    testing.expect_value(t, i2_bar.v, 300)

    // make sure prefab is not match in queries
    q1 := ecs.query_build(world, ecs.query_term(world, Foo), ecs.query_term(world, Bar))

    expect_query_matched_entities(t, q1, []ecs.EntityId{instance1, instance2})
}
