package tests

import ecs ".."
import "core:log"
import "core:testing"

@(test)
archetype_creation_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo: ecs.EntityId = ecs.ecs_declare(world, Foo)
	bar: ecs.EntityId = ecs.ecs_declare(world, Bar)
	plop: ecs.EntityId = ecs.ecs_new(world)
	plap: ecs.EntityId = ecs.ecs_new(world)

	set1 := ecs.ComponentSet{}
	set2 := ecs.ComponentSet{}
	set3 := ecs.ComponentSet{}

	ecs.component_set_init(&set1, []ecs.EntityId{foo, bar})
	ecs.component_set_init(&set2, []ecs.EntityId{bar, foo})
	defer ecs.component_set_deinit(&set2)
	ecs.component_set_init(&set3, []ecs.EntityId{bar, foo, plop})

	arch1 := ecs.Archetype{}
	arch2 := ecs.Archetype{}

	ecs.archetype_init(world, &arch1, &set1)
	defer ecs.archetype_deinit(&arch1)

	ecs.archetype_init(world, &arch2, &set3)
	defer ecs.archetype_deinit(&arch2)

	testing.expect(t, set1.hash == arch1.component_set.hash)
	testing.expect(t, set2.hash == arch1.component_set.hash)
	testing.expect(t, set3.hash == arch2.component_set.hash)

	testing.expect_value(t, len(arch1.chunks), 1)
	testing.expect_value(t, len(arch2.chunks), 1)

	arch1_chunk := arch1.chunks[0]
	arch2_chunk := arch2.chunks[0]

	testing.expect_value(t, arch1_chunk.column_count, 2)
	testing.expect_value(t, arch2_chunk.column_count, 2)
	testing.expect_value(t, arch1_chunk.columns[0].item_size, size_of(Foo))
	testing.expect_value(t, arch1_chunk.columns[1].item_size, size_of(Bar))

	testing.expect(t, ecs.archetype_has(&arch1, foo))
	testing.expect(t, ecs.archetype_has(&arch1, bar))
	testing.expect(t, !ecs.archetype_has(&arch1, plop))
	testing.expect(t, !ecs.archetype_has(&arch1, plap))

	testing.expect(t, ecs.archetype_has(&arch2, foo))
	testing.expect(t, ecs.archetype_has(&arch2, bar))
	testing.expect(t, ecs.archetype_has(&arch2, plop))
	testing.expect(t, !ecs.archetype_has(&arch2, plap))
}

@(test)
archetype_data_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo: ecs.EntityId = ecs.ecs_declare(world, Foo)
	foo2: ecs.EntityId = ecs.ecs_declare(world, Foo2)
	bar: ecs.EntityId = ecs.ecs_declare(world, Bar)
	plop: ecs.EntityId = ecs.ecs_new(world)

	set1 := ecs.ComponentSet{}
	set2 := ecs.ComponentSet{}

	ecs.component_set_init(&set1, []ecs.EntityId{foo, bar})
	ecs.component_set_init(&set2, []ecs.EntityId{bar, foo2, plop})

	arch1 := ecs.Archetype{}
	arch2 := ecs.Archetype{}

	ecs.archetype_init(world, &arch1, &set1)
	defer ecs.archetype_deinit(&arch1)
	ecs.archetype_init(world, &arch2, &set2)
	defer ecs.archetype_deinit(&arch2)

	a1_chunk, a1_row1 := ecs.archetype_add_entity(world, &arch1, 1)
	_, a1_row2 := ecs.archetype_add_entity(world, &arch1, 2)
	a2_chunk, a2_row1 := ecs.archetype_add_entity(world, &arch2, 3)
	_, a2_row2 := ecs.archetype_add_entity(world, &arch2, 4)
	_, a2_row3 := ecs.archetype_add_entity(world, &arch2, 5)

	testing.expect_value(t, a1_row1, 0)
	testing.expect_value(t, a1_row2, 1)
	testing.expect_value(t, a2_row1, 0)
	testing.expect_value(t, a2_row2, 1)
	testing.expect_value(t, a2_row3, 2)

	ecs.archetype_chunk_set_data(a1_chunk, arch1.component_column_map[foo], a1_row1, &Foo{42})
	ecs.archetype_chunk_set_data(a1_chunk, arch1.component_column_map[bar], a1_row2, &Bar{24})

	data1 := ecs.archetype_chunk_get_data(a1_chunk, arch1.component_column_map[foo], a1_row1)
	data2 := ecs.archetype_chunk_get_data(a1_chunk, arch1.component_column_map[bar], a1_row2)
	r_foo1 := (^Foo)(data1)
	r_bar1 := (^Bar)(data2)

	testing.expect_value(t, a1_chunk.entities[a1_row1], 1)
	testing.expect_value(t, a1_chunk.entities[a1_row2], 2)
	testing.expect_value(t, r_foo1.v, 42)
	testing.expect_value(t, r_bar1.v, 24)

	ecs.archetype_chunk_set_data(
		a2_chunk,
		arch2.component_column_map[foo2],
		a2_row3,
		&Foo2{1, 2, 3, true},
	)

	data3 := ecs.archetype_chunk_get_data(a2_chunk, arch2.component_column_map[foo2], a2_row3)
	r_foo2 := (^Foo2)(data3)

	testing.expect_value(t, a2_chunk.entities[a2_row1], 3)
	testing.expect_value(t, a2_chunk.entities[a2_row2], 4)
	testing.expect_value(t, a2_chunk.entities[a2_row3], 5)
	testing.expect_value(t, r_foo2.v1, 1)
	testing.expect_value(t, r_foo2.v2, 2)
	testing.expect_value(t, r_foo2.v3, 3)
	testing.expect_value(t, r_foo2.v4, true)
}

