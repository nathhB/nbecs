package tests

import ecs ".."
import "core:testing"

@(test)
id_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	e1 := ecs.new(world)
	e2 := ecs.new(world)

	testing.expect_value(t, e1 & 0x00FFFFFF, u64(ecs.get_entity_id(e1)))
	testing.expect_value(t, e2 & 0x00FFFFFF, u64(ecs.get_entity_id(e2)))

	testing.expect_value(t, 0, int(ecs.get_generation(e1)))
	testing.expect_value(t, 0, int(ecs.get_generation(e2)))

	id_with_gen1 := ecs.build_entity_id(ecs.get_entity_id(e1), 10)
	id_with_gen2 := ecs.build_entity_id(ecs.get_entity_id(e2), 42)

	testing.expect_value(t, e1 & 0x00FFFFFF, u64(ecs.get_entity_id(id_with_gen1)))
	testing.expect_value(t, e2 & 0x00FFFFFF, u64(ecs.get_entity_id(id_with_gen2)))

	testing.expect_value(t, int(ecs.get_generation(id_with_gen1)), 10)
	testing.expect_value(t, int(ecs.get_generation(id_with_gen2)), 42)
}

@(test)
id_flags_tests :: proc(t: ^testing.T) {
	world := ecs.create()
	defer ecs.destroy(world)

	expected_e1 := world.next_entity_id
	e1 := ecs.new(world, flags = 0x01)
	expected_e2 := world.next_entity_id
	e2 := ecs.new(world, flags = 0x11)
	expected_e3 := world.next_entity_id
	e3 := ecs.new(world, flags = 0xFF)

	testing.expect_value(t, ecs.get_entity_id(e1), expected_e1)
	testing.expect_value(t, ecs.get_entity_id(e2), expected_e2)
	testing.expect_value(t, ecs.get_entity_id(e3), expected_e3)

	testing.expect_value(t, ecs.get_entity_flags(e1), 0x01)
	testing.expect_value(t, ecs.get_entity_flags(e2), 0x11)
	testing.expect_value(t, ecs.get_entity_flags(e3), 0xFF)
}
