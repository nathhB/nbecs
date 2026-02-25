package nbecs

ECS_DEBUG :: #config(ECS_DEBUG, false)

import "core:fmt"
import "core:log"
import "core:mem"
import vmem "core:mem/virtual"

EntityId :: u64

// raw entity ids have to fit in 3 bytes
// "raw" meaning the id without generation and id flags
EntityId_Raw_Max :: 16_777_215

ReservedIDs :: 32
@(thread_local)
TypeTrait: EntityId
@(thread_local)
Wildcard: EntityId
@(thread_local)
ChildOf_Id: EntityId
@(thread_local)
Pipeline_Default: EntityId
@(thread_local)
OnDelete: EntityId
@(thread_local)
UniquePair: EntityId
@(thread_local)
DeleteStrategy_Delete: EntityId
@(thread_local)
DeleteStrategy_Remove: EntityId
@(thread_local)
Prefab: EntityId
@(thread_local)
Event_Deleted: EntityId

ComponentType :: struct {
	type: typeid,
	id:   EntityId,
	size: int,
}

EntityEntry :: struct {
	id:    EntityId,
	name:  string,
	row:   int,
	chunk: ^Archetype_Chunk,
}

EntityId_Flags :: enum u8 {
	Reserved = 1, // indicate that the ID is reserved by the library
	Entity   = 2, // indicate that the ID is an entity (created via ecs_new)
}

ArchetypeMap :: #type map[u64]^Archetype
System_Proc :: #type proc(world: ^World, it: ^QueryIterator, dt: f64, ctx: rawptr) -> bool
System_Hook_Proc :: #type proc(world: ^World, dt: f64, ctx: rawptr)
Watcher_Proc :: #type proc(
	world: ^World,
	entity: EntityId,
	it: ^QueryIterator,
	row: int,
	ctx: rawptr,
	data: rawptr,
)

World :: struct {
	next_entity_id:      EntityId,
	entities:            map[EntityId]EntityEntry,
	names_index:         map[string]EntityId,
	types_to_components: map[typeid]ComponentType,
	ids_to_components:   map[EntityId]ComponentType,
	archetype_index:     map[EntityId]ArchetypeMap,
	archetypes:          ArchetypeGraph,
	queries:             [dynamic]^Query,
	ctx:                 rawptr,
	pipelines:           map[EntityId]Pipeline,
	config:              World_Config,
	arena:               vmem.Arena,
	temp_allocator:      mem.Allocator,
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

ecs_create :: proc(allocator := context.allocator) -> ^World {
	world := new(World, allocator)

	world.next_entity_id = 1
	world.config.id_range = [2]EntityId{1, ReservedIDs + 1}
	world.entities = make(map[EntityId]EntityEntry, allocator)
	world.names_index = make(map[string]EntityId, allocator)
	world.types_to_components = make(map[typeid]ComponentType, allocator)
	world.ids_to_components = make(map[EntityId]ComponentType, allocator)
	world.archetype_index = make(map[EntityId]ArchetypeMap, allocator)
	world.allocator = allocator
	world.snapshot = false
	world.pipelines = make(map[EntityId]Pipeline, allocator)
	world.queries = make([dynamic]^Query, allocator)

	err := vmem.arena_init_growing(&world.arena)
	ensure(err == nil)
	world.temp_allocator = vmem.arena_allocator(&world.arena)

	archetype_graph_init(world, &world.archetypes, allocator)

	TypeTrait = ecs_new(world, "TypeTrait")
	Wildcard = ecs_new(world, "*", u8(EntityId_Flags.Reserved))
	OnDelete = ecs_new(world, "OnDelete")
	DeleteStrategy_Delete = ecs_new(world, "Delete")
	DeleteStrategy_Remove = ecs_new(world, "Remove")
	UniquePair = ecs_new(world, "UniquePair")
	Prefab = ecs_new(world, "Prefab")
	Event_Deleted = ecs_new(world, "Event_Deleted")


	ecs_declare(world, System, "System")
	Pipeline_Default = ecs_pipeline(world, "DefaultPipeline")
	ecs_declare(world, Watcher, "Watcher")
	ChildOf_Id = ecs_declare(world, ChildOf, "ChildOf")

	ecs_add(world, ChildOf_Id, UniquePair)

	ensure(world.next_entity_id <= ReservedIDs + 1)
	world.config.default_delete_strategy = DeleteStrategy_Remove
	ecs_set_id_range(world, ReservedIDs + 1, u64(max(u32)))

	return world
}

ecs_create_snapshot :: proc(allocator := context.allocator) -> ^World {
	world := new(World, allocator)

	world.next_entity_id = 1
	world.entities = make(map[EntityId]EntityEntry, allocator)
	world.names_index = make(map[string]EntityId, allocator)
	world.types_to_components = make(map[typeid]ComponentType, allocator)
	world.ids_to_components = make(map[EntityId]ComponentType, allocator)
	world.archetype_index = make(map[EntityId]ArchetypeMap, allocator)
	world.allocator = allocator
	world.snapshot = true

	archetype_graph_init(world, &world.archetypes, allocator, create_root = false)

	return world
}

ecs_destroy :: proc(world: ^World) {
	ensure(!world.snapshot)

	delete(world.entities)
	delete(world.names_index)
	delete(world.types_to_components)
	delete(world.ids_to_components)
	delete(world.pipelines)

	for query in world.queries {
		query_destroy(query)
	}

	for _, archetypes in world.archetype_index {
		delete(archetypes)
	}

	archetype_graph_deinit(&world.archetypes)
	delete(world.archetype_index)
	delete(world.queries)
	free(world, world.allocator)
}

ecs_pipeline :: proc(world: ^World, name: string) -> EntityId {
	ensure(!world.snapshot, "Cannot create a pipeline on a snapshot world")

	entity := ecs_new(world, name)
	query := query_build(
		world,
		query_term(world, System),
		query_term(world, entity),
		allocator = world.allocator,
	)

	world.pipelines[entity] = Pipeline{entity, query}

	return entity
}

ecs_new :: proc(world: ^World, name: string = "", flags: u8 = 0) -> EntityId {
	ensure(world.next_entity_id <= world.config.id_range[1])
	flags := flags
	flags |= u8(EntityId_Flags.Entity)
	entity := ecs_build_entity_id(world.next_entity_id, 0, flags)

	ecs_new_with_id(world, entity, name)

	world.next_entity_id += 1

	return entity
}

ecs_delete :: proc(world: ^World, entity: EntityId, by_user := true) {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(ecs_is_valid(world, entity))

	entry := &world.entities[entity]

	when ECS_DEBUG {
		entity_str := ecs_entity_to_str(world, entity)
		defer delete(entity_str)
		ecs_debug_log("%s requested to delete %s", by_user ? "User" : "System", entity_str)
	}

	ecs_emit(world, Event_Deleted, entity)

	cleanup_archetypes(world, entity, entity, false)
	cleanup_archetypes(world, ecs_build_pair(Wildcard, entity), entity, true)
	cleanup_archetypes(world, ecs_build_pair(entity, Wildcard), entity, true)

	move_entity(world, entry, nil, entry.row, 0)

	if entry.name != "" {
		ensure(entry.name in world.names_index)

		delete_key(&world.names_index, entry.name)
	}

	delete_key(&world.entities, entity)
}

ecs_new_with_id :: proc(world: ^World, entity: EntityId, name: string = "") {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(entity not_in world.entities)

	root := world.archetypes.root
	chunk, row := archetype_add_entity(world, &root.archetype, entity)
	entry := EntityEntry{entity, name, row, chunk}

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
		ecs_debug_log("Created entity %d, name = %s", entry.id, entry.name)
	}
}