@(test)
archetype_entity_deletion_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo: ecs.EntityId = ecs.ecs_declare(world, Foo)
	foo2: ecs.EntityId = ecs.ecs_declare(world, Foo2)
	bar: ecs.EntityId = ecs.ecs_declare(world, Bar)

	set1 := ecs.ComponentSet{}

	ecs.component_set_init(&set1, []ecs.EntityId{foo, bar, foo2})

	arch1 := ecs.Archetype{}

	ecs.archetype_init(world, &arch1, &set1)
	defer ecs.archetype_deinit(&arch1)

	chunk, _ := ecs.archetype_add_entity(world, &arch1, 1)
	ecs.archetype_add_entity(world, &arch1, 2)
	ecs.archetype_add_entity(world, &arch1, 3)
	ecs.archetype_add_entity(world, &arch1, 4)

	testing.expect_value(t, len(chunk.entities), 4)

	moved_entity := ecs.archetype_chunk_delete_entity(chunk, 0)

	testing.expect_value(t, len(chunk.entities), 3)
	testing.expect_value(t, moved_entity, 4)
	testing.expect_value(t, chunk.entities[0], 4)

	moved_entity = ecs.archetype_chunk_delete_entity(chunk, 0)
	testing.expect_value(t, len(chunk.entities), 2)
	testing.expect_value(t, moved_entity, 3)
	testing.expect_value(t, chunk.entities[0], 3)
	testing.expect_value(t, chunk.entities[1], 2)

	moved_entity = ecs.archetype_chunk_delete_entity(chunk, 1)
	testing.expect_value(t, moved_entity, 0) // last row so not moving any entity
	testing.expect_value(t, len(chunk.entities), 1)
	testing.expect_value(t, chunk.entities[0], 3)
}

