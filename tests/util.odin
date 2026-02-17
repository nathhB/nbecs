package tests

import ecs ".."
import "core:fmt"
import "core:log"
import "core:slice"
import "core:testing"

expect_archetype_columns :: proc(
	t: ^testing.T,
	archetype: ^ecs.Archetype,
	component_ids: []ecs.EntityId,
	loc := #caller_location,
) {
	set := ecs.ComponentSet{}

	ecs.component_set_init(&set, component_ids)
	defer ecs.component_set_deinit(&set)
	testing.expect_value(t, archetype.component_set.hash, set.hash, loc)
}

expect_find_archetype :: proc(
	t: ^testing.T,
	world: ^ecs.World,
	component_ids: []ecs.EntityId,
	loc := #caller_location,
) -> ^ecs.Archetype {
	set := ecs.ComponentSet{}

	ecs.component_set_init(&set, component_ids)
	defer ecs.component_set_deinit(&set)

	if set.hash not_in world.archetypes.nodes {
		testing.fail(t, loc)
	}

	return &world.archetypes.nodes[set.hash].archetype
}

expect_no_archetype :: proc(
	t: ^testing.T,
	world: ^ecs.World,
	component_ids: []ecs.EntityId,
	loc := #caller_location,
) {
	set := ecs.ComponentSet{}

	ecs.component_set_init(&set, component_ids)
	defer ecs.component_set_deinit(&set)

	if set.hash in world.archetypes.nodes {
		testing.fail(t, loc)
	}
}

expect_archetype_index :: proc(
	t: ^testing.T,
	world: ^ecs.World,
	index_key: ecs.EntityId,
	expected_archetypes: []^ecs.Archetype,
	loc := #caller_location,
) {
	index_map := make(map[u64]^ecs.Archetype)
	defer delete(index_map)

	if index_key in world.archetype_index {
		for hash, archetype in world.archetype_index[index_key] {
			index_map[hash] = archetype
		}
	}

	for archetype in expected_archetypes {
		hash := archetype.component_set.hash
		indexed_archetype, exists := index_map[hash]

		testing.expectf(
			t,
			exists && indexed_archetype == archetype,
			"archetype was not present in the index: %w",
			archetype,
			loc = loc,
		)

		if exists {
			delete_key(&index_map, hash)
		}
	}

	if (len(index_map) > 0) {
		log.error("Unexpected archetypes were found in the index:", loc)

		for _, archetype in index_map {
			archetype_str := ecs.archetype_to_str(world, archetype)
			defer delete(archetype_str)

			log.error(archetype_str, loc)
		}

		testing.fail(t, loc)
	}
}

expect_entity_archetype :: proc(
	t: ^testing.T,
	world: ^ecs.World,
	entity: ecs.EntityId,
	expected_archetype: ^ecs.Archetype,
	loc := #caller_location,
) {
	testing.expectf(t, ecs.ecs_is_valid(world, entity), "entity is not valid", loc = loc)
	testing.expect_value(t, world.entities[entity].chunk.archetype, expected_archetype, loc)
}

expect_query_matched_archetypes :: proc(
	t: ^testing.T,
	query: ^ecs.Query,
	expected_archetypes: []^ecs.Archetype,
	loc := #caller_location,
) {
	match_count := 0

	it := ecs.query_iter(query)

	for ecs.query_iter_next_match(&it) {
		match_count += 1

		testing.expectf(
			t,
			slice.contains(expected_archetypes, it.current_match.archetype),
			"query matched an unexpected archetype",
			loc = loc,
		)
	}

	testing.expectf(
		t,
		match_count == len(expected_archetypes),
		"query did not match the expected number of archetypes (actual: %d, expected: %d)",
		match_count,
		len(expected_archetypes),
		loc = loc,
	)
}

expect_query_matched_entities :: proc(
	t: ^testing.T,
	query: ^ecs.Query,
	expected_entities: []ecs.EntityId,
	loc := #caller_location,
) {
	match_count := 0

	it := ecs.query_iter(query)

	for ecs.query_iter_next_match(&it) {
		chunk := it.current_chunk

		for row := 0; row < len(chunk.entities); row += 1 {
			entity := chunk.entities[row]
			match_count += 1

			testing.expectf(
				t,
				slice.contains(expected_entities, entity),
				"query matched an unexpected entity: %d",
				entity,
				loc = loc,
			)
		}
	}

	testing.expectf(
		t,
		match_count == len(expected_entities),
		"query did not match the expected number of entities (actual: %d, expected: %d)",
		match_count,
		len(expected_entities),
		loc = loc,
	)
}

expect_query_matched_entities_in_order :: proc(
	t: ^testing.T,
	query: ^ecs.Query,
	expected_entities: []ecs.EntityId,
	loc := #caller_location,
) {
	it := ecs.query_iter(query)
	matched_entities := make([dynamic]ecs.EntityId)
	defer delete(matched_entities)

	for ecs.query_iter_next_match(&it) {
		chunk := it.current_chunk

		for row := 0; row < len(chunk.entities); row += 1 {
			entity := chunk.entities[row]

			append(&matched_entities, entity)
		}
	}

	testing.expectf(
		t,
		slice.equal(matched_entities[:], expected_entities),
		"query did not match the expected entities (actual: %w, expected: %w)",
		matched_entities,
		expected_entities,
		loc = loc,
	)
}

expect_filter_matched_entities :: proc(
	t: ^testing.T,
	world: ^ecs.World,
	expected_entities: []ecs.EntityId,
	terms: ..ecs.QueryTerm,
	loc := #caller_location,
) {
	match_count := 0

	it := ecs.filter_iter(world, ..terms, allocator = context.temp_allocator)

	for ecs.query_iter_next_match(&it) {
		chunk := it.current_chunk

		for row := 0; row < len(chunk.entities); row += 1 {
			entity := chunk.entities[row]
			match_count += 1

			testing.expectf(
				t,
				slice.contains(expected_entities, entity),
				"query matched an unexpected entity: %d",
				entity,
				loc = loc,
			)
		}
	}

	testing.expectf(
		t,
		match_count == len(expected_entities),
		"query did not match the expected number of entities (actual: %d, expected: %d)",
		match_count,
		len(expected_entities),
		loc = loc,
	)
}

expect_archetype_node_add_edge_count :: proc(
	t: ^testing.T,
	world: ^ecs.World,
	archetype: ^ecs.Archetype,
	expected_add_edge_count: int,
) {
	node := world.archetypes.nodes[archetype.component_set.hash]

	testing.expect_value(t, len(node.add_nodes), expected_add_edge_count)
}

expect_chunk_entities :: proc(
	t: ^testing.T,
	chunk: ^ecs.Archetype_Chunk,
	expected_entities: ..ecs.EntityId,
) {
	testing.expect_value(t, len(chunk.entities), len(expected_entities))

	for entity, idx in chunk.entities {
		testing.expect_value(t, entity, expected_entities[idx])
	}
}

expect_array_contains :: proc(
	t: ^testing.T,
	array: $T/[]$E,
	expected: ..E,
	loc := #caller_location,
) {
	testing.expect_value(t, len(array), len(expected), loc)

	for value in expected {
		testing.expect(t, slice.contains(array, value), loc = loc)
	}
}

log_debug_world :: proc(world: ^ecs.World) {
	debug_str := ecs.archetype_graph_to_str(world)
	defer delete(debug_str)

	log.debug(debug_str)
}