ecs_declare :: proc(world: ^World, $T: typeid, name: string = "", flags: u8 = 0) -> EntityId {
	entity := ecs_new(world, name, flags)

	return ecs_declare_type(world, entity, T, size_of(T))
}

ecs_declare_type :: proc(world: ^World, entity: EntityId, type: typeid, size: int) -> EntityId {
	ctype := ComponentType{type, entity, size}

	world.types_to_components[type] = ctype
	world.ids_to_components[entity] = ctype

	ecs_add(world, entity, TypeTrait)

	return entity
}

ecs_system :: proc {
	ecs_system_default,
	ecs_system_pipeline,
	ecs_system_default_no_ctx,
	ecs_system_pipeline_no_ctx,
	ecs_system_default_str,
	ecs_system_pipeline_str,
	ecs_system_default_no_ctx_str,
	ecs_system_pipeline_no_ctx_str,
}

ecs_system_default :: proc(
	world: ^World,
	procedure: System_Proc,
	ctx: rawptr,
	terms: ..QueryTerm,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	ecs_system_pipeline(
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

ecs_system_pipeline :: proc(
	world: ^World,
	procedure: System_Proc,
	pipeline: EntityId,
	ctx: rawptr,
	terms: ..QueryTerm,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	ensure(ecs_is_valid(world, pipeline))
	system := ecs_new(world)

	query: ^Query

	if len(terms) > 0 {
		query = query_build(world, ..terms, cascade = cascade, allocator = world.allocator)
	}

	ecs_set(world, system, &System{query, procedure, before_update_proc, after_update_proc, ctx})
	ecs_add(world, system, pipeline)
}

ecs_system_default_str :: proc(
	world: ^World,
	procedure: System_Proc,
	ctx: rawptr,
	query_str: string,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	ecs_system_pipeline_str(
		world,
		procedure,
		Pipeline_Default,
		ctx,
		query_str,
		before_update_proc = before_update_proc,
		after_update_proc = after_update_proc,
	)
}

ecs_system_pipeline_str :: proc(
	world: ^World,
	procedure: System_Proc,
	pipeline: EntityId,
	ctx: rawptr,
	query_str: string,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	ensure(ecs_is_valid(world, pipeline))
	system := ecs_new(world)

	query := query_parse(world, query_str, cascade = cascade, allocator = world.allocator)

	ecs_set(world, system, &System{query, procedure, before_update_proc, after_update_proc, ctx})
	ecs_add(world, system, pipeline)
}

ecs_system_default_no_ctx :: proc(
	world: ^World,
	procedure: System_Proc,
	terms: ..QueryTerm,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	ecs_system_default(
		world,
		procedure,
		nil,
		..terms,
		before_update_proc = before_update_proc,
		after_update_proc = after_update_proc,
		cascade = cascade,
	)
}

ecs_system_pipeline_no_ctx :: proc(
	world: ^World,
	procedure: System_Proc,
	pipeline: EntityId,
	terms: ..QueryTerm,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	ecs_system_pipeline(
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

ecs_system_default_no_ctx_str :: proc(
	world: ^World,
	procedure: System_Proc,
	query_str: string,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	ecs_system_default_str(
		world,
		procedure,
		nil,
		query_str,
		before_update_proc = before_update_proc,
		after_update_proc = after_update_proc,
		cascade = cascade,
	)
}

ecs_system_pipeline_no_ctx_str :: proc(
	world: ^World,
	procedure: System_Proc,
	pipeline: EntityId,
	query_str: string,
	before_update_proc: System_Hook_Proc = nil,
	after_update_proc: System_Hook_Proc = nil,
	cascade := false,
) {
	ecs_system_pipeline_str(
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

ecs_watch :: proc {
	ecs_watch_no_ctx,
	ecs_watch_ctx,
	ecs_watch_no_ctx_str,
	ecs_watch_ctx_str,
	ecs_watch_ctx_query,
}

ecs_watch_no_ctx :: proc(
	world: ^World,
	event: EntityId,
	procedure: Watcher_Proc,
	terms: ..QueryTerm,
) {
	ecs_watch_ctx(world, event, procedure, nil, ..terms)
}

ecs_watch_no_ctx_str :: proc(
	world: ^World,
	event: EntityId,
	procedure: Watcher_Proc,
	query_str: string,
) {
	ecs_watch_ctx_str(world, event, procedure, nil, query_str)
}

ecs_watch_ctx :: proc(
	world: ^World,
	event: EntityId,
	procedure: Watcher_Proc,
	ctx: rawptr,
	terms: ..QueryTerm,
) {
	query := query_build(world, ..terms, allocator = world.allocator)

	ecs_watch_ctx_query(world, event, procedure, ctx, query)
}

ecs_watch_ctx_str :: proc(
	world: ^World,
	event: EntityId,
	procedure: Watcher_Proc,
	ctx: rawptr,
	query_str: string,
) {
	query := query_parse(world, query_str, allocator = world.allocator)

	ecs_watch_ctx_query(world, event, procedure, ctx, query)
}

ecs_watch_ctx_query :: proc(
	world: ^World,
	event: EntityId,
	procedure: Watcher_Proc,
	ctx: rawptr,
	query: ^Query,
) {
	watcher := ecs_new(world)

	ecs_set_pair(world, watcher, &Watcher{query, procedure, ctx}, event)
}

ecs_emit :: proc {
	ecs_emit_no_data,
	ecs_emit_data,
}

ecs_emit_data :: proc(world: ^World, event: EntityId, entity: EntityId, data: rawptr) {
	ensure(ecs_is_valid(world, event))
	ensure(ecs_is_valid(world, entity))

	entry := &world.entities[entity]
	archetype := entry.chunk.archetype

	watcher_pair := ecs_build_pair(world, Watcher, event)
	it := filter_iter(world, query_term(world, watcher_pair), allocator = world.temp_allocator)

	for query_iter_next_match(&it) {
		chunk := it.current_chunk
		watcher_col := query_column(&it, 0)

		for row := 0; row < len(chunk.entities); row += 1 {
			watcher := query_entity_data(watcher_col, row, Watcher)

			if query_matches_archetype(watcher.query, archetype) {
				match := evaluate_archetype(
					world,
					watcher.query.terms,
					archetype,
					world.temp_allocator,
				) or_continue
				it2 := QueryIterator {
					world,
					watcher.query.terms,
					[]QueryMatch{match},
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

ecs_emit_no_data :: proc(world: ^World, event: EntityId, entity: EntityId) {
	ecs_emit_data(world, event, entity, nil)
}

ecs_exists :: proc(world: ^World, entity: EntityId) -> bool {
	return entity in world.entities
}

ecs_is_valid :: proc(world: ^World, entity: EntityId) -> bool {
	return entity > 0 && ecs_exists(world, entity)
}

ecs_build_pair :: proc {
	ecs_build_pair_with_ids,
	ecs_build_pair_1,
	ecs_build_pair_2,
}

ecs_build_pair_with_ids :: proc(first: EntityId, second: EntityId) -> EntityId {
	return (u64(first) << 32) | u64(second)
}

ecs_build_pair_1 :: proc(world: ^World, $T: typeid, second: EntityId) -> EntityId {
	first := ecs_get_type_id(world, T)

	return ecs_build_pair_with_ids(first, second)
}

ecs_build_pair_2 :: proc(world: ^World, first: EntityId, $T: typeid) -> EntityId {
	second := ecs_get_type_id(world, T)

	return ecs_build_pair_with_ids(first, second)
}

ecs_pair_first :: proc(pair: EntityId) -> EntityId {
	return pair >> 32
}

ecs_pair_second :: proc(pair: EntityId) -> EntityId {
	return pair & 0xffffffff
}

ecs_pair_split :: proc(pair: EntityId) -> (first: EntityId, second: EntityId) {
	first = ecs_pair_first(pair)
	second = ecs_pair_second(pair)

	return
}

ecs_pair_contains :: proc(pair: EntityId, entity: EntityId) -> bool {
	ensure(ecs_is_pair(pair))

	first, second := ecs_pair_split(pair)

	return first == entity || second == entity
}

ecs_is_pair :: proc(entity: EntityId) -> bool {
	return (entity & 0xFFFFFFFF00000000) > 0
}

ecs_is_unique_pair :: proc(world: ^World, entity: EntityId) -> bool {
	is_pair := ecs_is_pair(entity)

	if !is_pair {
		return false
	}

	first, _ := ecs_pair_split(entity)

	return ecs_has(world, first, UniquePair)
}

ecs_is_wildcard_pair :: proc(entity: EntityId) -> bool {
	first, second := ecs_pair_split(entity)

	return first == Wildcard || second == Wildcard
}

ecs_is_type :: proc(world: ^World, entity: EntityId) -> bool {
	return ecs_exists(world, entity) && ecs_has(world, entity, TypeTrait)
}

ecs_is_tag :: proc(world: ^World, entity: EntityId) -> bool {
	return !ecs_is_type(world, entity)
}

ecs_get_component_type :: proc {
	ecs_get_component_type_by_id,
	ecs_get_component_type_by_type,
}

ecs_get_component_type_by_type :: proc(world: ^World, $T: typeid) -> ComponentType {
	ensure(T in world.types_to_components)

	return world.types_to_components[T]
}

ecs_get_component_type_by_id :: proc(world: ^World, id: EntityId) -> ComponentType {
	ensure(id in world.ids_to_components)

	return world.ids_to_components[id]
}

ecs_get_type_id :: proc(world: ^World, $T: typeid) -> EntityId {
	type := ecs_get_component_type(world, T)

	ensure(ecs_is_type(world, type.id))

	return type.id
}

ecs_get_component_size :: proc(world: ^World, component_id: EntityId) -> int {
	if ecs_is_pair(component_id) {
		return ecs_get_pair_size(world, component_id)
	} else {
		ensure(ecs_is_valid(world, component_id))
		component_type, exists := world.ids_to_components[component_id]

		return exists ? component_type.size : 0
	}
}

ecs_get_pair_type :: proc(world: ^World, pair: EntityId) -> EntityId {
	ensure(ecs_is_pair(pair))

	first, second := ecs_pair_split(pair)
	first_is_type := ecs_is_type(world, first)
	second_is_type := !first_is_type && ecs_is_type(world, second)

	if first_is_type {
		return first
	}

	if second_is_type {
		return second
	}

	return 0
}

ecs_get_pair_size :: proc(world: ^World, pair: EntityId) -> int {
	ensure(ecs_is_pair(pair))

	component_id := ecs_get_pair_type(world, pair)

	return component_id > 0 ? ecs_get_component_size(world, component_id) : 0
}

ecs_add :: proc(world: ^World, entity: EntityId, add_entity: EntityId) -> bool {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(ecs_is_valid(world, entity))

	is_pair := ecs_is_pair(add_entity)

	ensure(ecs_is_valid(world, add_entity) || is_pair)

	entity_entry := &world.entities[entity]
	src_archetype := entity_entry.chunk.archetype

	if archetype_has(src_archetype, add_entity) {
		return false
	}

	src_node := src_archetype.node
	dest_node: ^ArchetypeNode

	if is_pair && ecs_is_unique_pair(world, add_entity) {
		first, _ := ecs_pair_split(add_entity)
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
		entity_str := ecs_entity_to_str(world, entity)
		defer delete(entity_str)
		add_entity_str := ecs_entity_to_str(world, add_entity)
		defer delete(add_entity_str)

		ecs_debug_log("Added %s to %s", add_entity_str, entity_str)
	}

	dest_chunk, dest_row := archetype_add_entity(world, &dest_node.archetype, entity)

	move_entity(world, entity_entry, dest_chunk, src_row, dest_row)

	return true
}

ecs_add_pair :: proc(world: ^World, entity: EntityId, first: EntityId, second: EntityId) -> bool {
	ensure(ecs_is_valid(world, entity))

	pair := ecs_build_pair(first, second)

	return ecs_add(world, entity, pair)
}

ecs_remove_pair :: proc {
	ecs_remove_pair_id,
	ecs_remove_pair_1,
	ecs_remove_pair_2,
}

ecs_remove_pair_id :: proc(
	world: ^World,
	entity: EntityId,
	first: EntityId,
	second: EntityId,
) -> bool {
	ensure(ecs_is_valid(world, entity))

	pair := ecs_build_pair(first, second)

	return ecs_remove(world, entity, pair)
}

ecs_remove_pair_1 :: proc(world: ^World, entity: EntityId, $T: typeid, second: EntityId) -> bool {
	ensure(ecs_is_valid(world, entity))

	pair := ecs_build_pair(world, T, second)

	return ecs_remove(world, entity, pair)
}

ecs_remove_pair_2 :: proc(world: ^World, entity: EntityId, first: EntityId, $T: typeid) -> bool {
	ensure(ecs_is_valid(world, entity))

	pair := ecs_build_pair(world, first, T)

	return ecs_remove(world, entity, pair)
}

ecs_set :: proc {
	ecs_set_with_type,
	ecs_set_with_id,
}

ecs_set_with_type :: proc(world: ^World, entity: EntityId, data: ^$T) {
	component_id := ecs_get_type_id(world, T)
	ensure(ecs_is_type(world, component_id))
	ecs_set_with_id(world, entity, component_id, data)
}

ecs_set_with_id :: proc(world: ^World, entity: EntityId, component_id: EntityId, data: rawptr) {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(ecs_is_pair(component_id) || ecs_is_type(world, component_id))

	ecs_add(world, entity, component_id)

	entity_entry := &world.entities[entity]
	chunk := entity_entry.chunk
	assert(chunk.entities[entity_entry.row] == entity)
	col_idx := chunk.archetype.component_column_map[component_id]

	archetype_chunk_set_data(chunk, col_idx, entity_entry.row, data)
}

ecs_set_pair :: proc {
	ecs_set_pair_with_id,
	ecs_set_pair_1,
	ecs_set_pair_2,
}

ecs_set_pair_with_id :: proc(
	world: ^World,
	entity: EntityId,
	first: EntityId,
	second: EntityId,
	data: ^$T,
) {
	ecs_set_with_id(world, entity, ecs_build_pair(first, second), data)
}

ecs_set_pair_1 :: proc(world: ^World, entity: EntityId, data: ^$T, second: EntityId) {
	ecs_set_pair_with_id(world, entity, ecs_get_type_id(world, T), second, data)
}

ecs_set_pair_2 :: proc(world: ^World, entity: EntityId, first: EntityId, data: ^$T) {
	ecs_set_pair_with_id(world, entity, first, ecs_get_type_id(world, T), data)
}

ecs_remove :: proc {
	ecs_remove_id,
	ecs_remove_type,
}

ecs_remove_id :: proc(world: ^World, entity: EntityId, rm_entity: EntityId) -> bool {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(ecs_is_valid(world, entity))
	ensure(ecs_is_valid(world, rm_entity) || ecs_is_pair(rm_entity))

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

ecs_remove_type :: proc(world: ^World, entity: EntityId, rm_component: typeid) -> bool {
	component_type, exists := world.types_to_components[rm_component]
	ensure(exists)

	return ecs_remove_id(world, entity, component_type.id)
}

ecs_has :: proc {
	ecs_has_id,
	ecs_has_type,
}

ecs_has_id :: proc(world: ^World, entity: EntityId, other: EntityId) -> bool {
	ensure(ecs_is_valid(world, entity))
	ensure(ecs_is_valid(world, other) || ecs_is_pair(other))

	entity_entry := &world.entities[entity]

	return archetype_has(entity_entry.chunk.archetype, other)
}

ecs_has_type :: proc(world: ^World, entity: EntityId, $T: typeid) -> bool {
	component_id := ecs_get_type_id(world, T)
	ensure(ecs_is_type(world, component_id))

	return ecs_has_id(world, entity, component_id)
}

ecs_has_pair :: proc {
	ecs_has_pair_id,
	ecs_has_pair_type,
}

ecs_has_pair_id :: proc(
	world: ^World,
	entity: EntityId,
	first: EntityId,
	second: EntityId,
) -> bool {
	ensure(ecs_is_valid(world, entity))

	return ecs_has(world, entity, ecs_build_pair(first, second))
}

ecs_has_pair_type :: proc(world: ^World, entity: EntityId, first: EntityId, $T: typeid) {
	return ecs_has_pair(world, entity, first, ecs_get_type_id(world, T))
}

ecs_get :: proc(world: ^World, entity: EntityId, $T: typeid) -> T {
	ensure(ecs_is_valid(world, entity))

	component_id := ecs_get_component_type(world, T).id

	ensure(ecs_is_pair(component_id) || ecs_is_valid(world, component_id))
	ensure(ecs_has(world, entity, component_id))

	entity_entry := &world.entities[entity]
	chunk := entity_entry.chunk
	row := entity_entry.row
	assert(chunk.entities[entity_entry.row] == entity)
	col_idx := chunk.archetype.component_column_map[component_id]
	ptr := (^T)(archetype_chunk_get_data(chunk, col_idx, row))

	return ptr^
}

ecs_get_mut :: proc(world: ^World, entity: EntityId, $T: typeid) -> ^T {
	component_id := ecs_get_component_type(world, T).id

	return (^T)(ecs_get_mut_with_id(world, entity, component_id))
}

ecs_get_mut_with_id :: proc(world: ^World, entity: EntityId, component_id: EntityId) -> rawptr {
	if world.frozen {
		panic("Attempted to retrieve mutable data from a frozen world")
	}

	ensure(ecs_is_valid(world, entity))
	ensure(ecs_is_pair(component_id) || ecs_is_valid(world, component_id))
	ensure(ecs_has(world, entity, component_id))

	entity_entry := &world.entities[entity]
	chunk := entity_entry.chunk
	row := entity_entry.row
	assert(chunk.entities[entity_entry.row] == entity)
	col_idx := chunk.archetype.component_column_map[component_id]

	return archetype_chunk_get_data(chunk, col_idx, row)
}

ecs_get_pair :: proc {
	ecs_get_pair_1,
	ecs_get_pair_2,
}
ecs_get_pair_mut :: proc {
	ecs_get_pair_mut_1,
	ecs_get_pair_mut_2,
}

ecs_get_pair_1 :: proc(world: ^World, entity: EntityId, $T: typeid, second: EntityId) -> T {
	return ecs_get_pair_mut_1(world, entity, T, second)^
}

ecs_get_pair_2 :: proc(world: ^World, entity: EntityId, first: EntityId, $T: typeid) -> T {
	return ecs_get_pair_mut_1(world, entity, first, T)^
}

ecs_get_pair_mut_1 :: proc(world: ^World, entity: EntityId, $T: typeid, second: EntityId) -> ^T {
	pair_id := ecs_build_pair(ecs_get_component_type(world, T).id, second)

	return (^T)(ecs_get_mut_with_id(world, entity, pair_id))
}

ecs_get_pair_mut_2 :: proc(world: ^World, entity: EntityId, first: EntityId, second: $T) -> ^T {
	pair_id := ecs_build_pair(first, ecs_get_component_type(world, T).id)

	return (^T)(ecs_get_mut_with_id(world, entity, pair_id))
}

ecs_get_entity_pair :: proc(world: ^World, entity: EntityId, first: EntityId) -> EntityId {
	ensure(ecs_is_valid(world, entity))
	ensure(ecs_is_valid(world, first))

	entity_entry := &world.entities[entity]

	return archetype_get_pair(entity_entry.chunk.archetype, first)
}

ecs_get_entity_pairs :: proc {
	ecs_get_entity_pairs_id,
	ecs_get_entity_pairs_type,
}

ecs_get_entity_pairs_id :: proc(world: ^World, entity: EntityId, first: EntityId) -> []EntityId {
	ensure(ecs_is_valid(world, entity))
	ensure(ecs_is_valid(world, first))

	entity_entry := &world.entities[entity]

	return archetype_get_pairs(entity_entry.chunk.archetype, first)
}

ecs_get_entity_pairs_type :: proc(world: ^World, entity: EntityId, $T: typeid) -> []EntityId {
	return ecs_get_entity_pairs_id(world, entity, ecs_get_type_id(world, T))
}

ecs_get_entity_id :: proc(entity: EntityId) -> EntityId {
	return EntityId(u32(entity) & 0x00FFFFFF)
}

ecs_get_entity_flags :: proc(entity: EntityId) -> u8 {
	return u8(u32(entity) >> 24)
}

ecs_get_generation :: proc(entity: EntityId) -> u16 {
	return u16(entity >> 32)
}

ecs_build_entity_id :: proc(id: EntityId, gen: u16, flags: u8 = 0) -> EntityId {
	ensure(id <= EntityId_Raw_Max)
	id_with_flags := u32(id) | (u32(flags) << 24)
	return u64(id_with_flags) | (u64(gen) << 32)
}

ecs_update :: proc(world: ^World, dt: f64, pipeline := Pipeline_Default) {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(len(world.pipelines) > 0)

	pipeline := world.pipelines[pipeline] // default pipeline

	it := query_iter(pipeline.query)

	for query_iter_next_match(&it) {
		chunk := it.current_chunk
		col := query_column(&it, 0)

		for row := 0; row < len(chunk.entities); row += 1 {
			system := query_entity_data(col, row, System)

			ecs_update_system(world, &system, dt)
		}
	}

	free_all(world.temp_allocator)

	world.info.entity_count = len(world.entities)
	world.info.archetype_count = len(world.archetypes.nodes)
}

ecs_update_system :: proc(world: ^World, system_data: ^System, dt: f64) {
	if system_data.before_update_proc != nil {
		system_data.before_update_proc(world, dt, system_data.ctx)
	}

	if system_data.query == nil {
		system_data.update_proc(world, nil, dt, system_data.ctx)
	} else {
		it := query_iter(system_data.query)

		for query_iter_next_match(&it) {
			system_data.update_proc(world, &it, dt, system_data.ctx)
		}
	}

	if system_data.after_update_proc != nil {
		system_data.after_update_proc(world, dt, system_data.ctx)
	}
}

ecs_set_parent :: proc(world: ^World, entity: EntityId, parent: EntityId) {
	ensure(ecs_is_valid(world, entity))
	ensure(ecs_is_valid(world, parent))

	depth := ecs_get_entity_depth(world, parent)

	ecs_set_pair(world, entity, ChildOf_Id, parent, &ChildOf{depth + 1})
}

ecs_get_parent :: proc(world: ^World, entity: EntityId) -> EntityId {
	ensure(ecs_is_valid(world, entity))

	entity_entry := &world.entities[entity]
	pair := archetype_get_pair(entity_entry.chunk.archetype, ChildOf_Id)
	_, parent := ecs_pair_split(pair)

	return parent
}

ecs_get_children :: proc(
	world: ^World,
	entity: EntityId,
	allocator := context.allocator,
) -> []EntityId {
	childof_pair := ecs_build_pair(ChildOf_Id, entity)
	it := filter_iter(world, query_term(world, childof_pair), allocator = allocator)

	children := make([dynamic]EntityId, allocator = allocator)

	for query_iter_next_match(&it) {
		chunk := it.current_chunk

		for row := 0; row < len(chunk.entities); row += 1 {
			append(&children, chunk.entities[row])
		}
	}

	return children[:]
}

ecs_get_entity_depth :: proc(world: ^World, entity: EntityId) -> int {
	entry := &world.entities[entity]

	return entry.chunk.archetype.depth
}

ecs_get_name :: proc(world: ^World, entity: EntityId) -> string {
	ensure(ecs_is_valid(world, entity))

	return world.entities[entity].name
}

ecs_find :: proc(world: ^World, name: string) -> (entity: EntityId, exists: bool) {
	entity, exists = world.names_index[name]
	ensure(!exists || ecs_is_valid(world, entity))

	return
}

ecs_set_id_range :: proc(world: ^World, r_min: EntityId, r_max: EntityId) {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(r_min > ReservedIDs && r_max <= u64(max(u32)))

	world.config.id_range = [2]EntityId{r_min, r_max}
	world.next_entity_id = world.config.id_range[0]
}

ecs_set_default_delete_strategy :: proc(world: ^World, strategy: EntityId) {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(strategy == DeleteStrategy_Delete || strategy == DeleteStrategy_Remove)

	world.config.default_delete_strategy = strategy
}

ecs_set_context :: proc(world: ^World, ctx: rawptr) {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	world.ctx = ctx
}

ecs_set_deletion_strategy :: proc(world: ^World, entity: EntityId, strategy: EntityId) {
	if world.frozen {
		panic("Attempted to modify a frozen world")
	}

	ensure(strategy == DeleteStrategy_Remove || strategy == DeleteStrategy_Delete)

	if get_deletion_strategy(world, entity) == strategy {
		return
	}

	ecs_add(world, entity, ecs_build_pair(OnDelete, strategy))
}

ecs_prefab :: proc(world: ^World, name := "") -> EntityId {
	prefab := ecs_new(world, name)

	ecs_add(world, prefab, Prefab)
	return prefab
}

ecs_is_prefab :: proc(world: ^World, entity: EntityId) -> bool {
	return ecs_has(world, entity, Prefab)
}

ecs_new_instance_of :: proc(world: ^World, prefab: EntityId, name := "") -> EntityId {
	ensure(ecs_is_prefab(world, prefab))

	entity := ecs_new(world, name)

	prefab_entry := &world.entities[prefab]
	entity_entry := &world.entities[entity]
	src_chunk := prefab_entry.chunk
	src_row := prefab_entry.row
	dest_chunk, dest_row := archetype_add_entity(world, src_chunk.archetype, entity)

	entity_entry.chunk = dest_chunk
	entity_entry.row = dest_row

	archetype_chunk_copy_row(src_chunk, dest_chunk, src_row, dest_row)
	ecs_remove(world, entity, Prefab)

	prefab_children := ecs_get_children(world, prefab, allocator = world.temp_allocator)

	for prefab_child in prefab_children {
		child := ecs_new_instance_of(world, prefab_child)

		ecs_set_parent(world, child, entity)
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
	entity_entry: ^EntityEntry,
	dest_chunk: ^Archetype_Chunk,
	src_row: int,
	dest_row: int,
) {
	src_chunk := entity_entry.chunk
	src_archetype := src_chunk.archetype

	when ECS_DEBUG {
		entity_str := ecs_entity_to_str(world, entity_entry.id)
		defer delete(entity_str)
		src_arch_str := archetype_to_str(world, src_archetype)
		defer delete(src_arch_str)
		dest_arch_str := dest_chunk != nil ? archetype_to_str(world, dest_chunk.archetype) : "NULL"
		ecs_debug_log("Move %s from %s to %s", entity_str, src_arch_str, dest_arch_str)
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
	entity_entry: ^EntityEntry,
	dest_archetype: ^Archetype,
	src_row: int,
) {
	dest_chunk, dest_row := archetype_add_entity(world, dest_archetype, entity_entry.id)

	move_entity_to_existing_row(world, entity_entry, dest_chunk, src_row, dest_row)
}

@(private)
index_archetype :: proc(world: ^World, entity: EntityId, archetype: ^Archetype) {
	if entity not_in world.archetype_index {
		world.archetype_index[entity] = make(ArchetypeMap, world.allocator)
	}

	archetype_map := &world.archetype_index[entity]
	hash := archetype.component_set.hash

	archetype_map[hash] = archetype
}

@(private)
on_archetype_created :: proc(world: ^World, archetype: ^Archetype) {
	for component_id, _ in archetype.component_set.components {
		index_archetype(world, component_id, archetype)

		if ecs_is_pair(component_id) {
			ensure(!ecs_is_wildcard_pair(component_id))

			first, second := ecs_pair_split(component_id)

			index_archetype(world, ecs_build_pair(first, Wildcard), archetype)
			index_archetype(world, ecs_build_pair(Wildcard, second), archetype)
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
	ensure(!ecs_is_pair(deleted_entity))

	when ECS_DEBUG {
		arch_str := archetype_to_str(world, archetype)
		defer delete(arch_str)

		ecs_debug_log("%s destroyed", arch_str)
	}

	strategy := get_deletion_strategy(world, deleted_entity)
	entities := make([]EntityId, archetype.chunk_capacity, world.temp_allocator)

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
		if ecs_is_pair(component) {
			first, second := ecs_pair_split(component)
			pair1 := ecs_build_pair(first, Wildcard)
			pair2 := ecs_build_pair(Wildcard, second)

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
	ensure(ecs_has(world, entity, deleted_entity))

	if strategy == DeleteStrategy_Remove {
		ecs_remove(world, entity, deleted_entity)
	} else if strategy == DeleteStrategy_Delete {
		ecs_delete(world, entity, by_user = false)
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
		new_set := component_set_remove_relationship(set, deleted_entity, world.allocator)
		target_node, exists := archetype_graph_get_or_create(world, &world.archetypes, &new_set)

		if exists {
			component_set_deinit(&new_set)
		}

		move_entity(world, entry, &target_node.archetype, entry.row)
	} else if strategy == DeleteStrategy_Delete {
		ecs_delete(world, entity, by_user = false)
	} else {
		unreachable()
	}
}

@(private)
get_deletion_strategy :: proc(world: ^World, entity: EntityId) -> EntityId {
	if ecs_has(world, entity, ecs_build_pair(OnDelete, DeleteStrategy_Delete)) {
		return DeleteStrategy_Delete
	}

	if ecs_has(world, entity, ecs_build_pair(OnDelete, DeleteStrategy_Remove)) {
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
			ecs_is_pair(index_entity) ? ecs_pair_to_str(world, index_entity) : ecs_entity_to_str(world, index_entity)
		defer delete(entity_str)
		ecs_debug_log("Cleaning up archetypes for entity %s", entity_str)
	}

	if index_entity not_in world.archetype_index {
		when ECS_DEBUG {
			ecs_debug_log("No archetypes to cleanup for entity %s", entity_str)
		}

		return
	}

	ensure(index_entity in world.archetype_index)
	archetype_map := world.archetype_index[index_entity]

	for hash, _ in archetype_map {
		archetype_graph_cleanup(world, &world.archetypes, hash, deleted_entity, relationship)
	}

	delete(archetype_map)
	delete_key(&world.archetype_index, index_entity)
}
