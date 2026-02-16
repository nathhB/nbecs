package snapshot

import ecs ".."
import "core:fmt"
import "core:log"
import "core:mem"

take_snapshot :: proc(src_world: ^ecs.World, allocator := context.allocator) -> ^ecs.World {
	snap_world := ecs.ecs_create_snapshot(allocator)

	copy_root(src_world, snap_world)
	copy_types(src_world, snap_world, allocator)

	for _, hash in src_world.archetypes.root.add_nodes {
		child := src_world.archetypes.nodes[hash]

		copy_archetypes(src_world, snap_world, child)
	}

	// this is a bit of a dirty hack
	// loop over all archetypes from the source world again as some archetypes
	// might not get picked up from iterating the archetype graph as done just above
	// for instance, for archetypes that have been created via 'archetype_graph_replace'
	for hash, node in src_world.archetypes.nodes {
		if hash not_in snap_world.archetypes.nodes {
			src_archetype := &node.archetype
			src_chunk_count := len(src_archetype.chunks)
			dest_node := ecs.create_new_archetype(
				snap_world,
				&snap_world.archetypes,
				&src_archetype.component_set,
				false,
				src_archetype.chunk_capacity,
				src_chunk_count,
			)

			copy_archetype(src_world, snap_world, src_archetype, &dest_node.archetype)
		}
	}

	snap_world.frozen = true

	// log.debug(archetype_graph_to_str(snap_world))

	return snap_world
}

copy_root :: proc(src_world: ^ecs.World, snap_world: ^ecs.World) {
	src_archetype := &src_world.archetypes.root.archetype
	src_chunk_count := len(src_archetype.chunks)
	dest_node := ecs.create_new_archetype(
		snap_world,
		&snap_world.archetypes,
		&src_archetype.component_set,
		true,
		src_archetype.chunk_capacity,
		src_chunk_count,
	)

	copy_archetype(src_world, snap_world, src_archetype, &dest_node.archetype)
}

copy_types :: proc(
	src_world: ^ecs.World,
	snap_world: ^ecs.World,
	allocator: mem.Allocator,
	node: ^ecs.ArchetypeNode = nil,
) {
	node := node

	if node == nil {
		hash := ecs.component_set_build_hash([]ecs.EntityId{ecs.TypeTrait})
		ensure(hash in src_world.archetypes.nodes)
		node = src_world.archetypes.nodes[hash]
	}

	src_archetype := &node.archetype
	src_chunk_count := len(src_archetype.chunks)
	dest_node := ecs.create_new_archetype(
		snap_world,
		&snap_world.archetypes,
		&src_archetype.component_set,
		false,
		src_archetype.chunk_capacity,
		src_chunk_count,
	)

	copy_archetype(src_world, snap_world, src_archetype, &dest_node.archetype)

	it := ecs.iter_archetype(src_world, src_archetype, allocator)
	chunk := it.current_chunk

	for row := 0; row < len(chunk.entities); row += 1 {
		entity := chunk.entities[row]
		src_world_type := src_world.ids_to_components[entity]

		ecs.ecs_declare_type(snap_world, entity, src_world_type.type, src_world_type.size)
	}

	for _, child_hash in node.add_nodes {
		child := src_world.archetypes.nodes[child_hash]

		copy_types(src_world, snap_world, allocator, child)
	}
}

