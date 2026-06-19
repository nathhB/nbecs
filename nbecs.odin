package nbecs

ECS_DEBUG :: #config(ECS_DEBUG, false)

import "base:builtin"
import "core:fmt"
import "core:log"
import "core:mem"
import vmem "core:mem/virtual"

EntityId :: u64

// raw entity ids have to fit in 3 bytes
// "raw" meaning the id without generation and id flags
EntityId_Raw_Max :: u64(16_777_215)

ReservedIDs :: 32
TypeTrait: EntityId = 1
Wildcard: EntityId = 2
ChildOf_Id: EntityId = 3
Pipeline_Default: EntityId = 4
OnDelete: EntityId = 5
UniquePair: EntityId = 6
DeleteStrategy_Delete: EntityId = 7
DeleteStrategy_Remove: EntityId = 8
Prefab: EntityId = 9
Event_Deleted: EntityId = 10
System_Id: EntityId = 11
Watcher_Id: EntityId = 12

Component_Type :: struct {
	type: typeid,
	id:   EntityId,
	size: int,
}

Entity_Entry :: struct {
	id:    EntityId,
	name:  string,
	row:   int,
	chunk: ^Archetype_Chunk,
}

Archetype_Map :: #type map[u64]^Archetype
System_Proc :: #type proc(world: ^World, it: ^Query_Iterator, dt: f64, ctx: rawptr) -> bool
System_Hook_Proc :: #type proc(world: ^World, dt: f64, ctx: rawptr)
Watcher_Proc :: #type proc(
	world: ^World,
	entity: EntityId,
	it: ^Query_Iterator,
	row: int,
	ctx: rawptr,
	data: rawptr,
)

World :: struct {
	next_entity_id:      EntityId,
	entities:            map[EntityId]Entity_Entry,
	names_index:         map[string]EntityId,
	types_to_components: map[typeid]Component_Type,
	ids_to_components:   map[EntityId]Component_Type,
	archetype_index:     map[EntityId]Archetype_Map,
	archetypes:          ArchetypeGraph,
	queries:             [dynamic]^Query,
	ctx:                 rawptr,
	pipelines:           map[EntityId]Pipeline,
	config:              World_Config,
	arena:               vmem.Arena,
	allocator:           mem.Allocator,
	frozen:              bool,
	snapshot:            bool,
	info:                World_Info,
}

World_Config :: struct {
	default_delete_strategy: EntityId,
	id_range:                [2]EntityId,
}

World_Info :: struct {
	entity_count:    int,
	archetype_count: int,
}

Pipeline :: struct {
	entity: EntityId,
	query:  ^Query,
}

System :: struct {
	query:              ^Query,
	update_proc:        System_Proc,
	before_update_proc: System_Hook_Proc,
	after_update_proc:  System_Hook_Proc,
	ctx:                rawptr,
}

Watcher :: struct {
	query:     ^Query,
	procedure: Watcher_Proc,
	ctx:       rawptr,
}

ChildOf :: struct {
	depth: int,
}

create :: proc(allocator := context.allocator) -> ^World {
	world := builtin.new(World, allocator)

	world.next_entity_id = 1
	world.config.id_range = [2]EntityId{1, ReservedIDs + 1}
	world.entities = make(map[EntityId]Entity_Entry, allocator)
	world.names_index = make(map[string]EntityId, allocator)
	world.types_to_components = make(map[typeid]Component_Type, allocator)
	world.ids_to_components = make(map[EntityId]Component_Type, allocator)
	world.archetype_index = make(map[EntityId]Archetype_Map, allocator)
	world.allocator = allocator
	world.snapshot = false
	world.pipelines = make(map[EntityId]Pipeline, allocator)
	world.queries = make([dynamic]^Query, allocator)

	archetype_graph_init(world, &world.archetypes, allocator)

	new_with_id(world, TypeTrait, "TypeTrait")
	new_with_id(world, Wildcard, "*")
	new_with_id(world, OnDelete, "OnDelete")
	new_with_id(world, DeleteStrategy_Delete, "Delete")
	new_with_id(world, DeleteStrategy_Remove, "Remove")
	new_with_id(world, UniquePair, "UniquePair")
	new_with_id(world, Prefab, "Prefab")
	new_with_id(world, Event_Deleted, "Event_Deleted")

	declare_with_id(world, System_Id, System, "System")
	declare_with_id(world, Watcher_Id, Watcher, "Watcher")

	new_with_id(world, Pipeline_Default, "Pipeline_Default")
	pipeline_with_id(world, Pipeline_Default)

	declare_with_id(world, ChildOf_Id, ChildOf, "ChildOf")
	add(world, ChildOf_Id, UniquePair)

	ensure(world.next_entity_id <= ReservedIDs + 1)
	world.config.default_delete_strategy = DeleteStrategy_Remove
	set_id_range(world, [2]EntityId{ReservedIDs + 1, EntityId_Raw_Max})

	return world
}

create_snapshot :: proc(allocator := context.allocator) -> ^World {
	world := builtin.new(World, allocator)

	world.next_entity_id = 1
	world.entities = make(map[EntityId]Entity_Entry, allocator)
	world.names_index = make(map[string]EntityId, allocator)
	world.types_to_components = make(map[typeid]Component_Type, allocator)
	world.ids_to_components = make(map[EntityId]Component_Type, allocator)
	world.archetype_index = make(map[EntityId]Archetype_Map, allocator)
	world.allocator = allocator
	world.snapshot = true

	archetype_graph_init(world, &world.archetypes, allocator, create_root = false)

	return world
}

