package nbecs

import sa "core:container/small_array"
import "core:log"
import "core:slice"

Component_Set :: struct {
	components: map[Entity]struct{},
	hash:       u64,
}

set_build :: proc(component_ids: []Entity, allocator := context.allocator) -> Component_Set {
	component_count := len(component_ids)

	set := Component_Set{}
	set.components = make(map[Entity]struct{}, component_count, allocator)

	for component_id in component_ids {
		set.components[component_id] = {}
	}

	set.hash = set_build_hash(component_ids)

	return set
}

set_destroy :: proc(set: ^Component_Set) {
	delete_map(set.components)
}

set_add :: proc(
	set: ^Component_Set,
	entity: Entity,
	allocator := context.allocator,
) -> Component_Set {
	component_ids := make([]Entity, len(set.components) + 1, context.temp_allocator)

	idx := 0
	for component_id, _ in set.components {
		component_ids[idx] = component_id
		idx += 1
	}

	component_ids[idx] = entity

	return set_build(component_ids, allocator)
}

set_remove :: proc(
	set: ^Component_Set,
	entity: Entity,
	allocator := context.allocator,
) -> Component_Set {
	component_ids := make([]Entity, len(set.components) - 1, context.temp_allocator)

	idx := 0
	for component_id, _ in set.components {
		if component_id != entity {
			component_ids[idx] = component_id
			idx += 1
		}
	}

	return set_build(component_ids, allocator)
}

set_replace :: proc(
	set: ^Component_Set,
	rm: Entity,
	add: Entity,
	allocator := context.allocator,
) -> Component_Set {
	component_ids := make([]Entity, len(set.components), context.temp_allocator)

	idx := 0
	for component_id, _ in set.components {
		component_ids[idx] = component_id == rm ? add : component_id
		idx += 1
	}

	return set_build(component_ids, allocator)
}

set_remove_relationship :: proc(
	set: ^Component_Set,
	entity: Entity,
	allocator := context.allocator,
) -> Component_Set {
	component_ids := make([]Entity, len(set.components), context.temp_allocator)

	idx := 0
	for component_id, _ in set.components {
		if is_pair(component_id) && pair_contains(component_id, entity) {
			continue
		}

		component_ids[idx] = component_id
		idx += 1
	}

	return set_build(component_ids[:idx], allocator)
}

set_has :: #force_inline proc(set: ^Component_Set, component_id: Entity) -> bool {
	return component_id in set.components
}

set_build_hash_add :: proc(set: ^Component_Set, add: Entity) -> u64 {
	component_ids := make([]Entity, len(set.components) + 1, context.temp_allocator)

	idx := 0
	for component_id, _ in set.components {
		component_ids[idx] = component_id
		idx += 1
	}

	component_ids[idx] = add

	return set_build_hash(component_ids)
}

set_build_hash_rm :: proc(set: ^Component_Set, rm: Entity) -> u64 {
	component_ids := make([]Entity, len(set.components) - 1, context.temp_allocator)

	idx := 0
	for component_id, _ in set.components {
		if component_id != rm {
			component_ids[idx] = component_id
			idx += 1
		}
	}

	return set_build_hash(component_ids)
}

set_build_hash_replace :: proc(set: ^Component_Set, rm: Entity, add: Entity) -> u64 {
	component_ids := make([]Entity, len(set.components), context.temp_allocator)

	idx := 0
	for component_id, _ in set.components {
		component_ids[idx] = component_id == rm ? add : component_id
		idx += 1
	}

	return set_build_hash(component_ids)
}

set_build_hash :: proc(component_ids: []Entity) -> u64 {
	slice.sort(component_ids)

	hash := u64(len(component_ids))

	for component_id in component_ids {
		x := u64(component_id)

		x = ((x >> 16) ~ x) * 0x45d9f3b
		x = ((x >> 16) ~ x) * 0x45d9f3b
		x = (x >> 16) ~ x
		hash ~= x + 0x9e3779b9 + (hash << 6) + (hash >> 2)
	}

	return hash
}

set_to_arr :: proc(set: ^Component_Set) -> []Entity {
	arr := make([]Entity, len(set.components))

	i := 0
	for component_id, _ in set.components {
		arr[i] = component_id
		i += 1
	}

	slice.sort(arr)

	return arr
}

