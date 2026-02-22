package nbecs

import "core:fmt"
import "core:log"
import "core:mem"
import vmem "core:mem/virtual"

Archetype_ChunkSize_Bytes :: 16_000

Archetype_Column :: struct {
	component_id: EntityId,
	item_size:    int,
	rows:         rawptr,
}

Archetype_Chunk :: struct {
	capacity:     int,
	column_count: int,
	index:        int,
	archetype:    ^Archetype,
	columns:      []Archetype_Column,
	entities:     [dynamic]EntityId,
	buffer:       []u8,
}

archetype_chunk_create :: proc(
	world: ^World,
	archetype: ^Archetype,
	capacity: int,
	component_set: ^ComponentSet,
	buffer: []u8,
) -> ^Archetype_Chunk {
	chunk_arena := vmem.Arena{}
	err := vmem.arena_init_buffer(&chunk_arena, buffer)
	ensure(err == nil)

	chunk_allocator := vmem.arena_allocator(&chunk_arena)
	chunk := new(Archetype_Chunk, chunk_allocator)

	chunk.entities, err = make([dynamic]EntityId, 0, capacity, chunk_allocator)
	ensure(err == .None)

	chunk.capacity = capacity
	chunk.archetype = archetype
	chunk.columns, err = make([]Archetype_Column, len(component_set.components), chunk_allocator)
	ensure(err == .None)

	idx := 0
	for component_id, _ in component_set.components {
		component_size := ecs_get_component_size(world, component_id)

		if component_size > 0 {
			column := &chunk.columns[idx]

			err := init_column(
				column,
				component_id,
				component_size,
				chunk.capacity,
				chunk_allocator,
			)

			if err != .None {
				fmt.panicf(
					"Failed to allocate memory for chunk column %d of archetype %s: %w",
					idx,
					archetype_to_str(world, archetype),
					err,
				)
			}

			idx += 1
		}
	}

	chunk.column_count = idx
	chunk.buffer = buffer

	return chunk
}

archetype_chunk_add_entity :: proc(chunk: ^Archetype_Chunk, entity: EntityId) -> int {
	count := len(chunk.entities)
	ensure(count + 1 <= chunk.capacity)
	append(&chunk.entities, entity)

	return count
}

archetype_chunk_delete_entity :: proc(chunk: ^Archetype_Chunk, row: int) -> EntityId {
	moved_entity: EntityId = 0

	// if the deleted entity is not the last one, we perform an "unordered" remove
	// effectively swaping the deleted row with the last one
	// we need to return the entity that was moved so its row indew can be updated

	chunk_count := len(chunk.entities)
	delete_last := row == chunk_count - 1

	if !delete_last {
		for col_idx := 0; col_idx < chunk.column_count; col_idx += 1 {
			col := &chunk.columns[col_idx]
			last_row := archetype_chunk_get_data(chunk, col_idx, chunk_count - 1)
			dest_row := archetype_chunk_get_data(chunk, col_idx, row)

			mem.copy(dest_row, last_row, col.item_size)
		}

		moved_entity = chunk.entities[chunk_count - 1]
	}

	unordered_remove(&chunk.entities, row)
	ensure(len(chunk.entities) == chunk_count - 1)

	return moved_entity
}

archetype_chunk_get_data :: #force_inline proc(
	chunk: ^Archetype_Chunk,
	col_idx: int,
	row: int,
) -> rawptr {
	assert(col_idx < chunk.column_count)
	return archetype_column_get_data(&chunk.columns[col_idx], row)
}

archetype_chunk_set_data :: proc(chunk: ^Archetype_Chunk, col_idx: int, row: int, data: rawptr) {
	ensure(row < len(chunk.entities))
	ensure(col_idx < chunk.column_count)

	col := &chunk.columns[col_idx]

	ensure(data == nil || col.item_size > 0)

	offset := uintptr(row * col.item_size)
	dest := rawptr(uintptr(col.rows) + offset)

	mem.copy(dest, data, col.item_size)
}

archetype_chunk_get_column_index :: proc(chunk: ^Archetype_Chunk, component_id: EntityId) -> int {
	col_index, exists := chunk.archetype.component_column_map[component_id]
	ensure(exists)

	return col_index
}

archetype_chunk_copy_row :: proc(
	src_chunk: ^Archetype_Chunk,
	dest_chunk: ^Archetype_Chunk,
	src_row: int,
	dest_row: int,
) {
	ensure(src_row < len(src_chunk.entities))
	ensure(dest_row < len(dest_chunk.entities))

	src_col_count := src_chunk.column_count
	dest_col_count := dest_chunk.column_count

	if dest_col_count > src_col_count {
		ensure(dest_col_count - src_col_count == 1)

		for src_col_idx := 0; src_col_idx < src_col_count; src_col_idx += 1 {
			row_data := archetype_chunk_get_data(src_chunk, src_col_idx, src_row)
			src_component_id := src_chunk.columns[src_col_idx].component_id
			dest_col_idx := dest_chunk.archetype.component_column_map[src_component_id]

			archetype_chunk_set_data(dest_chunk, dest_col_idx, dest_row, row_data)
		}
	} else {
		for src_col_idx := 0; src_col_idx < src_col_count; src_col_idx += 1 {
			row_data := archetype_chunk_get_data(src_chunk, src_col_idx, src_row)
			src_component_id := src_chunk.columns[src_col_idx].component_id

			if component_set_has(&dest_chunk.archetype.component_set, src_component_id) {
				dest_col_idx := dest_chunk.archetype.component_column_map[src_component_id]

				archetype_chunk_set_data(dest_chunk, dest_col_idx, dest_row, row_data)
			}
		}
	}
}

@(private = "file")
init_column :: proc(
	column: ^Archetype_Column,
	component_id: EntityId,
	item_size: int,
	capacity: int,
	allocator := context.allocator,
) -> mem.Allocator_Error {
	column.component_id = component_id
	column.item_size = item_size
	rows := mem.alloc(item_size * capacity, mem.DEFAULT_ALIGNMENT, allocator) or_return
	column.rows = rows

	return .None
}