copy_archetypes :: proc(
	src_world: ^ecs.World,
	snap_world: ^ecs.World,
	src_node: ^ecs.ArchetypeNode,
) {
	ensure(!src_node.archetype.is_root)

	src_archetype := &src_node.archetype

	if skip_archetype(src_world, src_archetype) {
		return
	}

	src_hash := src_archetype.component_set.hash

	if src_hash in snap_world.archetypes.nodes {
		return
	}

	for component, _ in src_archetype.component_set.components {
		if ecs.ecs_exists(snap_world, component) {
			continue
		}

		// this component is not a type and has not been created yet
		// from another archetype

		if ecs.ecs_is_pair(component) {
			first, second := ecs.ecs_pair_split(component)
			pair_type := ecs.ecs_get_pair_type(src_world, component)

			if pair_type == 0 {
				// pair has no type, both parts are regular entities
				first_entry, first_exists := src_world.entities[first]
				second_entry, second_exists := src_world.entities[second]

				if first_exists && !ecs.ecs_exists(snap_world, first) {
					ecs.ecs_new_with_id(snap_world, first, first_entry.name)
				}

				if second_exists && !ecs.ecs_exists(snap_world, second) {
					ecs.ecs_new_with_id(snap_world, second, second_entry.name)
				}
			} else if pair_type == first {
				ensure(ecs.ecs_exists(snap_world, first))
				second_entry, second_exists := src_world.entities[second]

				if second_exists && !ecs.ecs_exists(snap_world, second) {
					ecs.ecs_new_with_id(snap_world, second, second_entry.name)
				}
			} else {
				panic("NOT SUPPORTED")
			}
		} else {
			entry, exists := src_world.entities[component]
			ensure(exists)

			ecs.ecs_new_with_id(snap_world, component, entry.name)
		}
	}

	src_chunk_count := len(src_archetype.chunks)
	dest_node := ecs.create_new_archetype(
		snap_world,
		&snap_world.archetypes,
		&src_archetype.component_set,
		src_archetype.is_root,
		src_archetype.chunk_capacity,
		src_chunk_count,
	)

	copy_archetype(src_world, snap_world, src_archetype, &dest_node.archetype)

	for _, hash in src_node.add_nodes {
		child := src_world.archetypes.nodes[hash]

		copy_archetypes(src_world, snap_world, child)
	}
}

copy_archetype :: proc(
	src_world: ^ecs.World,
	snap_world: ^ecs.World,
	src: ^ecs.Archetype,
	dest: ^ecs.Archetype,
) {
	when ecs.ECS_DEBUG {
		arch_str := archetype_to_str(src_world, src)
		defer delete(arch_str)

		log.debugf("Copying archetype %s to snapshot", arch_str)
	}

	src_chunk_count := len(src.chunks)
	dest_chunk_count := len(dest.chunks)

	ensure(src.component_set.hash == dest.component_set.hash)
	ensure(src_chunk_count == dest_chunk_count)

	for i := 0; i < src_chunk_count; i += 1 {
		src_chunk := src.chunks[i]
		dest_chunk := dest.chunks[i]

		copy_chunk(src_chunk, dest_chunk)
		ensure(len(src_chunk.entities) == len(dest_chunk.entities))

		for entity in dest_chunk.entities {
			src_entry, exists := src_world.entities[entity]

			ensure(exists)
			ensure(src_entry.id == entity)

			// src_entry is a copy here, we are not actually modifying the entry in the source world
			src_entry.chunk = dest_chunk
			snap_world.entities[src_entry.id] = src_entry
		}
	}
}

copy_chunk :: proc(src: ^ecs.Archetype_Chunk, dest: ^ecs.Archetype_Chunk) {
	fmt.ensuref(
		src.column_count == dest.column_count,
		"src.column_count == %d, dest.column_count == %d",
		src.column_count,
		dest.column_count,
	)

	resize(&dest.entities, len(src.entities))
	copy(dest.entities[:], src.entities[:])

	for i := 0; i < src.column_count; i += 1 {
		src_col := &src.columns[i]
		dest_col := &dest.columns[i]
		src_col_len := src_col.item_size * src.capacity
		dest_col_len := dest_col.item_size * dest.capacity

		ensure(src_col.item_size == dest_col.item_size)
		ensure(src_col.component_id == dest_col.component_id)
		ensure(src_col_len == dest_col_len)

		mem.copy(dest_col.rows, src_col.rows, src_col_len)
	}
}

skip_archetype :: proc(world: ^ecs.World, arch: ^ecs.Archetype) -> bool {
	if ecs.component_set_has(&arch.component_set, ecs.ecs_get_type_id(world, ecs.System)) {
		return true
	}

	if arch.is_watcher {
		return true
	}

	return false
}