destroy :: proc(world: ^World) {
	ensure(!world.snapshot)

	delete_map(world.entities)
	delete_map(world.names_index)
	delete_map(world.types_to_components)
	delete_map(world.ids_to_components)
	delete_map(world.pipelines)

	for query in world.queries {
		destroy_query(query)
	}

	for _, archetypes in world.archetype_index {
		delete_map(archetypes)
	}

	archetype_graph_deinit(&world.archetypes)
	delete_map(world.archetype_index)
	delete_dynamic_array(world.queries)
	free(world, world.allocator)
}

pipeline_with_id :: proc(world: ^World, entity: EntityId) {
	query := query(world, term(world, System), term(world, entity), allocator = world.allocator)

	world.pipelines[entity] = Pipeline{entity, query}
}

pipeline :: proc(world: ^World, name: string) -> EntityId {
	ensure(!world.snapshot, "Cannot create a pipeline on a snapshot world")

	entity := new(world, name)

	pipeline_with_id(world, entity)

	return entity
}

new :: proc(world: ^World, name: string = "", flags: u8 = 0) -> EntityId {
	ensure(world.next_entity_id <= world.config.id_range[1])
	entity := build_entity_id(world.next_entity_id, 0, flags)

	new_with_id(world, entity, name)

	world.next_entity_id += 1

	return entity
}

delete :: proc(world: ^World, entity: EntityId, by_user := true) {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(is_valid(world, entity))

	entry := &world.entities[entity]

	when ECS_DEBUG {
		entity_str := entity_to_str(world, entity)
		defer delete(entity_str)
		debug_log("%s requested to delete %s", by_user ? "User" : "System", entity_str)
	}

	emit(world, Event_Deleted, entity)

	cleanup_archetypes(world, entity, entity, false)
	cleanup_archetypes(world, build_pair(Wildcard, entity), entity, true)
	cleanup_archetypes(world, build_pair(entity, Wildcard), entity, true)

	move_entity(world, entry, nil, entry.row, 0)

	if entry.name != "" {
		ensure(entry.name in world.names_index)
		delete_key(&world.names_index, entry.name)
	}

	delete_key(&world.entities, entity)
}

new_with_id :: proc(world: ^World, entity: EntityId, name: string = "") {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	if entity in world.entities {
		fmt.panicf("entity {} (info: {}) already exists", entity_to_str(world, entity))
	}

	root := world.archetypes.root
	chunk, row := archetype_add_entity(world, &root.archetype, entity)
	entry := Entity_Entry{entity, name, row, chunk}

	world.entities[entity] = entry

	if name != "" {
		fmt.ensuref(
			name not_in world.names_index,
			"An entity with the name %s already exists",
			name,
		)

		world.names_index[name] = entity
	}

	when ECS_DEBUG {
		debug_log("Created entity %d, name = %s", entry.id, entry.name)
	}
}

declare :: proc(world: ^World, $T: typeid, name: string = "", flags: u8 = 0) -> EntityId {
	entity := new(world, name, flags)

	return declare_type(world, entity, T, size_of(T))
}

declare_with_id :: proc(
	world: ^World,
	entity: EntityId,
	$T: typeid,
	name: string = "",
	flags: u8 = 0,
) -> EntityId {
	new_with_id(world, entity, name)

	return declare_type(world, entity, T, size_of(T))
}

declare_type :: proc(world: ^World, entity: EntityId, type: typeid, size: int) -> EntityId {
	ctype := Component_Type{type, entity, size}

	world.types_to_components[type] = ctype
	world.ids_to_components[entity] = ctype

	add(world, entity, TypeTrait)

	return entity
}

system :: proc {
	system_default,
	system_pipeline,
	system_default_no_ctx,
	system_pipeline_no_ctx,
	system_default_str,
	system_pipeline_str,
	system_default_no_ctx_str,
	system_pipeline_no_ctx_str,
}

system_default :: proc(
	world: ^World,
	procedure: System_Proc,
	ctx: rawptr,
	terms: ..Query_Term,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	system_pipeline(
		world,
		procedure,
		Pipeline_Default,
		ctx,
		..terms,
		before_update_proc = before_update_proc,
		after_update_proc = after_update_proc,
		cascade = cascade,
	)
}

system_pipeline :: proc(
	world: ^World,
	procedure: System_Proc,
	pipeline: EntityId,
	ctx: rawptr,
	terms: ..Query_Term,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	ensure(is_valid(world, pipeline))
	system := new(world)

	q: ^Query

	if len(terms) > 0 {
		q = query(world, ..terms, cascade = cascade, allocator = world.allocator)
	}

	set(world, system, &System{q, procedure, before_update_proc, after_update_proc, ctx})
	add(world, system, pipeline)
}

system_default_str :: proc(
	world: ^World,
	procedure: System_Proc,
	ctx: rawptr,
	query_str: string,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	system_pipeline_str(
		world,
		procedure,
		Pipeline_Default,
		ctx,
		query_str,
		before_update_proc = before_update_proc,
		after_update_proc = after_update_proc,
	)
}