@(test)
archetype_copy_row_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo: ecs.EntityId = ecs.ecs_declare(world, Foo)
	foo2: ecs.EntityId = ecs.ecs_declare(world, Foo2)
	bar: ecs.EntityId = ecs.ecs_declare(world, Bar)

	set1 := ecs.ComponentSet{}
	set2 := ecs.ComponentSet{}

	ecs.component_set_init(&set1, []ecs.EntityId{foo, bar})
	ecs.component_set_init(&set2, []ecs.EntityId{foo, bar, foo2})

	arch1 := ecs.Archetype{}
	arch2 := ecs.Archetype{}

	ecs.archetype_init(world, &arch1, &set1)
	defer ecs.archetype_deinit(&arch1)
	ecs.archetype_init(world, &arch2, &set2)
	defer ecs.archetype_deinit(&arch2)

	_, a1_row1 := ecs.archetype_add_entity(world, &arch1, 1)
	_, a1_row2 := ecs.archetype_add_entity(world, &arch1, 2)

	a1_chunk := arch1.chunks[0]
	a2_chunk := arch2.chunks[0]

	ecs.archetype_chunk_set_data(a1_chunk, arch1.component_column_map[foo], a1_row1, &Foo{42})
	ecs.archetype_chunk_set_data(a1_chunk, arch1.component_column_map[bar], a1_row1, &Bar{24})
	ecs.archetype_chunk_set_data(a1_chunk, arch1.component_column_map[foo], a1_row2, &Foo{142})
	ecs.archetype_chunk_set_data(a1_chunk, arch1.component_column_map[bar], a1_row2, &Bar{124})

	_, a2_row1 := ecs.archetype_add_entity(world, &arch2, 3)
	_, a2_row2 := ecs.archetype_add_entity(world, &arch2, 4)

	ecs.archetype_chunk_copy_row(a1_chunk, a2_chunk, a1_row2, a2_row1)
	ecs.archetype_chunk_copy_row(a1_chunk, a2_chunk, a1_row1, a2_row2)

	data1 := ecs.archetype_chunk_get_data(a2_chunk, arch2.component_column_map[foo], a2_row1)
	data2 := ecs.archetype_chunk_get_data(a2_chunk, arch2.component_column_map[bar], a2_row1)
	data3 := ecs.archetype_chunk_get_data(a2_chunk, arch2.component_column_map[foo], a2_row2)
	data4 := ecs.archetype_chunk_get_data(a2_chunk, arch2.component_column_map[bar], a2_row2)

	testing.expect_value(t, ((^Foo)(data1)).v, 142)
	testing.expect_value(t, ((^Bar)(data2)).v, 124)
	testing.expect_value(t, ((^Foo)(data3)).v, 42)
	testing.expect_value(t, ((^Bar)(data4)).v, 24)

	ecs.archetype_chunk_copy_row(a2_chunk, a1_chunk, a2_row1, a1_row1)
	ecs.archetype_chunk_copy_row(a2_chunk, a1_chunk, a2_row2, a1_row2)

	data5 := ecs.archetype_chunk_get_data(a1_chunk, arch1.component_column_map[foo], a1_row1)
	data6 := ecs.archetype_chunk_get_data(a1_chunk, arch1.component_column_map[bar], a1_row1)
	data7 := ecs.archetype_chunk_get_data(a1_chunk, arch1.component_column_map[foo], a1_row2)
	data8 := ecs.archetype_chunk_get_data(a1_chunk, arch1.component_column_map[bar], a1_row2)

	testing.expect_value(t, ((^Foo)(data5)).v, 142)
	testing.expect_value(t, ((^Bar)(data6)).v, 124)
	testing.expect_value(t, ((^Foo)(data7)).v, 42)
	testing.expect_value(t, ((^Bar)(data8)).v, 24)
}

@(test)
archetype_pairs_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	eats: ecs.EntityId = ecs.ecs_new(world, "Eats")
	likes: ecs.EntityId = ecs.ecs_new(world, "Likes")
	apple: ecs.EntityId = ecs.ecs_new(world, "Apple")
	pear: ecs.EntityId = ecs.ecs_new(world, "Pear")
	pair1 := ecs.ecs_build_pair(eats, apple)
	pair2 := ecs.ecs_build_pair(eats, pear)
	pair3 := ecs.ecs_build_pair(likes, apple)
	pair4 := ecs.ecs_build_pair(likes, pear)

	set := ecs.ComponentSet{}
	ecs.component_set_init(&set, []ecs.EntityId{pair1, pair2, pair3, pair4})
	arch := ecs.Archetype{}
	ecs.archetype_init(world, &arch, &set)
	defer ecs.archetype_deinit(&arch)

	pairs1 := ecs.archetype_get_pairs(&arch, eats)
	pairs2 := ecs.archetype_get_pairs(&arch, likes)

	expect_array_contains(t, pairs1, pair1, pair2)
	expect_array_contains(t, pairs2, pair3, pair4)
}

@(test)
archetype_unique_pair_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	eats: ecs.EntityId = ecs.ecs_new(world, "Eats")
	likes: ecs.EntityId = ecs.ecs_new(world, "Likes")
	apple: ecs.EntityId = ecs.ecs_new(world, "Apple")
	pear: ecs.EntityId = ecs.ecs_new(world, "Pear")
	pair1 := ecs.ecs_build_pair(eats, apple)
	pair2 := ecs.ecs_build_pair(eats, pear)
	pair3 := ecs.ecs_build_pair(likes, apple)
	pair4 := ecs.ecs_build_pair(likes, pear)

	ecs.ecs_add(world, eats, ecs.UniquePair)
	ecs.ecs_add(world, likes, ecs.UniquePair)

	set := ecs.ComponentSet{}
	ecs.component_set_init(&set, []ecs.EntityId{pair1, pair4})
	arch := ecs.Archetype{}
	ecs.archetype_init(world, &arch, &set)
	defer ecs.archetype_deinit(&arch)

	testing.expect_value(t, ecs.archetype_get_pair(&arch, eats), pair1)
	testing.expect_value(t, ecs.archetype_get_pair(&arch, likes), pair4)

	set2 := ecs.ComponentSet{}
	ecs.component_set_init(&set2, []ecs.EntityId{pair2, pair3})
	arch2 := ecs.Archetype{}
	ecs.archetype_init(world, &arch2, &set2)
	defer ecs.archetype_deinit(&arch2)

	testing.expect_value(t, ecs.archetype_get_pair(&arch2, eats), pair2)
	testing.expect_value(t, ecs.archetype_get_pair(&arch2, likes), pair3)
}

