package nbecs

import "base:builtin"
import "core:fmt"
import "core:log"
import "core:mem"
import vmem "core:mem/virtual"

Archetype_ChunkSize_Bytes :: 32_000

Archetype_Column :: struct {
	component_id: Entity,
	item_size:    int,
	rows:         rawptr,
}

Archetype_Chunk :: struct {
	capacity:     int,
	count:        int,
	column_count: int,
	index:        int,
	archetype:    ^Archetype,
	columns:      []Archetype_Column,
	entities:     []Entity,
	buffer:       []u8,
}

archetype_chunk_create :: proc(
	world: ^World,
	archetype: ^Archetype,
	capacity: int,
	component_set: ^Component_Set,
	buffer: []u8,
) -> ^Archetype_Chunk {
	chunk_arena := vmem.Arena{}
	err := vmem.arena_init_buffer(&chunk_arena, buffer)
	ensure(err == nil)

	chunk_allocator := vmem.arena_allocator(&chunk_arena)
	chunk := builtin.new(Archetype_Chunk, chunk_allocator)

	chunk.entities, err = make([]Entity, capacity, chunk_allocator)
	ensure(err == .None)

	chunk.capacity = capacity
	chunk.archetype = archetype
	chunk.columns, err = make([]Archetype_Column, archetype.column_count, chunk_allocator)
	ensure(err == .None)

	col_idx := 0
	for component_id, _ in component_set.components {
		comp_size := get_component_size(world, component_id)

		if comp_size > 0 {
			column := &chunk.columns[col_idx]
			err := init_column(column, component_id, comp_size, chunk.capacity, chunk_allocator)

			if err != .None {
				fmt.panicf(
					"Failed to allocate memory for chunk column %d ({}) of archetype {}: {} (used: {}, reserved: {})",
					col_idx,
					get_component_type(world, component_id).type,
					archetype_to_str(world, archetype),
					err,
					chunk_arena.total_used,
					chunk_arena.total_reserved,
				)
			}

			col_idx += 1
		}
	}

	assert(col_idx == archetype.column_count)

	chunk.column_count = archetype.column_count
	chunk.buffer = buffer

	return chunk
}

archetype_chunk_add_entity :: proc(chunk: ^Archetype_Chunk, entity: Entity) -> int {
	count := chunk.count
	assert(count < chunk.capacity)
	chunk.entities[chunk.count] = entity
	chunk.count += 1

	return count
}

archetype_chunk_delete_entity :: proc(chunk: ^Archetype_Chunk, row: int) -> Entity {
	moved_entity: Entity = 0

	// if the deleted entity is not the last one, we perform an "unordered" remove
	// effectively swaping the deleted row with the last one
	// we need to return the entity that was moved so its row index can be updated

	delete_last := row == chunk.count - 1

	if !delete_last {
		for col_idx := 0; col_idx < chunk.column_count; col_idx += 1 {
			col := &chunk.columns[col_idx]
			last_row := archetype_chunk_get_data(col, chunk.count - 1)
			dest_row := archetype_chunk_get_data(col, row)

			mem.copy(dest_row, last_row, col.item_size)
		}

		moved_entity = chunk.entities[chunk.count - 1]
		chunk.entities[row] = moved_entity
	}

	chunk.entities[chunk.count - 1] = 0
	chunk.count -= 1

	return moved_entity
}

archetype_chunk_set_data :: proc(chunk: ^Archetype_Chunk, col_idx: int, row: int, data: rawptr) {
	assert(row < chunk.count)
	assert(col_idx < chunk.column_count)

	col := &chunk.columns[col_idx]

	assert(data == nil || col.item_size > 0)

	offset := uintptr(row * col.item_size)
	dest := rawptr(uintptr(col.rows) + offset)

	mem.copy(dest, data, col.item_size)
}

archetype_chunk_get_data :: proc {
	archetype_chunk_get_data_col,
	archetype_chunk_get_data_col_idx,
}

archetype_chunk_get_data_col :: #force_inline proc(col: ^Archetype_Column, row: int) -> rawptr {
	offset := uintptr(row * col.item_size)

	return rawptr(uintptr(col.rows) + offset)
}

archetype_chunk_get_data_col_idx :: #force_inline proc(
	chunk: ^Archetype_Chunk,
	col_idx: int,
	row: int,
) -> rawptr {
	col := &chunk.columns[col_idx]

	return archetype_chunk_get_data_col(col, row)
}

archetype_chunk_get_column_index :: proc(chunk: ^Archetype_Chunk, component_id: Entity) -> int {
	col_index, exists := chunk.archetype.component_column_map[component_id]
	assert(exists)

	return col_index
}

archetype_chunk_copy_row :: proc(
	src_chunk: ^Archetype_Chunk,
	dest_chunk: ^Archetype_Chunk,
	src_row: int,
	dest_row: int,
) {
	assert(src_row < src_chunk.count)
	assert(dest_row < dest_chunk.count)

	src_col_count := src_chunk.column_count
	dest_col_count := dest_chunk.column_count

	if dest_col_count > src_col_count {
		assert(dest_col_count - src_col_count == 1)

		for src_col_idx := 0; src_col_idx < src_col_count; src_col_idx += 1 {
			src_col := &src_chunk.columns[src_col_idx]
			row_data := archetype_chunk_get_data(src_col, src_row)
			src_component_id := src_col.component_id
			dest_col_idx := dest_chunk.archetype.component_column_map[src_component_id]

			archetype_chunk_set_data(dest_chunk, dest_col_idx, dest_row, row_data)
		}
	} else {
		for src_col_idx := 0; src_col_idx < src_col_count; src_col_idx += 1 {
			src_col := &src_chunk.columns[src_col_idx]
			src_component_id := src_col.component_id
			row_data := archetype_chunk_get_data(src_col, src_row)

			if set_has(&dest_chunk.archetype.component_set, src_component_id) {
				dest_col_idx := dest_chunk.archetype.component_column_map[src_component_id]

				archetype_chunk_set_data(dest_chunk, dest_col_idx, dest_row, row_data)
			}
		}
	}
}

@(private = "file")
init_column :: proc(
	column: ^Archetype_Column,
	component_id: Entity,
	item_size: int,
	capacity: int,
	allocator: mem.Allocator,
) -> mem.Allocator_Error {
	column.component_id = component_id
	column.item_size = item_size
	rows := mem.alloc(item_size * capacity, mem.DEFAULT_ALIGNMENT, allocator) or_return
	column.rows = rows

	return .None
}