system_pipeline_str :: proc(
	world: ^World,
	procedure: System_Proc,
	pipeline: EntityId,
	ctx: rawptr,
	query_str: string,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	ensure(is_valid(world, pipeline))
	system := new(world)

	query := query(world, query_str, cascade = cascade, allocator = world.allocator)

	set(world, system, &System{query, procedure, before_update_proc, after_update_proc, ctx})
	add(world, system, pipeline)
}

system_default_no_ctx :: proc(
	world: ^World,
	procedure: System_Proc,
	terms: ..Query_Term,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	system_default(
		world,
		procedure,
		nil,
		..terms,
		before_update_proc = before_update_proc,
		after_update_proc = after_update_proc,
		cascade = cascade,
	)
}

system_pipeline_no_ctx :: proc(
	world: ^World,
	procedure: System_Proc,
	pipeline: EntityId,
	terms: ..Query_Term,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	system_pipeline(
		world,
		procedure,
		pipeline,
		nil,
		..terms,
		before_update_proc = before_update_proc,
		after_update_proc = after_update_proc,
		cascade = cascade,
	)
}

system_default_no_ctx_str :: proc(
	world: ^World,
	procedure: System_Proc,
	query_str: string,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	system_default_str(
		world,
		procedure,
		nil,
		query_str,
		before_update_proc = before_update_proc,
		after_update_proc = after_update_proc,
		cascade = cascade,
	)
}

system_pipeline_no_ctx_str :: proc(
	world: ^World,
	procedure: System_Proc,
	pipeline: EntityId,
	query_str: string,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	system_pipeline_str(
		world,
		procedure,
		pipeline,
		nil,
		query_str,
		before_update_proc = before_update_proc,
		after_update_proc = after_update_proc,
		cascade = cascade,
	)
}

watch :: proc {
	watch_no_ctx,
	watch_ctx,
	watch_no_ctx_str,
	watch_ctx_str,
	watch_ctx_query,
}

watch_no_ctx :: proc(
	world: ^World,
	event: EntityId,
	procedure: Watcher_Proc,
	terms: ..Query_Term,
) {
	watch_ctx(world, event, procedure, nil, ..terms)
}

watch_no_ctx_str :: proc(
	world: ^World,
	event: EntityId,
	procedure: Watcher_Proc,
	query_str: string,
) {
	watch_ctx_str(world, event, procedure, nil, query_str)
}

watch_ctx :: proc(
	world: ^World,
	event: EntityId,
	procedure: Watcher_Proc,
	ctx: rawptr,
	terms: ..Query_Term,
) {
	query := query(world, ..terms, allocator = world.allocator)

	watch_ctx_query(world, event, procedure, ctx, query)
}

watch_ctx_str :: proc(
	world: ^World,
	event: EntityId,
	procedure: Watcher_Proc,
	ctx: rawptr,
	query_str: string,
) {
	query := query(world, query_str, allocator = world.allocator)

	watch_ctx_query(world, event, procedure, ctx, query)
}

watch_ctx_query :: proc(
	world: ^World,
	event: EntityId,
	procedure: Watcher_Proc,
	ctx: rawptr,
	query: ^Query,
) {
	watcher := new(world)

	set_pair(world, watcher, &Watcher{query, procedure, ctx}, event)
}

emit :: proc {
	emit_no_data,
	emit_data,
}

emit_data :: proc(world: ^World, event: EntityId, entity: EntityId, data: rawptr) {
	ensure(is_valid(world, event))
	ensure(is_valid(world, entity))

	entry := &world.entities[entity]
	archetype := entry.chunk.archetype

	watcher_pair := build_pair(world, Watcher, event)
	it := iter(world, term(world, watcher_pair), allocator = context.temp_allocator)

	for iter_next_match(&it) {
		watcher_col := column(&it, 0)

		for chunk in iter_next_chunk(&it) {
			for row := 0; row < len(chunk.entities); row += 1 {
				watcher := row_data(chunk, watcher_col, row, Watcher)

				if query_matches_archetype(watcher.query, archetype) {
					match := evaluate_archetype(
						world,
						watcher.query.terms,
						archetype,
						context.temp_allocator,
					) or_continue
					it2 := Query_Iterator {
						world,
						watcher.query.terms,
						[]Query_Match{match},
						&match,
						entry.chunk,
						0,
						0,
					}

					watcher.procedure(world, entity, &it2, entry.row, watcher.ctx, data)
				}
			}
		}
	}
}

emit_no_data :: proc(world: ^World, event: EntityId, entity: EntityId) {
	emit_data(world, event, entity, nil)
}

exists :: proc(world: ^World, entity: EntityId) -> bool {
	return entity in world.entities
}

is_valid :: proc(world: ^World, entity: EntityId) -> bool {
	return entity > 0 && exists(world, entity)
}

build_pair :: proc {
	build_pair_with_ids,
	build_pair_1,
	build_pair_2,
}

build_pair_with_ids :: proc(first: EntityId, second: EntityId) -> EntityId {
	return (u64(first) << 32) | u64(second)
}

build_pair_1 :: proc(world: ^World, $T: typeid, second: EntityId) -> EntityId {
	first := get_type_id(world, T)

	return build_pair_with_ids(first, second)
}

build_pair_2 :: proc(world: ^World, first: EntityId, $T: typeid) -> EntityId {
	second := get_type_id(world, T)

	return build_pair_with_ids(first, second)
}

pair_first :: proc(pair: EntityId) -> EntityId {
	return pair >> 32
}

