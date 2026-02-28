package nbecs

import sa "core:container/small_array"
import "core:log"
import "core:slice"

Component_Set_Max_Capacity :: 16

Component_Set :: struct {
	components: map[EntityId]struct{},
	hash:       u64,
}

@(thread_local)
@(private = "file")
component_ids: sa.Small_Array(Component_Set_Max_Capacity, EntityId)

set_build :: proc(component_ids: []EntityId, allocator := context.allocator) -> Component_Set {
	component_count := len(component_ids)

	set := Component_Set{}
	set.components = make(map[EntityId]struct{}, component_count, allocator)

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
	entity: EntityId,
	allocator := context.allocator,
) -> Component_Set {
	assert(len(set.components) + 1 <= Component_Set_Max_Capacity)

	sa.clear(&component_ids)

	for component_id, _ in set.components {
		sa.append(&component_ids, component_id)
	}

	sa.append(&component_ids, entity)

	return set_build(sa.slice(&component_ids), allocator)
}

set_remove :: proc(
	set: ^Component_Set,
	entity: EntityId,
	allocator := context.allocator,
) -> Component_Set {
	sa.clear(&component_ids)

	for component_id, _ in set.components {
		if component_id != entity {
			sa.append(&component_ids, component_id)
		}
	}

	return set_build(sa.slice(&component_ids), allocator)
}

set_replace :: proc(
	set: ^Component_Set,
	rm: EntityId,
	add: EntityId,
	allocator := context.allocator,
) -> Component_Set {
	sa.clear(&component_ids)

	for component_id, _ in set.components {
		sa.append(&component_ids, component_id == rm ? add : component_id)
	}

	return set_build(sa.slice(&component_ids), allocator)
}

set_remove_relationship :: proc(
	set: ^Component_Set,
	entity: EntityId,
	allocator := context.allocator,
) -> Component_Set {
	sa.clear(&component_ids)

	for component_id, _ in set.components {
		if is_pair(component_id) && pair_contains(component_id, entity) {
			continue
		}

		sa.append(&component_ids, component_id)
	}

	return set_build(sa.slice(&component_ids), allocator)
}

set_has :: proc(set: ^Component_Set, component_id: EntityId) -> bool {
	return component_id in set.components
}

set_build_hash_add :: proc(set: ^Component_Set, add: EntityId) -> u64 {
	assert(len(set.components) + 1 <= Component_Set_Max_Capacity)

	sa.clear(&component_ids)

	for component_id, _ in set.components {
		sa.append(&component_ids, component_id)
	}

	sa.append(&component_ids, add)

	return set_build_hash(sa.slice(&component_ids))
}

set_build_hash_rm :: proc(set: ^Component_Set, rm: EntityId) -> u64 {
	sa.clear(&component_ids)

	for component_id, _ in set.components {
		if component_id != rm {
			sa.append(&component_ids, component_id)
		}
	}

	return set_build_hash(sa.slice(&component_ids))
}

set_build_hash_replace :: proc(set: ^Component_Set, rm: EntityId, add: EntityId) -> u64 {
	sa.clear(&component_ids)

	for component_id, _ in set.components {
		sa.append(&component_ids, component_id == rm ? add : component_id)
	}

	return set_build_hash(sa.slice(&component_ids))
}

set_build_hash :: proc(component_ids: []EntityId) -> u64 {
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

set_to_arr :: proc(set: ^Component_Set) -> []EntityId {
	arr := make([]EntityId, len(set.components))

	i := 0
	for component_id, _ in set.components {
		arr[i] = component_id
		i += 1
	}

	slice.sort(arr)

	return arr
}
