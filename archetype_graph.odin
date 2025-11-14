package nbecs

import "core:log"
import "core:strings"
import "core:mem"

ArchetypeNode :: struct {
    archetype: Archetype,
    add_nodes: map[EntityId]u64,
    rm_nodes: map[EntityId]u64
}

ArchetypeGraph :: struct {
    root: ^ArchetypeNode,
    nodes: map[u64]^ArchetypeNode,
    allocator: mem.Allocator
}

archetype_graph_init :: proc(world: ^World, graph: ^ArchetypeGraph, allocator := context.allocator, create_root := true) {
    graph.nodes = make(map[u64]^ArchetypeNode, allocator)
    graph.allocator = allocator

    if create_root {
        root_component_set := ComponentSet{}
        component_set_init(&root_component_set, []EntityId{})
        create_new_archetype(world, graph, &root_component_set, is_root = true)
    }
}

archetype_graph_deinit :: proc(graph: ^ArchetypeGraph) {
    for _, node in graph.nodes {
        destroy_node(graph, node)
    }

    delete(graph.nodes)
}

archetype_graph_add :: proc(world: ^World, graph: ^ArchetypeGraph, src_node: ^ArchetypeNode, component_id: EntityId) -> ^ArchetypeNode {
    target_node_hash, exists := src_node.add_nodes[component_id]

    if exists {
        ensure(target_node_hash in graph.nodes)

        return graph.nodes[target_node_hash]
    }

    hash := component_set_build_hash_add(&src_node.archetype.component_set, component_id)
    ensure(hash != src_node.archetype.component_set.hash)
    target_node, exists2 := graph.nodes[hash]

    if !exists2 {
        set := component_set_add(&src_node.archetype.component_set, component_id, graph.allocator)
        ensure(set.hash == hash)
        target_node = create_new_archetype(world, graph, &set)
    }

    src_node.add_nodes[component_id] = target_node.archetype.component_set.hash
    target_node.rm_nodes[component_id] = src_node.archetype.component_set.hash

    return target_node
}

archetype_graph_remove :: proc(world: ^World, graph: ^ArchetypeGraph, src_node: ^ArchetypeNode, component_id: EntityId) -> ^ArchetypeNode {
    target_node_hash, exists := src_node.rm_nodes[component_id]

    if exists {
        ensure(target_node_hash in graph.nodes)

        return graph.nodes[target_node_hash]
    }

    hash := component_set_build_hash_rm(&src_node.archetype.component_set, component_id)
    ensure(hash != src_node.archetype.component_set.hash)
    target_node, exists2 := graph.nodes[hash]

    if !exists2 {
        set := component_set_remove(&src_node.archetype.component_set, component_id, graph.allocator)
        ensure(set.hash == hash)
        target_node = create_new_archetype(world, graph, &set)
    }

    src_node.rm_nodes[component_id] = target_node.archetype.component_set.hash
    target_node.add_nodes[component_id] = src_node.archetype.component_set.hash

    return target_node
}

archetype_graph_replace :: proc(world: ^World, graph: ^ArchetypeGraph, src_node: ^ArchetypeNode,
    rm_entity: EntityId, add_entity: EntityId) -> ^ArchetypeNode
{
    ensure(archetype_has(&src_node.archetype, rm_entity))
    hash := component_set_build_hash_replace(&src_node.archetype.component_set, rm_entity, add_entity)
    ensure(hash != src_node.archetype.component_set.hash)
    target_node, exists := graph.nodes[hash]

    if !exists {
        set := component_set_replace(&src_node.archetype.component_set, rm_entity, add_entity, graph.allocator)
        ensure(set.hash == hash)
        target_node = create_new_archetype(world, graph, &set)
    }

    return target_node
}

archetype_graph_get_or_create :: proc(world: ^World, graph: ^ArchetypeGraph,
    set: ^ComponentSet) -> (node: ^ArchetypeNode, exists: bool)
{
    node, exists = graph.nodes[set.hash]

    if !exists {
        node = create_new_archetype(world, graph, set)
    }

    return
}

archetype_graph_cleanup :: proc(world: ^World, graph: ^ArchetypeGraph, hash: u64, deleted_entity: EntityId, relationship: bool) {
    node, exists := graph.nodes[hash]

    ensure(exists)

    for _, prev_hash in node.rm_nodes {
        if prev_hash not_in graph.nodes {
            continue
        }

        prev_node := graph.nodes[prev_hash]

        for key, add_hash in prev_node.add_nodes {
            if add_hash == hash {
                delete_key(&prev_node.add_nodes, key)
            }
        }
    }

    on_archetype_deleted(world, &node.archetype, deleted_entity, relationship)
    destroy_node(graph, node)
    delete_key(&graph.nodes, hash)
}

create_new_node :: proc(graph: ^ArchetypeGraph, hash: u64, is_root: bool) -> ^ArchetypeNode {
    ensure(hash not_in graph.nodes)

    node := new(ArchetypeNode, graph.allocator)

    node.add_nodes = make(map[EntityId]u64, graph.allocator)
    node.rm_nodes = make(map[EntityId]u64, graph.allocator)

    graph.nodes[hash] = node

    if is_root {
        ensure(graph.root == nil)

        graph.root = node
    }

    return node
}

create_new_archetype :: proc(world: ^World, graph: ^ArchetypeGraph, set: ^ComponentSet, is_root := false,
    chunk_capacity := 0, chunk_count := 1) -> ^ArchetypeNode
{
    when ECS_DEBUG {
        set_str := component_set_to_str(world, set)
        defer delete(set_str)

        ecs_debug_log("Creating new archetype: %s", set_str)
    }

    node := create_new_node(graph, set.hash, is_root)

    node.archetype.node = node
    archetype_init(world, &node.archetype, set, chunk_capacity = chunk_capacity, chunk_count = chunk_count,
        allocator = graph.allocator, is_root = is_root)
    on_archetype_created(world, &node.archetype)

    return node
}

@private
destroy_node :: proc(graph: ^ArchetypeGraph, node: ^ArchetypeNode) {
    archetype_deinit(&node.archetype)
    delete(node.add_nodes)
    delete(node.rm_nodes)
    free(node, graph.allocator)
}