pair_second :: proc(pair: EntityId) -> EntityId {
	return pair & 0xffffffff
}

pair_split :: proc(pair: EntityId) -> (first: EntityId, second: EntityId) {
	first = pair_first(pair)
	second = pair_second(pair)

	return
}

pair_contains :: proc(pair: EntityId, entity: EntityId) -> bool {
	ensure(is_pair(pair))

	first, second := pair_split(pair)

	return first == entity || second == entity
}

is_pair :: proc(entity: EntityId) -> bool {
	return (entity & 0xFFFFFFFF00000000) > 0
}

is_unique_pair :: proc(world: ^World, entity: EntityId) -> bool {
	is_pair := is_pair(entity)

	if !is_pair {
		return false
	}

	first, _ := pair_split(entity)

	return has(world, first, UniquePair)
}

is_wildcard_pair :: proc(entity: EntityId) -> bool {
	first, second := pair_split(entity)

	return first == Wildcard || second == Wildcard
}

is_type :: proc(world: ^World, entity: EntityId) -> bool {
	return exists(world, entity) && has(world, entity, TypeTrait)
}

is_tag :: proc(world: ^World, entity: EntityId) -> bool {
	return !is_type(world, entity)
}

get_component_type :: proc {
	get_component_type_by_id,
	get_component_type_by_type,
}

get_component_type_by_type :: proc(world: ^World, $T: typeid) -> Component_Type {
	ensure(T in world.types_to_components)

	return world.types_to_components[T]
}

get_component_type_by_id :: proc(world: ^World, id: EntityId) -> Component_Type {
	ensure(id in world.ids_to_components)

	return world.ids_to_components[id]
}

get_type_id :: proc(world: ^World, $T: typeid) -> EntityId {
	type := get_component_type(world, T)

	ensure(is_type(world, type.id))

	return type.id
}

get_component_size :: proc(world: ^World, component_id: EntityId) -> int {
	if is_pair(component_id) {
		return get_pair_size(world, component_id)
	} else {
		ensure(is_valid(world, component_id))
		component_type, exists := world.ids_to_components[component_id]

		return exists ? component_type.size : 0
	}
}

get_pair_type :: proc(world: ^World, pair: EntityId) -> EntityId {
	ensure(is_pair(pair))

	first, second := pair_split(pair)
	first_is_type := is_type(world, first)
	second_is_type := !first_is_type && is_type(world, second)

	if first_is_type {
		return first
	}

	if second_is_type {
		return second
	}

	return 0
}

get_pair_size :: proc(world: ^World, pair: EntityId) -> int {
	ensure(is_pair(pair))

	component_id := get_pair_type(world, pair)

	return component_id > 0 ? get_component_size(world, component_id) : 0
}

add :: proc {
	add_by_name,
	add_by_id,
}

add_by_name :: proc(world: ^World, entity: EntityId, add_entity_name: string) -> bool {
	add_entity := find(world, add_entity_name)

	return add_by_id(world, entity, add_entity)
}

add_by_id :: proc(world: ^World, entity: EntityId, add_entity: EntityId) -> bool {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(is_valid(world, entity))

	is_pair := is_pair(add_entity)

	ensure(is_valid(world, add_entity) || is_pair)

	entity_entry := &world.entities[entity]
	src_archetype := entity_entry.chunk.archetype

	if archetype_has(src_archetype, add_entity) {
		return false
	}

	src_node := src_archetype.node
	dest_node: ^ArchetypeNode

	if is_pair && is_unique_pair(world, add_entity) {
		first, _ := pair_split(add_entity)
		unique_pair := archetype_get_pair(entity_entry.chunk.archetype, first)

		if unique_pair > 0 {
			dest_node = archetype_graph_replace(
				world,
				&world.archetypes,
				src_node,
				unique_pair,
				add_entity,
			)
		}
	}

	src_row := entity_entry.row

	if dest_node == nil {
		dest_node = archetype_graph_add(world, &world.archetypes, src_node, add_entity)
	}

	when ECS_DEBUG {
		entity_str := entity_to_str(world, entity)
		defer delete(entity_str)
		add_entity_str := entity_to_str(world, add_entity)
		defer delete(add_entity_str)

		debug_log("Added %s to %s", add_entity_str, entity_str)
	}

	dest_chunk, dest_row := archetype_add_entity(world, &dest_node.archetype, entity)

	move_entity(world, entity_entry, dest_chunk, src_row, dest_row)

	return true
}

add_pair :: proc {
	add_pair_ids,
	add_pair_name_1,
	add_pair_name_2,
}

add_pair_ids :: proc(world: ^World, entity: EntityId, first: EntityId, second: EntityId) -> bool {
	ensure(is_valid(world, entity))

	pair := build_pair(first, second)

	return add(world, entity, pair)
}

add_pair_name_1 :: proc(world: ^World, entity: EntityId, first: string, second: EntityId) -> bool {
	return add_pair_ids(world, entity, find(world, first), second)
}

add_pair_name_2 :: proc(world: ^World, entity: EntityId, first: EntityId, second: string) -> bool {
	return add_pair_ids(world, entity, first, find(world, second))
}

remove_pair :: proc {
	remove_pair_id,
	remove_pair_1,
	remove_pair_2,
}

