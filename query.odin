package nbecs

import sa "core:container/small_array"
import "core:log"
import "core:mem"
import "core:slice"

QueryTerm :: struct {
	index:            int,
	component_id:     EntityId,
	component_size:   int,
	is_pair:          bool,
	is_wildcard_pair: bool,
	is_unique_pair:   bool,
	not:              bool,
	optional:         bool,
	parent:           bool,
	evaluator:        QueryTermEvaluator,
}

QueryField :: union {
	QueryField_ColumnIndex,
	EntityId,
}

QueryField_ColumnIndex :: struct {
	index:    int,
	optional: bool,
}

QueryMatch :: struct {
	archetype: ^Archetype,
	parent:    EntityId,
	fields:    sa.Small_Array(ComponentSet_MaxCapacity, QueryField),
}

Query :: struct {
	world:       ^World,
	terms:       []QueryTerm,
	match_index: map[u64]int,
	matches:     [dynamic]QueryMatch,
	allocator:   mem.Allocator,
	cascade:     bool,
}

QueryIterator :: struct {
	world:            ^World,
	terms:            []QueryTerm,
	matches:          []QueryMatch,
	current_match:    ^QueryMatch,
	current_chunk:    ^Archetype_Chunk,
	current_row:      int,
	next_chunk_index: int,
	next_match_index: int,
}

QueryEvaluator :: struct {
	world:  ^World,
	terms:  []QueryTerm,
	match:  ^QueryMatch,
	parent: EntityId,
}

QueryTermEvaluator :: #type proc(evaluator: ^QueryEvaluator, term: ^QueryTerm) -> bool

query_build :: proc(
	world: ^World,
	terms: ..QueryTerm,
	cascade := false,
	allocator := context.allocator,
) -> ^Query {
	query := new(Query, allocator)

	query.world = world
	// + 1 so we can add the '!Prefab' term, see below
	query.terms = make([]QueryTerm, len(terms) + 1, allocator)
	query.matches = make([dynamic]QueryMatch, allocator)
	query.match_index = make(map[u64]int, allocator)
	query.allocator = allocator
	query.cascade = cascade

	for &term, index in terms {
		// ensure(!term.is_wildcard_pair || term.component_id in query.world.archetype_index)
		term.index = index
		query.terms[index] = term
	}

	// make sure prefab entities are not matched in queries
	query.terms[len(terms)] = query_not_term(world, Prefab)

	evaluate_cached_query(query)
	append(&world.queries, query)

	return query
}

query_destroy :: proc(query: ^Query) {
	delete(query.terms)
	delete(query.matches)
	delete(query.match_index)

	free(query, query.allocator)
}

query_iter :: proc(query: ^Query) -> QueryIterator {
	return QueryIterator{query.world, query.terms, query.matches[:], nil, nil, 0, 0, 0}
}

filter_iter :: proc(
	world: ^World,
	terms: ..QueryTerm,
	allocator := context.allocator,
) -> QueryIterator {
	matches := make([dynamic]QueryMatch, allocator)

	evaluate_terms(world, terms, &matches, allocator)

	return QueryIterator{world, terms, matches[:], nil, nil, 0, 0, 0}
}

iter_archetype :: proc(
	world: ^World,
	archetype: ^Archetype,
	allocator := context.allocator,
) -> QueryIterator {
	matches := make([]QueryMatch, 1, allocator)

	matches[0].archetype = archetype

	it := QueryIterator{world, nil, matches, nil, nil, 0, 0, 0}
	query_iter_next_match(&it)

	return it
}

query_iter_next_match :: proc(iterator: ^QueryIterator) -> bool {
	if iterator.next_match_index >= len(iterator.matches) {
		return false
	}

	iterator.current_match = &iterator.matches[iterator.next_match_index]
	iterator.next_match_index += 1
	iterator.next_chunk_index = 0
	iterator.current_chunk = nil
	iterator.current_row = 0

	return true
}

query_iter_next_entity :: proc(iterator: ^QueryIterator) -> (entity: EntityId, has_more: bool) {
	ensure(iterator.current_match != nil)

	archetype := iterator.current_match.archetype

	if iterator.current_chunk == nil {
		if iterator.next_chunk_index >= len(archetype.chunks) {
			entity = 0
			has_more = false

			return
		}

		iterator.current_chunk = archetype.chunks[iterator.next_chunk_index]
		iterator.next_chunk_index += 1
	}

	chunk := iterator.current_chunk
	chunk_count := len(chunk.entities)

	if iterator.current_row < chunk_count {
		entity = chunk.entities[iterator.current_row]
		has_more = true

		iterator.current_row += 1

		return
	}

	// end of chunk reached
	iterator.current_chunk = nil

	return query_iter_next_entity(iterator)
}

