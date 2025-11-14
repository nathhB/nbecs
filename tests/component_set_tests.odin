package tests

import "core:testing"
import "core:slice"
import ecs ".."

@(test)
component_set_tests :: proc(t: ^testing.T) {
    foo: ecs.EntityId = 1
    bar: ecs.EntityId = 2
    plop: ecs.EntityId = 42
    plap: ecs.EntityId = 24

    set1 := ecs.ComponentSet{}
    set2 := ecs.ComponentSet{}
    set3 := ecs.ComponentSet{}
    set4 := ecs.ComponentSet{}
    set5 := ecs.ComponentSet{}

    ecs.component_set_init(&set1, []ecs.EntityId{foo, bar})
    defer ecs.component_set_deinit(&set1)
    ecs.component_set_init(&set2, []ecs.EntityId{bar, foo})
    defer ecs.component_set_deinit(&set2)
    ecs.component_set_init(&set3, []ecs.EntityId{bar, foo, plop})
    defer ecs.component_set_deinit(&set3)
    ecs.component_set_init(&set4, []ecs.EntityId{bar, foo, plop, plap})
    defer ecs.component_set_deinit(&set4)
    ecs.component_set_init(&set5, []ecs.EntityId{plop, foo, plap, bar})
    defer ecs.component_set_deinit(&set5) 

    testing.expect(t, set1.hash == set2.hash)
    testing.expect(t, set3.hash != set2.hash)
    testing.expect(t, set3.hash != set4.hash)
    testing.expect(t, set4.hash == set5.hash)
    testing.expect(t, set1.hash != set5.hash)

    testing.expect(t, ecs.component_set_has(&set1, foo))
    testing.expect(t, ecs.component_set_has(&set1, bar))
    testing.expect(t, !ecs.component_set_has(&set1, plop))
    testing.expect(t, ecs.component_set_has(&set4, plop))
    testing.expect(t, ecs.component_set_has(&set5, plop))

    set6 := ecs.component_set_add(&set2, plop)
    defer ecs.component_set_deinit(&set6)

    testing.expect(t, set6.hash == set3.hash)

    set7 := ecs.component_set_remove(&set6, plop)
    defer ecs.component_set_deinit(&set7)

    testing.expect(t, set7.hash == set1.hash)

    set8 := ecs.component_set_remove(&set5, plap)
    defer ecs.component_set_deinit(&set8)

    testing.expect(t, set8.hash == set3.hash)

    set9 := ecs.component_set_remove(&set8, plop)
    defer ecs.component_set_deinit(&set9)

    testing.expect(t, set9.hash == set1.hash)

    set10 := ecs.component_set_remove(&set3, foo)
    defer ecs.component_set_deinit(&set10)

    set11 := ecs.ComponentSet{}

    ecs.component_set_init(&set11, []ecs.EntityId{plop, plap})
    defer ecs.component_set_deinit(&set11)
}

@(test)
component_set_delete_relationships_tests :: proc(t: ^testing.T) {
    foo: ecs.EntityId = 1
    bar: ecs.EntityId = 2
    plop: ecs.EntityId = 42
    plap: ecs.EntityId = 24
    pair1 := ecs.ecs_build_pair(foo, bar)
    pair2 := ecs.ecs_build_pair(bar, foo)
    pair3 := ecs.ecs_build_pair(plop, plap)

    set1 := ecs.ComponentSet{}

    ecs.component_set_init(&set1, []ecs.EntityId{foo, pair1, pair2, pair3})
    defer ecs.component_set_deinit(&set1)

    testing.expect(t, ecs.component_set_has(&set1, foo))
    testing.expect(t, ecs.component_set_has(&set1, pair1))
    testing.expect(t, ecs.component_set_has(&set1, pair2))
    testing.expect(t, ecs.component_set_has(&set1, pair3))

    set2 := ecs.component_set_remove_relationship(&set1, foo)
    defer ecs.component_set_deinit(&set2)

    testing.expect(t, ecs.component_set_has(&set2, foo))
    testing.expect(t, !ecs.component_set_has(&set2, pair1))
    testing.expect(t, !ecs.component_set_has(&set2, pair2))
    testing.expect(t, ecs.component_set_has(&set2, pair3))
}
