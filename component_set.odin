package nbecs

import "core:slice"
import "core:log"
import "core:strings"
import sa "core:container/small_array"

ComponentSet_MaxCapacity :: 16

ComponentSet :: struct {
    components: map[EntityId]int, // used as a set, values are awlays 0
    hash: u64,
}

component_set_init :: proc(set: ^ComponentSet, component_ids: []EntityId, allocator := context.allocator) {
    component_count := len(component_ids)

    set.components = make(map[EntityId]int, component_count, allocator)

    for component_id in component_ids {
        set.components[component_id] = 0
    }

    set.hash = component_set_build_hash(component_ids)
}

component_set_deinit :: proc(set: ^ComponentSet) {
    delete(set.components)
}

component_set_add :: proc(set: ^ComponentSet, entity: EntityId, allocator := context.allocator) -> ComponentSet {
    ensure(len(set.components) + 1 <= ComponentSet_MaxCapacity)
    component_ids: sa.Small_Array(ComponentSet_MaxCapacity, EntityId)

    for component_id, _ in set.components {
        sa.append(&component_ids, component_id)
    }

    sa.append(&component_ids, entity)

    new_set := ComponentSet{}
    component_set_init(&new_set, sa.slice(&component_ids), allocator)

    return new_set
}

component_set_remove :: proc(set: ^ComponentSet, entity: EntityId, allocator := context.allocator) -> ComponentSet {
    component_ids: sa.Small_Array(ComponentSet_MaxCapacity, EntityId)

    for component_id, _ in set.components {
        if component_id != entity {
            sa.append(&component_ids, component_id)
        }
    }

    new_set := ComponentSet{}
    component_set_init(&new_set, sa.slice(&component_ids), allocator)

    return new_set
}

component_set_replace :: proc(set: ^ComponentSet, rm: EntityId, add: EntityId, allocator := context.allocator) -> ComponentSet {
    component_ids: sa.Small_Array(ComponentSet_MaxCapacity, EntityId)

    for component_id, _ in set.components {
        sa.append(&component_ids, component_id == rm ? add : component_id)
    }

    new_set := ComponentSet{}
    component_set_init(&new_set, sa.slice(&component_ids), allocator)

    return new_set
}

component_set_remove_relationship :: proc(set: ^ComponentSet, entity: EntityId, allocator := context.allocator) -> ComponentSet {
    component_ids: sa.Small_Array(ComponentSet_MaxCapacity, EntityId)

    for component_id, _ in set.components {
        if ecs_is_pair(component_id) && ecs_pair_contains(component_id, entity) {
            continue
        }

        sa.append(&component_ids, component_id)
    }

    new_set := ComponentSet{}
    component_set_init(&new_set, sa.slice(&component_ids), allocator)

    return new_set
}

component_set_has :: proc(set: ^ComponentSet, component_id: EntityId) -> bool {
    return component_id in set.components
}

component_set_build_hash_add :: proc(set: ^ComponentSet, add: EntityId) -> u64 {
    ensure(len(set.components) + 1 <= ComponentSet_MaxCapacity)

    component_ids: sa.Small_Array(ComponentSet_MaxCapacity, EntityId)

    for component_id, _ in set.components {
        sa.append(&component_ids, component_id)
    }

    sa.append(&component_ids, add)

    return component_set_build_hash(sa.slice(&component_ids))
}

component_set_build_hash_rm :: proc(set: ^ComponentSet, rm: EntityId) -> u64 {
    component_ids: sa.Small_Array(ComponentSet_MaxCapacity, EntityId)

    for component_id, _ in set.components {
        if component_id != rm {
            sa.append(&component_ids, component_id)
        }
    }

    return component_set_build_hash(sa.slice(&component_ids))
}

component_set_build_hash_replace :: proc(set: ^ComponentSet, rm: EntityId, add: EntityId) -> u64 {
    component_ids: sa.Small_Array(ComponentSet_MaxCapacity, EntityId)

    for component_id, _ in set.components {
        sa.append(&component_ids, component_id == rm ? add : component_id)
    }

    return component_set_build_hash(sa.slice(&component_ids))
}

component_set_build_hash :: proc(component_ids: []EntityId) -> u64 {
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

component_set_to_arr :: proc(set: ^ComponentSet) -> []EntityId {
    arr := make([]EntityId, len(set.components))

    i := 0
    for component_id, _ in set.components {
        arr[i] = component_id
        i += 1
    }

    slice.sort(arr)

    return arr
}
