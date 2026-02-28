package tests

import ecs ".."
import "core:slice"
import "core:testing"

@(test)
component_set_tests :: proc(t: ^testing.T) {
	foo: ecs.EntityId = 1
	bar: ecs.EntityId = 2
	plop: ecs.EntityId = 42
	plap: ecs.EntityId = 24

	set1 := ecs.set_build([]ecs.EntityId{foo, bar})
	defer ecs.set_destroy(&set1)
	set2 := ecs.set_build([]ecs.EntityId{bar, foo})
	defer ecs.set_destroy(&set2)
	set3 := ecs.set_build([]ecs.EntityId{bar, foo, plop})
	defer ecs.set_destroy(&set3)
	set4 := ecs.set_build([]ecs.EntityId{bar, foo, plop, plap})
	defer ecs.set_destroy(&set4)
	set5 := ecs.set_build([]ecs.EntityId{plop, foo, plap, bar})
	defer ecs.set_destroy(&set5)

	testing.expect(t, set1.hash == set2.hash)
	testing.expect(t, set3.hash != set2.hash)
	testing.expect(t, set3.hash != set4.hash)
	testing.expect(t, set4.hash == set5.hash)
	testing.expect(t, set1.hash != set5.hash)

	testing.expect(t, ecs.set_has(&set1, foo))
	testing.expect(t, ecs.set_has(&set1, bar))
	testing.expect(t, !ecs.set_has(&set1, plop))
	testing.expect(t, ecs.set_has(&set4, plop))
	testing.expect(t, ecs.set_has(&set5, plop))

	set6 := ecs.set_add(&set2, plop)
	defer ecs.set_destroy(&set6)

	testing.expect(t, set6.hash == set3.hash)

	set7 := ecs.set_remove(&set6, plop)
	defer ecs.set_destroy(&set7)

	testing.expect(t, set7.hash == set1.hash)

	set8 := ecs.set_remove(&set5, plap)
	defer ecs.set_destroy(&set8)

	testing.expect(t, set8.hash == set3.hash)

	set9 := ecs.set_remove(&set8, plop)
	defer ecs.set_destroy(&set9)

	testing.expect(t, set9.hash == set1.hash)

	set10 := ecs.set_remove(&set3, foo)
	defer ecs.set_destroy(&set10)

	set11 := ecs.set_build([]ecs.EntityId{plop, plap})
	defer ecs.set_destroy(&set11)
}

@(test)
component_set_delete_relationships_tests :: proc(t: ^testing.T) {
	foo: ecs.EntityId = 1
	bar: ecs.EntityId = 2
	plop: ecs.EntityId = 42
	plap: ecs.EntityId = 24
	pair1 := ecs.build_pair(foo, bar)
	pair2 := ecs.build_pair(bar, foo)
	pair3 := ecs.build_pair(plop, plap)

	set1 := ecs.set_build([]ecs.EntityId{foo, pair1, pair2, pair3})
	defer ecs.set_destroy(&set1)

	testing.expect(t, ecs.set_has(&set1, foo))
	testing.expect(t, ecs.set_has(&set1, pair1))
	testing.expect(t, ecs.set_has(&set1, pair2))
	testing.expect(t, ecs.set_has(&set1, pair3))

	set2 := ecs.set_remove_relationship(&set1, foo)
	defer ecs.set_destroy(&set2)

	testing.expect(t, ecs.set_has(&set2, foo))
	testing.expect(t, !ecs.set_has(&set2, pair1))
	testing.expect(t, !ecs.set_has(&set2, pair2))
	testing.expect(t, ecs.set_has(&set2, pair3))
}
