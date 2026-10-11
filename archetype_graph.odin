package nbecs

import "base:builtin"
import "core:log"
import "core:mem"
import "core:strings"

ArchetypeNode :: struct {
	archetype: Archetype,
	add_nodes: map[Entity]u64,
	rm_nodes:  map[Entity]u64,
}

ArchetypeGraph :: struct {
	root:      ^ArchetypeNode,
	nodes:     map[u64]^ArchetypeNode,
	allocator: mem.Allocator,
}

archetype_graph_init :: proc(
	world: ^World,
	graph: ^ArchetypeGraph,
	allocator := context.allocator,
	create_root := true,
) {
	graph.nodes = make(map[u64]^ArchetypeNode, allocator)
	graph.allocator = allocator

	if create_root {
		root_component_set := set_build([]Entity{}, allocator)
		create_new_archetype(world, graph, &root_component_set, is_root = true)
	}
}

archetype_graph_deinit :: proc(graph: ^ArchetypeGraph) {
	for _, node in graph.nodes {
		destroy_node(graph, node)
	}

	delete_map(graph.nodes)
}

archetype_graph_add :: proc(
	world: ^World,
	graph: ^ArchetypeGraph,
	src_node: ^ArchetypeNode,
	component_id: Entity,
) -> ^ArchetypeNode {
	target_node_hash, exists := src_node.add_nodes[component_id]

	if exists {
		assert(target_node_hash in graph.nodes)

		return graph.nodes[target_node_hash]
	}

	hash := set_build_hash_add(&src_node.archetype.component_set, component_id)
	assert(hash != src_node.archetype.component_set.hash)
	target_node: ^ArchetypeNode
	target_node, exists = graph.nodes[hash]

	if !exists {
		set := set_add(&src_node.archetype.component_set, component_id, graph.allocator)
		assert(set.hash == hash)
		target_node = create_new_archetype(world, graph, &set)
	}

	src_node.add_nodes[component_id] = target_node.archetype.component_set.hash
	target_node.rm_nodes[component_id] = src_node.archetype.component_set.hash

	return target_node
}

archetype_graph_remove :: proc(
	world: ^World,
	graph: ^ArchetypeGraph,
	src_node: ^ArchetypeNode,
	component_id: Entity,
) -> ^ArchetypeNode {
	target_node_hash, exists := src_node.rm_nodes[component_id]

	if exists {
		assert(target_node_hash in graph.nodes)

		return graph.nodes[target_node_hash]
	}

	hash := set_build_hash_rm(&src_node.archetype.component_set, component_id)
	assert(hash != src_node.archetype.component_set.hash)
	target_node: ^ArchetypeNode
	target_node, exists = graph.nodes[hash]

	if !exists {
		set := set_remove(&src_node.archetype.component_set, component_id, graph.allocator)
		assert(set.hash == hash)
		target_node = create_new_archetype(world, graph, &set)
	}

	src_node.rm_nodes[component_id] = target_node.archetype.component_set.hash
	target_node.add_nodes[component_id] = src_node.archetype.component_set.hash

	return target_node
}

archetype_graph_replace :: proc(
	world: ^World,
	graph: ^ArchetypeGraph,
	src_node: ^ArchetypeNode,
	rm_entity: Entity,
	add_entity: Entity,
) -> ^ArchetypeNode {
	assert(archetype_has(&src_node.archetype, rm_entity))
	hash := set_build_hash_replace(&src_node.archetype.component_set, rm_entity, add_entity)
	assert(hash != src_node.archetype.component_set.hash)
	target_node, exists := graph.nodes[hash]

	if !exists {
		set := set_replace(
			&src_node.archetype.component_set,
			rm_entity,
			add_entity,
			graph.allocator,
		)
		assert(set.hash == hash)
		target_node = create_new_archetype(world, graph, &set)
	}

	return target_node
}

archetype_graph_get_or_create :: proc(
	world: ^World,
	graph: ^ArchetypeGraph,
	set: ^Component_Set,
) -> (
	node: ^ArchetypeNode,
	exists: bool,
) {
	node, exists = graph.nodes[set.hash]

	if !exists {
		node = create_new_archetype(world, graph, set)
	}

	return
}

archetype_graph_cleanup :: proc(
	world: ^World,
	graph: ^ArchetypeGraph,
	hash: u64,
	deleted_entity: Entity,
	relationship: bool,
) {
	node, exists := graph.nodes[hash]

	assert(exists)

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
	assert(hash not_in graph.nodes)

	node := builtin.new(ArchetypeNode, graph.allocator)

	node.add_nodes = make(map[Entity]u64, graph.allocator)
	node.rm_nodes = make(map[Entity]u64, graph.allocator)

	graph.nodes[hash] = node

	if is_root {
		assert(graph.root == nil)

		graph.root = node
	}

	return node
}

create_new_archetype :: proc(
	world: ^World,
	graph: ^ArchetypeGraph,
	set: ^Component_Set,
	is_root := false,
	chunk_capacity := 0,
	chunk_count := 1,
) -> ^ArchetypeNode {
	when ECS_DEBUG {
		set_str := component_set_to_str(world, set)
		defer delete(set_str)

		ecs_debug_log("Creating new archetype: %s", set_str)
	}

	node := create_new_node(graph, set.hash, is_root)

	node.archetype.node = node
	archetype_init(
		world,
		&node.archetype,
		set,
		chunk_capacity = chunk_capacity,
		chunk_count = chunk_count,
		allocator = graph.allocator,
		is_root = is_root,
	)
	on_archetype_created(world, &node.archetype)

	return node
}

@(private)
destroy_node :: proc(graph: ^ArchetypeGraph, node: ^ArchetypeNode) {
	archetype_deinit(&node.archetype)
	delete_map(node.add_nodes)
	delete_map(node.rm_nodes)
	free(node, graph.allocator)
}