@(test)
archetype_chunks_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo: ecs.EntityId = ecs.ecs_declare(world, Foo)
	bar: ecs.EntityId = ecs.ecs_declare(world, Bar)

	set := ecs.ComponentSet{}

	ecs.component_set_init(&set, []ecs.EntityId{foo, bar})

	arch := ecs.Archetype{}

	ecs.archetype_init(world, &arch, &set, 3)
	defer ecs.archetype_deinit(&arch)

	testing.expect_value(t, len(arch.chunks), 1)

	ecs.archetype_add_entity(world, &arch, 1)
	ecs.archetype_add_entity(world, &arch, 2)
	ecs.archetype_add_entity(world, &arch, 3)
	ecs.archetype_add_entity(world, &arch, 4)
	ecs.archetype_add_entity(world, &arch, 5)
	ecs.archetype_add_entity(world, &arch, 6)
	ecs.archetype_add_entity(world, &arch, 7)

	testing.expect_value(t, len(arch.chunks), 3)

	chunk1 := arch.chunks[0]
	chunk2 := arch.chunks[1]
	chunk3 := arch.chunks[2]

	expect_chunk_entities(t, chunk1, 1, 2, 3)
	expect_chunk_entities(t, chunk2, 4, 5, 6)
	expect_chunk_entities(t, chunk3, 7)

	testing.expect(t, arch.chunk_free_list == nil)

	ecs.archetype_delete_entity(&arch, chunk3, 0)

	testing.expect(t, arch.chunk_free_list != nil)
	testing.expect_value(t, len(arch.chunk_free_list), 1)
	testing.expect_value(t, len(arch.chunks), 2)
	testing.expect(t, arch.chunk_free_list[0] == chunk3)

	ecs.archetype_add_entity(world, &arch, 8)
	ecs.archetype_add_entity(world, &arch, 9)

	testing.expect_value(t, len(arch.chunk_free_list), 0)
	testing.expect_value(t, len(arch.chunks), 3)
	testing.expect(t, arch.chunks[2] == chunk3)

	expect_chunk_entities(t, chunk1, 1, 2, 3)
	expect_chunk_entities(t, chunk2, 4, 5, 6)
	expect_chunk_entities(t, chunk3, 8, 9)

	ecs.archetype_delete_entity(&arch, chunk2, 0)
	ecs.archetype_delete_entity(&arch, chunk2, 0)
	ecs.archetype_delete_entity(&arch, chunk2, 0)

	testing.expect_value(t, len(arch.chunk_free_list), 1)
	testing.expect_value(t, len(arch.chunks), 2)
	testing.expect(t, arch.chunks[0] == chunk1)
	testing.expect(t, arch.chunks[1] == chunk3)

	expect_chunk_entities(t, chunk1, 1, 2, 3)
	expect_chunk_entities(t, chunk3, 8, 9)

	ecs.archetype_delete_entity(&arch, chunk1, 0)
	ecs.archetype_delete_entity(&arch, chunk1, 0)
	ecs.archetype_delete_entity(&arch, chunk1, 0)

	testing.expect_value(t, len(arch.chunk_free_list), 2)
	testing.expect_value(t, len(arch.chunks), 1)
	testing.expect(t, arch.chunks[0] == chunk3)

	expect_chunk_entities(t, chunk3, 8, 9)
}

@(test)
archetype_chunk_memory_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo: ecs.EntityId = ecs.ecs_declare(world, Foo)
	bar: ecs.EntityId = ecs.ecs_declare(world, Bar)

	set := ecs.ComponentSet{}

	ecs.component_set_init(&set, []ecs.EntityId{foo, bar})

	arch := ecs.Archetype{}

	ecs.archetype_init(world, &arch, &set)
	defer ecs.archetype_deinit(&arch)

	chunk1 := arch.chunks[0]

	// testing.expect(t, chunk1.arena.total_used < ecs.Archetype_ChunkSize_Bytes)
	testing.expect_value(t, chunk1.capacity, ecs.compute_chunk_capacity(world, &set))

	for i := 0; i < chunk1.capacity; i += 1 {
		ecs.archetype_add_entity(world, &arch, u64(i + 1))
	}

	testing.expect_value(t, len(chunk1.entities), chunk1.capacity)
	testing.expect_value(t, len(arch.chunks), 1)
}