query_column_index :: proc(iterator: ^QueryIterator, index: int) -> int {
	ensure(iterator.current_match != nil)

	fields := sa.slice(&iterator.current_match.fields)
	field := &fields[index]

	return (field.(QueryField_ColumnIndex)).index
}

query_unique_pair_entity :: proc(iterator: ^QueryIterator, index: int) -> EntityId {
	ensure(iterator.current_match != nil)
	ensure(iterator.terms[index].is_unique_pair)

	fields := sa.slice(&iterator.current_match.fields)

	return fields[index].(EntityId)
}

query_entity_data :: proc(iterator: ^QueryIterator, col_idx: int, $T: typeid) -> T {
	return query_entity_data_mut(iterator, col_idx, T)^
}

query_entity_data_mut :: proc(iterator: ^QueryIterator, col_idx: int, $T: typeid) -> ^T {
	chunk := iterator.current_chunk
	col := &chunk.columns[col_idx]
	world := iterator.world

	if ecs_is_pair(col.component_id) {
		ensure(ecs_get_pair_type(world, col.component_id) == ecs_get_type_id(iterator.world, T))
	} else {
		ensure(col.component_id == ecs_get_type_id(iterator.world, T))
	}

	return (^T)(archetype_chunk_get_data(chunk, col_idx, iterator.current_row - 1))
}

query_get_parent :: proc(it: ^QueryIterator) -> EntityId {
	return it.current_match.parent
}

query_get_match_count :: proc(query: ^Query) -> int {
	return len(query.match_index)
}

query_on_archertype_created :: proc(query: ^Query, archetype: ^Archetype) {
	match, ok := evaluate_archetype(query.world, query.terms, archetype)

	if ok {
		add_cached_match(query, &match)
	}
}

query_on_archertype_deleted :: proc(query: ^Query, archetype: ^Archetype) {
	match, ok := evaluate_archetype(query.world, query.terms, archetype)

	if ok && archetype.component_set.hash in query.match_index {
		delete_match(query, match.archetype.component_set.hash)
	}
}

query_term :: proc {
	query_term_component_id,
	query_term_type,
	query_term_pair,
	query_term_pair_1,
	query_term_pair_2,
}

query_term_component_id :: proc(
	world: ^World,
	component_id: EntityId,
	optional := false,
) -> QueryTerm {
	term := QueryTerm{}

	term.component_id = component_id
	term.component_size = ecs_get_component_size(world, component_id)
	term.is_pair = ecs_is_pair(term.component_id)
	term.is_wildcard_pair = ecs_is_wildcard_pair(term.component_id)
	term.evaluator = term_component_eval
	term.optional = optional

	return term
}

query_term_type :: proc(world: ^World, $T: typeid, optional := false) -> QueryTerm {
	return query_term_component_id(world, ecs_get_type_id(world, T), optional)
}

query_term_pair :: proc(
	world: ^World,
	first: EntityId,
	second: EntityId,
	optional := false,
) -> QueryTerm {
	pair := ecs_build_pair(first, second)
	term := query_term_component_id(world, pair, optional)

	if ecs_is_unique_pair(world, pair) && second == Wildcard {
		term.is_unique_pair = true
	}

	return term
}

query_term_pair_1 :: proc(
	world: ^World,
	$T: typeid,
	second: EntityId,
	optional := false,
) -> QueryTerm {
	return query_term_pair(world, ecs_get_type_id(world, T), second, optional)
}

query_term_pair_2 :: proc(
	world: ^World,
	first: EntityId,
	$T: typeid,
	optional := false,
) -> QueryTerm {
	return query_term_pair(world, first, ecs_get_type_id(world, T), optional)
}

query_not_term :: proc {
	query_term_not_component_id,
	query_term_not_type,
	query_term_not_pair,
	query_term_not_pair_1,
	query_term_not_pair_2,
}

query_term_not_component_id :: proc(world: ^World, component_id: EntityId) -> QueryTerm {
	term := query_term_component_id(world, component_id)

	term.not = true
	return term
}

query_term_not_type :: proc(world: ^World, $T: typeid) -> QueryTerm {
	term := query_term_type(world, T)

	term.not = true
	return term
}

query_term_not_pair :: proc(world: ^World, first: EntityId, second: EntityId) -> QueryTerm {
	term := query_term_pair(world, first, second)

	term.not = true
	return term
}

query_term_not_pair_1 :: proc(world: ^World, $T: typeid, second: EntityId) -> QueryTerm {
	term := query_term_pair_1(world, T, second)

	term.not = true
	return term
}

query_term_not_pair_2 :: proc(world: ^World, first: EntityId, $T: typeid) -> QueryTerm {
	term := query_term_pair_2(world, first, T)

	term.not = true
	return term
}

query_matches_archetype :: proc(query: ^Query, archetype: ^Archetype) -> bool {
	return archetype.component_set.hash in query.match_index
}