remove_pair_id :: proc(
	world: ^World,
	entity: EntityId,
	first: EntityId,
	second: EntityId,
) -> bool {
	ensure(is_valid(world, entity))

	pair := build_pair(first, second)

	return remove(world, entity, pair)
}

remove_pair_1 :: proc(world: ^World, entity: EntityId, $T: typeid, second: EntityId) -> bool {
	ensure(is_valid(world, entity))

	pair := build_pair(world, T, second)

	return remove(world, entity, pair)
}

remove_pair_2 :: proc(world: ^World, entity: EntityId, first: EntityId, $T: typeid) -> bool {
	ensure(is_valid(world, entity))

	pair := build_pair(world, first, T)

	return remove(world, entity, pair)
}

set :: proc {
	set_with_type,
	set_with_id,
}

set_with_type :: proc(world: ^World, entity: EntityId, data: ^$T) {
	component_id := get_type_id(world, T)
	ensure(is_type(world, component_id))
	set_with_id(world, entity, component_id, data)
}

set_with_id :: proc(world: ^World, entity: EntityId, component_id: EntityId, data: rawptr) {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(is_valid(world, entity))
	ensure(is_pair(component_id) || is_type(world, component_id))

	add(world, entity, component_id)

	entity_entry := &world.entities[entity]
	chunk := entity_entry.chunk
	assert(chunk.entities[entity_entry.row] == entity)
	col_idx := chunk.archetype.component_column_map[component_id]

	archetype_chunk_set_data(chunk, col_idx, entity_entry.row, data)
}

set_pair :: proc {
	set_pair_with_id,
	set_pair_1,
	set_pair_2,
}

set_pair_with_id :: proc(
	world: ^World,
	entity: EntityId,
	first: EntityId,
	second: EntityId,
	data: ^$T,
) {
	set_with_id(world, entity, build_pair(first, second), data)
}

set_pair_1 :: proc(world: ^World, entity: EntityId, data: ^$T, second: EntityId) {
	set_pair_with_id(world, entity, get_type_id(world, T), second, data)
}

set_pair_2 :: proc(world: ^World, entity: EntityId, first: EntityId, data: ^$T) {
	set_pair_with_id(world, entity, first, get_type_id(world, T), data)
}

remove :: proc {
	remove_id,
	remove_type,
	remove_name,
}

remove_id :: proc(world: ^World, entity: EntityId, rm_entity: EntityId) -> bool {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(is_valid(world, entity))
	ensure(is_valid(world, rm_entity) || is_pair(rm_entity))

	entity_entry := &world.entities[entity]
	src_node := entity_entry.chunk.archetype.node

	if !archetype_has(&src_node.archetype, rm_entity) {
		return false
	}

	dest_node := archetype_graph_remove(world, &world.archetypes, src_node, rm_entity)
	src_row := entity_entry.row
	dest_chunk, dest_row := archetype_add_entity(world, &dest_node.archetype, entity)

	move_entity(world, entity_entry, dest_chunk, src_row, dest_row)

	return true
}

remove_type :: proc(world: ^World, entity: EntityId, rm: typeid) -> bool {
	component_type, exists := world.types_to_components[rm]
	ensure(exists)

	return remove_id(world, entity, component_type.id)
}

remove_name :: proc(world: ^World, entity: EntityId, rm_name: string) -> bool {
	rm := find(world, rm_name)

	return remove_id(world, entity, rm)
}

has :: proc {
	has_id,
	has_type,
	has_name,
}

has_id :: proc(world: ^World, entity: EntityId, other: EntityId) -> bool {
	ensure(is_valid(world, entity))
	ensure(is_valid(world, other) || is_pair(other))

	entity_entry := &world.entities[entity]

	return archetype_has(entity_entry.chunk.archetype, other)
}

has_type :: proc(world: ^World, entity: EntityId, $T: typeid) -> bool {
	component_id := get_type_id(world, T)
	ensure(is_type(world, component_id))

	return has_id(world, entity, component_id)
}

has_name :: proc(world: ^World, entity: EntityId, name: string) -> bool {
	other := find(world, name)

	return has_id(world, entity, other)
}

has_pair :: proc {
	has_pair_id,
	has_pair_type_1,
	has_pair_type_2,
	has_pair_name_1,
	has_pair_name_2,
}

has_pair_id :: proc(world: ^World, entity: EntityId, first: EntityId, second: EntityId) -> bool {
	ensure(is_valid(world, entity))

	return has(world, entity, build_pair(first, second))
}

has_pair_type_1 :: proc(world: ^World, entity: EntityId, $T: typeid, second: EntityId) -> bool {
	return has_pair(world, entity, get_type_id(world, T), second)
}

has_pair_type_2 :: proc(world: ^World, entity: EntityId, first: EntityId, $T: typeid) {
	return has_pair(world, entity, first, get_type_id(world, T))
}

has_pair_name_1 :: proc(world: ^World, entity: EntityId, first: string, second: EntityId) -> bool {
	return has_pair(world, entity, find(world, first), second)
}

has_pair_name_2 :: proc(world: ^World, entity: EntityId, first: EntityId, second: string) -> bool {
	return has_pair(world, entity, first, find(world, second))
}

