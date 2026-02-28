package nbecs

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import vmem "core:mem/virtual"
import "core:strings"

Pair_Array :: [dynamic]EntityId

Archetype :: struct {
	is_root:              bool,
	is_watcher:           bool,
	node:                 ^ArchetypeNode,
	component_set:        Component_Set,
	chunks:               [dynamic]^Archetype_Chunk,
	component_column_map: map[EntityId]int,
	pairs:                map[EntityId]Pair_Array,
	active_chunk:         ^Archetype_Chunk,
	chunk_capacity:       int,
	chunk_free_list:      [dynamic]^Archetype_Chunk,
	allocator:            mem.Allocator,
	depth:                int,
	column_count:         int,
}

archetype_init :: proc(
	world: ^World,
	archetype: ^Archetype,
	component_set: ^Component_Set,
	chunk_capacity := 0,
	chunk_count := 1,
	is_root := false,
	allocator := context.allocator,
) {
	assert(chunk_count > 0)

	archetype.is_root = is_root
	archetype.component_set = component_set^
	archetype.chunks = make([dynamic]^Archetype_Chunk, allocator)
	archetype.component_column_map = make(map[EntityId]int, allocator)
	archetype.chunk_capacity =
		chunk_capacity > 0 ? chunk_capacity : compute_chunk_capacity(world, component_set)
	archetype.allocator = allocator

	col_idx := 0
	for component_id, _ in component_set.components {
		component_size := get_component_size(world, component_id)

		if component_size > 0 {
			archetype.component_column_map[component_id] = col_idx

			col_idx += 1
		}

		is_pair := is_pair(component_id)

		if is_pair {
			add_pair(world, archetype, component_id)
		}

		if !archetype.is_watcher && is_pair {
			first, _ := pair_split(component_id)

			archetype.is_watcher = first == get_type_id(world, Watcher)
		}
	}

	archetype.column_count = col_idx

	for i := 0; i < chunk_count; i += 1 {
		get_or_create_chunk(world, archetype)
	}

	archetype.active_chunk = archetype.chunks[0]
}

archetype_deinit :: proc(archetype: ^Archetype) {
	for chunk in archetype.chunks {
		delete_slice(chunk.buffer)
	}

	for chunk in pop_safe(&archetype.chunk_free_list) {
		delete_slice(chunk.buffer)
	}

	if archetype.pairs != nil {
		for _, pairs in archetype.pairs {
			delete_dynamic_array(pairs)
		}

		delete_map(archetype.pairs)
	}

	delete_dynamic_array(archetype.chunks)
	delete_map(archetype.component_column_map)

	if archetype.chunk_free_list != nil {
		delete_dynamic_array(archetype.chunk_free_list)
	}

	set_destroy(&archetype.component_set)
}

archetype_has :: proc(archetype: ^Archetype, component_id: EntityId) -> bool {
	return !archetype.is_root && set_has(&archetype.component_set, component_id)
}

archetype_add_entity :: proc(
	world: ^World,
	archetype: ^Archetype,
	entity: EntityId,
) -> (
	chunk: ^Archetype_Chunk,
	row: int,
) {
	chunk = archetype.active_chunk
	chunk_count := len(chunk.entities)

	if chunk_count == archetype.chunk_capacity {
		chunk = get_or_create_chunk(world, archetype)
		archetype.active_chunk = chunk
	}

	row = archetype_chunk_add_entity(chunk, entity)

	return
}

archetype_delete_entity :: proc(
	archetype: ^Archetype,
	chunk: ^Archetype_Chunk,
	row: int,
) -> EntityId {
	moved_entity := archetype_chunk_delete_entity(chunk, row)

	if len(chunk.entities) == 0 && len(archetype.chunks) > 1 {
		last_chunk := archetype.chunks[len(archetype.chunks) - 1]
		last_chunk.index = chunk.index

		unordered_remove(&archetype.chunks, chunk.index)

		if chunk == archetype.active_chunk {
			assert(chunk.index == archetype.active_chunk.index)

			archetype.active_chunk = archetype.chunks[0]
		}

		if archetype.chunk_free_list == nil {
			archetype.chunk_free_list = make([dynamic]^Archetype_Chunk, archetype.allocator)
		}

		append(&archetype.chunk_free_list, chunk)
	}

	return moved_entity
}

archetype_get_pair :: proc(archetype: ^Archetype, entity: EntityId) -> EntityId {
	assert(!is_pair(entity))

	if archetype.pairs == nil {
		return 0
	}

	pairs, exists := archetype.pairs[entity]

	if !exists {
		return 0
	}

	return pairs[0]
}

archetype_get_pairs :: proc(archetype: ^Archetype, entity: EntityId) -> []EntityId {
	assert(!is_pair(entity))

	if archetype.pairs == nil {
		return nil
	}

	pairs, exists := archetype.pairs[entity]

	if !exists {
		return nil
	}

	return pairs[:]
}

compute_chunk_capacity :: proc(world: ^World, component_set: ^Component_Set) -> int {
	overhead := size_of(Archetype_Chunk) + 64
	entity_size := size_of(EntityId)

	for component_id, _ in component_set.components {
		component_size := get_component_size(world, component_id)

		if component_size > 0 {
			overhead += size_of(Archetype_Column)
			entity_size += component_size
		}
	}

	return (Archetype_ChunkSize_Bytes - overhead) / entity_size
}

@(private = "file")
get_or_create_chunk :: proc(world: ^World, archetype: ^Archetype) -> ^Archetype_Chunk {
	chunk: ^Archetype_Chunk

	if archetype.chunk_free_list != nil && len(archetype.chunk_free_list) > 0 {
		chunk = pop(&archetype.chunk_free_list)
	} else {
		chunk_buffer, err := mem.alloc_bytes(
			Archetype_ChunkSize_Bytes,
			allocator = archetype.allocator,
		)
		ensure(err == nil)

		chunk = archetype_chunk_create(
			world,
			archetype,
			archetype.chunk_capacity,
			&archetype.component_set,
			chunk_buffer,
		)
	}

	chunk.index = len(archetype.chunks)
	append(&archetype.chunks, chunk)

	return chunk
}

@(private = "file")
add_pair :: proc(world: ^World, archetype: ^Archetype, pair: EntityId) {
	assert(is_pair(pair))

	if archetype.pairs == nil {
		archetype.pairs = make(map[EntityId]Pair_Array, archetype.allocator)
	}

	first, second := pair_split(pair)

	if first not_in archetype.pairs {
		archetype.pairs[first] = make(Pair_Array)
	}

	if first == ChildOf_Id {
		assert(exists(world, second))

		archetype.depth = get_entity_depth(world, second) + 1
	}

	append(&archetype.pairs[first], pair)
}