@(private = "file")
evaluate_cached_query :: proc(query: ^Query) {
	ensure(len(query.terms) > 0)

	clear_matches(query)

	for term in query.terms {
		archetype_map := query.world.archetype_index[term.component_id] or_continue

		for hash, archetype in archetype_map {
			if hash in query.match_index {
				continue
			}

			match := evaluate_archetype(query.world, query.terms, archetype) or_continue
			add_cached_match(query, &match)
		}
	}
}

@(private = "file")
evaluate_terms :: proc(
	world: ^World,
	terms: []QueryTerm,
	matches: ^[dynamic]QueryMatch,
	allocator := context.allocator,
) {
	match_map := make(map[u64]bool, allocator)

	for term in terms {
		archetype_map := world.archetype_index[term.component_id] or_continue

		for _, archetype in archetype_map {
			match := evaluate_archetype(world, terms, archetype, allocator) or_continue
			hash := match.archetype.component_set.hash

			if hash not_in match_map {
				append(matches, match)
				match_map[hash] = true
			}
		}
	}
}

evaluate_archetype :: proc(
	world: ^World,
	terms: []QueryTerm,
	archetype: ^Archetype,
	allocator := context.allocator,
) -> (
	match: QueryMatch,
	ok: bool,
) {
	evaluator := QueryEvaluator{world, terms, &match, 0}

	child_of_pair := archetype_get_pair(archetype, ChildOf_Id)
	_, parent := ecs_pair_split(child_of_pair)

	match.archetype = archetype
	match.parent = parent

	sa.resize(&match.fields, ComponentSet_MaxCapacity)

	for i := 0; i < len(terms); i += 1 {
		term := terms[i]
		ok = term.evaluator(&evaluator, &term)

		if !ok {
			return
		}
	}

	ok = true
	return
}

@(private = "file")
term_component_eval :: proc(evaluator: ^QueryEvaluator, term: ^QueryTerm) -> bool {
	match := evaluator.match
	world := evaluator.world

	if term.is_wildcard_pair {
		ensure(!term.optional)
		ensure(!term.not)

		return evaluate_wildcard_pair(world, match, term)
	}

	has := archetype_has(evaluator.match.archetype, term.component_id)

	if !term.optional {
		if term.not {
			has = !has
		}

		if !has {
			return false
		}
	}

	if term.component_size > 0 {
		col_index := has ? match.archetype.component_column_map[term.component_id] : -1

		sa.set(&match.fields, term.index, QueryField_ColumnIndex{col_index, term.optional})
	}

	return true
}

@(private = "file")
evaluate_wildcard_pair :: proc(world: ^World, match: ^QueryMatch, term: ^QueryTerm) -> bool {
	if match.archetype.component_set.hash not_in world.archetype_index[term.component_id] {
		return false
	}

	if term.is_unique_pair {
		first, second := ecs_pair_split(term.component_id)

		ensure(second == Wildcard)
		unique_pair := archetype_get_pair(match.archetype, first)
		_, entity := ecs_pair_split(unique_pair)

		sa.set(&match.fields, term.index, entity)
	}

	return true
}

@(private = "file")
term_parent_eval :: proc(evaluator: ^QueryEvaluator, term: ^QueryTerm) -> bool {
	return true
}

@(private = "file")
add_cached_match :: proc(query: ^Query, match: ^QueryMatch) {
	ensure(match.archetype.component_set.hash not_in query.match_index)
	append(&query.matches, match^)

	index := -1

	if query.cascade {
		slice.sort_by(query.matches[:], match_depth_sort)
		index = get_match_location(query, match)
	} else {
		index = len(query.matches) - 1
	}

	ensure(index >= 0)
	query.match_index[match.archetype.component_set.hash] = index
}

@(private = "file")
get_match_location :: proc(query: ^Query, match: ^QueryMatch) -> int {
	for &m, index in query.matches {
		if m.archetype.component_set.hash == match.archetype.component_set.hash {
			return index
		}
	}

	return -1
}

@(private = "file")
match_depth_sort :: proc(m1, m2: QueryMatch) -> bool {
	return m1.archetype.depth < m2.archetype.depth
}

@(private = "file")
delete_match :: proc(query: ^Query, hash: u64) {
	match_index, exists := query.match_index[hash]
	ensure(exists)
	delete_key(&query.match_index, hash)

	if query.cascade {
		ordered_remove(&query.matches, match_index)
	} else {
		moved_archetype := query.matches[len(query.matches) - 1].archetype
		unordered_remove(&query.matches, match_index)
		query.match_index[moved_archetype.component_set.hash] = match_index
	}
}

@(private = "file")
clear_matches :: proc(query: ^Query) {
	// TODO: deinit matches here?

	clear(&query.matches)
	clear(&query.match_index)
}