get :: proc(world: ^World, entity: EntityId, $T: typeid) -> T {
	ensure(is_valid(world, entity))

	component_id := get_component_type(world, T).id

	ensure(is_pair(component_id) || is_valid(world, component_id))
	ensure(has(world, entity, component_id))

	entity_entry := &world.entities[entity]
	chunk := entity_entry.chunk
	row := entity_entry.row
	assert(chunk.entities[entity_entry.row] == entity)
	col_idx := chunk.archetype.component_column_map[component_id]
	ptr := (^T)(archetype_chunk_get_data(chunk, col_idx, row))

	return ptr^
}

get_mut :: proc(world: ^World, entity: EntityId, $T: typeid) -> ^T {
	component_id := get_component_type(world, T).id

	return (^T)(get_mut_with_id(world, entity, component_id))
}

get_mut_with_id :: proc(world: ^World, entity: EntityId, component_id: EntityId) -> rawptr {
	if world.frozen {
		panic("Attempted to retrieve mutable data from a frozen world")
	}

	ensure(is_valid(world, entity))
	ensure(is_pair(component_id) || is_valid(world, component_id))
	ensure(has(world, entity, component_id))

	entity_entry := &world.entities[entity]
	chunk := entity_entry.chunk
	row := entity_entry.row
	assert(chunk.entities[entity_entry.row] == entity)
	col_idx := chunk.archetype.component_column_map[component_id]

	return archetype_chunk_get_data(chunk, col_idx, row)
}

get_pair :: proc {
	get_pair_1,
	get_pair_2,
}
get_pair_mut :: proc {
	get_pair_mut_1,
	get_pair_mut_2,
}

get_pair_1 :: proc(world: ^World, entity: EntityId, $T: typeid, second: EntityId) -> T {
	return get_pair_mut_1(world, entity, T, second)^
}

get_pair_2 :: proc(world: ^World, entity: EntityId, first: EntityId, $T: typeid) -> T {
	return get_pair_mut_1(world, entity, first, T)^
}

get_pair_mut_1 :: proc(world: ^World, entity: EntityId, $T: typeid, second: EntityId) -> ^T {
	pair_id := build_pair(get_component_type(world, T).id, second)

	return (^T)(get_mut_with_id(world, entity, pair_id))
}

get_pair_mut_2 :: proc(world: ^World, entity: EntityId, first: EntityId, second: $T) -> ^T {
	pair_id := build_pair(first, get_component_type(world, T).id)

	return (^T)(get_mut_with_id(world, entity, pair_id))
}

get_entity_pair :: proc(world: ^World, entity: EntityId, first: EntityId) -> EntityId {
	ensure(is_valid(world, entity))
	ensure(is_valid(world, first))

	entity_entry := &world.entities[entity]

	return archetype_get_pair(entity_entry.chunk.archetype, first)
}

get_entity_pairs :: proc {
	get_entity_pairs_id,
	get_entity_pairs_type,
}

get_entity_pairs_id :: proc(world: ^World, entity: EntityId, first: EntityId) -> []EntityId {
	ensure(is_valid(world, entity))
	ensure(is_valid(world, first))

	entity_entry := &world.entities[entity]

	return archetype_get_pairs(entity_entry.chunk.archetype, first)
}

get_entity_pairs_type :: proc(world: ^World, entity: EntityId, $T: typeid) -> []EntityId {
	return get_entity_pairs_id(world, entity, get_type_id(world, T))
}

get_entity_id :: proc(entity: EntityId) -> EntityId {
	return EntityId(u32(entity) & 0x00FFFFFF)
}

get_entity_flags :: proc(entity: EntityId) -> u8 {
	return u8(u32(entity) >> 24)
}

get_generation :: proc(entity: EntityId) -> u16 {
	return u16(entity >> 32)
}

build_entity_id :: proc(id: EntityId, gen: u16, flags: u8 = 0) -> EntityId {
	ensure(id <= EntityId_Raw_Max)
	id_with_flags := u32(id) | (u32(flags) << 24)
	return u64(id_with_flags) | (u64(gen) << 32)
}

update :: proc(world: ^World, dt: f64, pipeline := Pipeline_Default) {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(len(world.pipelines) > 0)

	pipeline := world.pipelines[pipeline] // default pipeline

	it := iter(pipeline.query)

	for iter_next_match(&it) {
		col := column(&it, 0)

		for chunk in iter_next_chunk(&it) {
			for row := 0; row < len(chunk.entities); row += 1 {
				system := row_data(chunk, col, row, System)

				update_system(world, &system, dt)
			}
		}
	}

	world.info.entity_count = len(world.entities)
	world.info.archetype_count = len(world.archetypes.nodes)
}

update_system :: proc(world: ^World, system_data: ^System, dt: f64) {
	if system_data.before_update_proc != nil {
		system_data.before_update_proc(world, dt, system_data.ctx)
	}

	if system_data.query == nil {
		system_data.update_proc(world, nil, dt, system_data.ctx)
	} else {
		it := iter(system_data.query)

		for iter_next_match(&it) {
			system_data.update_proc(world, &it, dt, system_data.ctx)
		}
	}

	if system_data.after_update_proc != nil {
		system_data.after_update_proc(world, dt, system_data.ctx)
	}
}

set_parent :: proc(world: ^World, entity: EntityId, parent: EntityId) {
	ensure(is_valid(world, entity))
	ensure(is_valid(world, parent))

	depth := get_entity_depth(world, parent)

	set_pair(world, entity, ChildOf_Id, parent, &ChildOf{depth + 1})
}

get_parent :: proc(world: ^World, entity: EntityId) -> EntityId {
	ensure(is_valid(world, entity))

	entity_entry := &world.entities[entity]
	pair := archetype_get_pair(entity_entry.chunk.archetype, ChildOf_Id)
	_, parent := pair_split(pair)

	return parent
}

get_children :: proc(
	world: ^World,
	entity: EntityId,
	allocator := context.allocator,
) -> []EntityId {
	childof_pair := build_pair(ChildOf_Id, entity)
	it := iter(world, term(world, childof_pair), allocator = allocator)

	children := make([dynamic]EntityId, allocator = allocator)

	for iter_next_match(&it) {
		for chunk in iter_next_chunk(&it) {
			for row := 0; row < len(chunk.entities); row += 1 {
				append(&children, chunk.entities[row])
			}
		}
	}

	return children[:]
}

get_entity_depth :: proc(world: ^World, entity: EntityId) -> int {
	entry := &world.entities[entity]

	return entry.chunk.archetype.depth
}

get_name :: proc(world: ^World, entity: EntityId) -> string {
	ensure(is_valid(world, entity))

	return world.entities[entity].name
}

find_safe :: proc(world: ^World, name: string) -> (entity: EntityId, exists: bool) {
	entity, exists = world.names_index[name]
	ensure(!exists || is_valid(world, entity))

	return
}

find :: proc(world: ^World, name: string) -> EntityId {
	entity, exists := find_safe(world, name)
	ensure(!exists || is_valid(world, entity))

	return entity
}

set_id_range :: proc(world: ^World, range: [2]EntityId, set_next_id := true) {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	r_min := range[0]
	r_max := range[1]

	ensure(r_min > ReservedIDs && r_max <= EntityId_Raw_Max)

	world.config.id_range = [2]EntityId{r_min, r_max}

	if set_next_id {
		world.next_entity_id = world.config.id_range[0]
	}
}

set_default_delete_strategy :: proc(world: ^World, strategy: EntityId) {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(strategy == DeleteStrategy_Delete || strategy == DeleteStrategy_Remove)

	world.config.default_delete_strategy = strategy
}

set_context :: proc(world: ^World, ctx: rawptr) {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	world.ctx = ctx
}

set_deletion_strategy :: proc(world: ^World, entity: EntityId, strategy: EntityId) {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(strategy == DeleteStrategy_Remove || strategy == DeleteStrategy_Delete)

	if get_deletion_strategy(world, entity) == strategy {
		return
	}

	add(world, entity, build_pair(OnDelete, strategy))
}

prefab :: proc(world: ^World, name := "") -> EntityId {
	prefab := new(world, name)

	add(world, prefab, Prefab)
	return prefab
}

is_prefab :: proc(world: ^World, entity: EntityId) -> bool {
	return has(world, entity, Prefab)
}

new_instance_of :: proc(world: ^World, prefab: EntityId, name := "") -> EntityId {
	ensure(is_prefab(world, prefab))

	entity := new(world, name)

	prefab_entry := &world.entities[prefab]
	entity_entry := &world.entities[entity]
	src_chunk := prefab_entry.chunk
	src_row := prefab_entry.row
	dest_chunk, dest_row := archetype_add_entity(world, src_chunk.archetype, entity)

	entity_entry.chunk = dest_chunk
	entity_entry.row = dest_row

	archetype_chunk_copy_row(src_chunk, dest_chunk, src_row, dest_row)
	remove(world, entity, Prefab)

	prefab_children := get_children(world, prefab, allocator = context.temp_allocator)

	for prefab_child in prefab_children {
		child := new_instance_of(world, prefab_child)

		set_parent(world, child, entity)
	}

	return entity
}

@(private)
move_entity :: proc {
	move_entity_to_existing_row,
	move_entity_to_new_row,
}

@(private)
move_entity_to_existing_row :: proc(
	world: ^World,
	entity_entry: ^Entity_Entry,
	dest_chunk: ^Archetype_Chunk,
	src_row: int,
	dest_row: int,
) {
	src_chunk := entity_entry.chunk
	src_archetype := src_chunk.archetype

	when ECS_DEBUG {
		entity_str := entity_to_str(world, entity_entry.id)
		defer delete(entity_str)
		src_arch_str := archetype_to_str(world, src_archetype)
		defer delete(src_arch_str)
		dest_arch_str := dest_chunk != nil ? archetype_to_str(world, dest_chunk.archetype) : "NULL"
		debug_log("Move %s from %s to %s", entity_str, src_arch_str, dest_arch_str)
		defer if dest_chunk != nil {
			delete(dest_arch_str)
		}
	}

	entity_entry.row = dest_row
	entity_entry.chunk = dest_chunk

	if dest_chunk != nil {
		archetype_chunk_copy_row(src_chunk, dest_chunk, src_row, dest_row)
	}

	moved_entity := archetype_delete_entity(src_archetype, src_chunk, src_row)

	if moved_entity != 0 {
		moved_entry := &world.entities[moved_entity]

		moved_entry.row = src_row
	}
}

@(private)
move_entity_to_new_row :: proc(
	world: ^World,
	entity_entry: ^Entity_Entry,
	dest_archetype: ^Archetype,
	src_row: int,
) {
	dest_chunk, dest_row := archetype_add_entity(world, dest_archetype, entity_entry.id)

	move_entity_to_existing_row(world, entity_entry, dest_chunk, src_row, dest_row)
}

@(private)
index_archetype :: proc(world: ^World, entity: EntityId, archetype: ^Archetype) {
	if entity not_in world.archetype_index {
		world.archetype_index[entity] = make(Archetype_Map, world.allocator)
	}

	archetype_map := &world.archetype_index[entity]
	hash := archetype.component_set.hash

	archetype_map[hash] = archetype
}

@(private)
on_archetype_created :: proc(world: ^World, archetype: ^Archetype) {
	for component_id, _ in archetype.component_set.components {
		index_archetype(world, component_id, archetype)

		if is_pair(component_id) {
			ensure(!is_wildcard_pair(component_id))

			first, second := pair_split(component_id)

			index_archetype(world, build_pair(first, Wildcard), archetype)
			index_archetype(world, build_pair(Wildcard, second), archetype)
		}
	}

	if !world.snapshot {
		for query in world.queries {
			query_on_archertype_created(query, archetype)
		}
	}
}

@(private)
on_archetype_deleted :: proc(
	world: ^World,
	archetype: ^Archetype,
	deleted_entity: EntityId,
	relationship: bool,
) {
	ensure(!archetype.is_root)
	ensure(!is_pair(deleted_entity))

	when ECS_DEBUG {
		arch_str := archetype_to_str(world, archetype)
		defer delete(arch_str)

		debug_log("%s destroyed", arch_str)
	}

	strategy := get_deletion_strategy(world, deleted_entity)
	entities := make([]EntityId, archetype.chunk_capacity, context.temp_allocator)

	for chunk in archetype.chunks {
		chunk_count := len(chunk.entities)

		if chunk_count == 0 {
			continue
		}

		copied_count := copy(entities, chunk.entities[0:chunk_count])
		ensure(copied_count == chunk_count)

		for entity in entities[0:chunk_count] {
			if relationship {
				handle_relationship_deleted(world, entity, deleted_entity, strategy)
			} else {
				handle_normal_entity_deleted(world, entity, deleted_entity, strategy)
			}
		}
	}

	for query in world.queries {
		query_on_archertype_deleted(query, archetype)
	}

	for component, _ in archetype.component_set.components {
		if is_pair(component) {
			first, second := pair_split(component)
			pair1 := build_pair(first, Wildcard)
			pair2 := build_pair(Wildcard, second)

			ensure(pair1 in world.archetype_index)
			ensure(pair1 in world.archetype_index)

			archetype_map1 := &world.archetype_index[pair1]
			archetype_map2 := &world.archetype_index[pair2]

			delete_key(archetype_map1, archetype.component_set.hash)
			delete_key(archetype_map2, archetype.component_set.hash)
		} else {
			ensure(component in world.archetype_index)

			archetype_map := &world.archetype_index[component]
			delete_key(archetype_map, archetype.component_set.hash)
		}
	}
}

@(private)
handle_normal_entity_deleted :: proc(
	world: ^World,
	entity: EntityId,
	deleted_entity: EntityId,
	strategy: EntityId,
) {
	ensure(has(world, entity, deleted_entity))

	if strategy == DeleteStrategy_Remove {
		remove(world, entity, deleted_entity)
	} else if strategy == DeleteStrategy_Delete {
		delete(world, entity, by_user = false)
	} else {
		unreachable()
	}
}

@(private)
handle_relationship_deleted :: proc(
	world: ^World,
	entity: EntityId,
	deleted_entity: EntityId,
	strategy: EntityId,
) {
	if strategy == DeleteStrategy_Remove {
		entry := &world.entities[entity]
		set := &entry.chunk.archetype.component_set
		new_set := set_remove_relationship(set, deleted_entity, world.allocator)
		target_node, exists := archetype_graph_get_or_create(world, &world.archetypes, &new_set)

		if exists {
			set_destroy(&new_set)
		}

		move_entity(world, entry, &target_node.archetype, entry.row)
	} else if strategy == DeleteStrategy_Delete {
		delete(world, entity, by_user = false)
	} else {
		unreachable()
	}
}

@(private)
get_deletion_strategy :: proc(world: ^World, entity: EntityId) -> EntityId {
	if has(world, entity, build_pair(OnDelete, DeleteStrategy_Delete)) {
		return DeleteStrategy_Delete
	}

	if has(world, entity, build_pair(OnDelete, DeleteStrategy_Remove)) {
		return DeleteStrategy_Remove
	}

	return world.config.default_delete_strategy
}

@(private)
cleanup_archetypes :: proc(
	world: ^World,
	index_entity: EntityId,
	deleted_entity: EntityId,
	relationship: bool,
) {
	when ECS_DEBUG {
		entity_str :=
			is_pair(index_entity) ? pair_to_str(world, index_entity) : entity_to_str(world, index_entity)
		defer delete(entity_str)
		debug_log("Cleaning up archetypes for entity %s", entity_str)
	}

	if index_entity not_in world.archetype_index {
		when ECS_DEBUG {
			debug_log("No archetypes to cleanup for entity %s", entity_str)
		}

		return
	}

	ensure(index_entity in world.archetype_index)
	archetype_map := world.archetype_index[index_entity]

	for hash, _ in archetype_map {
		archetype_graph_cleanup(world, &world.archetypes, hash, deleted_entity, relationship)
	}

	delete_map(archetype_map)
	delete_key(&world.archetype_index, index_entity)
}
