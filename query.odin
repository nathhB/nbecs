package nbecs

import "base:builtin"
import sa "core:container/small_array"
import "core:log"
import "core:mem"
import "core:slice"

Query_Term :: struct {
	index:            int,
	component_id:     Entity,
	component_size:   int,
	is_pair:          bool,
	is_wildcard_pair: bool,
	is_unique_pair:   bool,
	not:              bool,
	optional:         bool,
	parent:           bool,
	evaluator:        Query_TermEvaluator,
}

Query_Column_Index :: int

Query_Field :: struct {
	exists: bool,
	data:   union {
		Query_Column_Index,
		Entity,
	},
}

Query_Match :: struct {
	archetype: ^Archetype,
	parent:    Entity,
	fields:    sa.Small_Array(Component_Set_Max_Capacity, Query_Field),
}

Query :: struct {
	world:       ^World,
	terms:       []Query_Term,
	match_index: map[u64]int,
	matches:     [dynamic]Query_Match,
	allocator:   mem.Allocator,
	cascade:     bool,
}

Query_Iterator :: struct {
	world:            ^World,
	terms:            []Query_Term,
	matches:          []Query_Match,
	current_match:    ^Query_Match,
	current_chunk:    ^Archetype_Chunk,
	next_chunk_index: int,
	next_match_index: int,
}

Query_Evaluator :: struct {
	world:  ^World,
	terms:  []Query_Term,
	match:  ^Query_Match,
	parent: Entity,
}

Query_TermEvaluator :: #type proc(evaluator: ^Query_Evaluator, term: ^Query_Term) -> bool

query :: proc {
	build_query,
	parse_query,
}

build_query :: proc(
	world: ^World,
	terms: ..Query_Term,
	cascade := false,
	allocator := context.allocator,
) -> ^Query {
	query := builtin.new(Query, allocator)

	query.world = world
	// + 1 so we can add the '!Prefab' term, see below
	query.terms = make([]Query_Term, len(terms) + 1, allocator)
	query.matches = make([dynamic]Query_Match, allocator)
	query.match_index = make(map[u64]int, allocator)
	query.allocator = allocator
	query.cascade = cascade

	for &term, index in terms {
		// ensure(!term.is_wildcard_pair || term.component_id in query.world.archetype_index)
		term.index = index
		query.terms[index] = term
	}

	// make sure prefab entities are not matched in queries
	query.terms[len(terms)] = not_term(world, Prefab)

	evaluate_cached_query(query)
	append(&world.queries, query)

	return query
}

destroy_query :: proc(query: ^Query) {
	delete_slice(query.terms)
	delete_dynamic_array(query.matches)
	delete_map(query.match_index)

	free(query, query.allocator)
}

iter :: proc {
	query_iter,
	filter_iter,
}

query_iter :: proc(query: ^Query) -> Query_Iterator {
	return Query_Iterator{query.world, query.terms, query.matches[:], nil, nil, 0, 0}
}

filter_iter :: proc(
	world: ^World,
	terms: ..Query_Term,
	allocator := context.temp_allocator,
) -> Query_Iterator {
	matches := make([dynamic]Query_Match, allocator)

	for &term, index in terms {
		term.index = index
	}

	evaluate_terms(world, terms, &matches, allocator)

	return Query_Iterator{world, terms, matches[:], nil, nil, 0, 0}
}

archetype_iter :: proc(
	world: ^World,
	archetype: ^Archetype,
	allocator := context.allocator,
) -> Query_Iterator {
	matches := make([]Query_Match, 1, allocator)

	matches[0].archetype = archetype

	it := Query_Iterator{world, nil, matches, nil, nil, 0, 0}
	iter_next_match(&it)
	iter_next_chunk(&it)

	return it
}

iter_next_match :: proc(iterator: ^Query_Iterator) -> bool {
	if iterator.next_match_index >= len(iterator.matches) {
		return false
	}

	iterator.current_match = &iterator.matches[iterator.next_match_index]
	iterator.next_match_index += 1
	iterator.next_chunk_index = 0

	return true
}

iter_next_chunk :: proc(iterator: ^Query_Iterator) -> (chunk: ^Archetype_Chunk, has_more: bool) {
	archetype := iterator.current_match.archetype

	if iterator.next_chunk_index >= len(archetype.chunks) {
		return nil, false
	}

	iterator.current_chunk = archetype.chunks[iterator.next_chunk_index]
	iterator.next_chunk_index += 1

	return iterator.current_chunk, true
}

column :: proc(iterator: ^Query_Iterator, index: int) -> int {
	col, exists := column_maybe(iterator, index)
	ensure(exists)

	return col
}

column_maybe :: proc(iterator: ^Query_Iterator, index: int) -> (col: int, exists: bool) {
	ensure(iterator.current_match != nil)
	ensure(index < sa.len(iterator.current_match.fields))

	fields := sa.slice(&iterator.current_match.fields)
	field := &fields[index]

	if !field.exists {
		return -1, false
	}

	return field.data.(Query_Column_Index), true
}

unique_pair_column :: proc(iterator: ^Query_Iterator, $T: typeid) -> ^Archetype_Column {
	ensure(iterator.current_match != nil)

	archetype := iterator.current_match.archetype
	pair := archetype_get_pair(archetype, get_type_id(iterator.world, T))
	ensure(pair > 0)
	ensure(pair in archetype.component_column_map)
	col_idx := archetype.component_column_map[pair]

	return &iterator.current_chunk.columns[col_idx]
}

unique_pair_entity :: proc(iterator: ^Query_Iterator, index: int) -> Entity {
	ensure(iterator.current_match != nil)
	ensure(iterator.terms[index].is_unique_pair)

	fields := sa.slice(&iterator.current_match.fields)

	return fields[index].data.(Entity)
}

query_get_parent :: proc(it: ^Query_Iterator) -> Entity {
	return it.current_match.parent
}

term :: proc {
	term_component_id,
	term_type,
	term_pair,
	term_pair_1,
	term_pair_2,
	term_name,
}

term_component_id :: proc(world: ^World, component_id: Entity, optional := false) -> Query_Term {
	term := Query_Term{}

	term.component_id = component_id
	term.component_size = get_component_size(world, component_id)
	term.is_pair = is_pair(term.component_id)
	term.is_wildcard_pair = is_wildcard_pair(term.component_id)
	term.evaluator = term_component_eval
	term.optional = optional

	return term
}

term_type :: proc(world: ^World, $T: typeid, optional := false) -> Query_Term {
	return term_component_id(world, get_type_id(world, T), optional)
}

term_name :: proc(world: ^World, name: string, optional := false) -> Query_Term {
	return term_component_id(world, find(world, name), optional)
}

term_pair :: proc(world: ^World, first: Entity, second: Entity, optional := false) -> Query_Term {
	pair := build_pair(first, second)
	term := term_component_id(world, pair, optional)

	if is_unique_pair(world, pair) && second == Wildcard {
		term.is_unique_pair = true
	}

	return term
}

term_pair_1 :: proc(world: ^World, $T: typeid, second: Entity, optional := false) -> Query_Term {
	return term_pair(world, get_type_id(world, T), second, optional)
}

term_pair_2 :: proc(world: ^World, first: Entity, $T: typeid, optional := false) -> Query_Term {
	return term_pair(world, first, get_type_id(world, T), optional)
}

not_term :: proc {
	term_not_component_id,
	term_not_type,
	term_not_pair,
	term_not_pair_1,
	term_not_pair_2,
}

term_not_component_id :: proc(world: ^World, component_id: Entity) -> Query_Term {
	term := term_component_id(world, component_id)

	term.not = true
	return term
}

term_not_type :: proc(world: ^World, $T: typeid) -> Query_Term {
	term := term_type(world, T)

	term.not = true
	return term
}

term_not_pair :: proc(world: ^World, first: Entity, second: Entity) -> Query_Term {
	term := term_pair(world, first, second)

	term.not = true
	return term
}

term_not_pair_1 :: proc(world: ^World, $T: typeid, second: Entity) -> Query_Term {
	term := term_pair_1(world, T, second)

	term.not = true
	return term
}

term_not_pair_2 :: proc(world: ^World, first: Entity, $T: typeid) -> Query_Term {
	term := term_pair_2(world, first, T)

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

@(private)
query_on_archertype_created :: proc(query: ^Query, archetype: ^Archetype) {
	ensure(!archetype.is_root)

	match, ok := evaluate_archetype(query.world, query.terms, archetype)

	if ok {
		when ECS_DEBUG {
			arch_str := archetype_to_str(query.world, match.archetype)
			defer delete(arch_str)
			query_str := query_to_str(query)
			defer delete(query_str)

			debug_log("archertype %s added to query matches: %s", arch_str, query_str)
		}

		add_cached_match(query, &match)
	}
}

@(private)
query_on_archertype_deleted :: proc(query: ^Query, archetype: ^Archetype) {
	match, ok := evaluate_archetype(query.world, query.terms, archetype)

	if ok && archetype.component_set.hash in query.match_index {
		when ECS_DEBUG {
			arch_str := archetype_to_str(query.world, match.archetype)
			defer delete(arch_str)
			query_str := query_to_str(query)
			defer delete(query_str)

			debug_log("archertype %s was removed from query matches: %s", arch_str, query_str)
		}

		delete_match(query, match.archetype.component_set.hash)
	}
}

@(private = "file")
evaluate_terms :: proc(
	world: ^World,
	terms: []Query_Term,
	matches: ^[dynamic]Query_Match,
	allocator: mem.Allocator,
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

@(private)
evaluate_archetype :: proc(
	world: ^World,
	terms: []Query_Term,
	archetype: ^Archetype,
	allocator := context.allocator,
) -> (
	match: Query_Match,
	ok: bool,
) {
	evaluator := Query_Evaluator{world, terms, &match, 0}

	child_of_pair := archetype_get_pair(archetype, ChildOf_Id)
	_, parent := pair_split(child_of_pair)

	match.archetype = archetype
	match.parent = parent

	sa.resize(&match.fields, Component_Set_Max_Capacity)

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
term_component_eval :: proc(evaluator: ^Query_Evaluator, term: ^Query_Term) -> bool {
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
		col_idx := has ? match.archetype.component_column_map[term.component_id] : -1

		field := Query_Field{has, col_idx}
		sa.set(&match.fields, term.index, field)
	}

	return true
}

@(private = "file")
evaluate_wildcard_pair :: proc(world: ^World, match: ^Query_Match, term: ^Query_Term) -> bool {
	if match.archetype.component_set.hash not_in world.archetype_index[term.component_id] {
		return false
	}

	if term.is_unique_pair {
		first, second := pair_split(term.component_id)

		ensure(second == Wildcard)
		unique_pair := archetype_get_pair(match.archetype, first)
		_, entity := pair_split(unique_pair)

		field := Query_Field{true, entity}
		sa.set(&match.fields, term.index, field)
	}

	return true
}

@(private = "file")
term_parent_eval :: proc(evaluator: ^Query_Evaluator, term: ^Query_Term) -> bool {
	return true
}

@(private = "file")
add_cached_match :: proc(query: ^Query, match: ^Query_Match) {
	ensure(match.archetype.component_set.hash not_in query.match_index)
	append(&query.matches, match^)

	index := -1

	if query.cascade {
		slice.sort_by(query.matches[:], match_depth_sort)
		clear(&query.match_index)

		for m, i in query.matches {
			hash := m.archetype.component_set.hash
			query.match_index[hash] = i

			if hash == match.archetype.component_set.hash {
				index = i
			}
		}
	} else {
		index = len(query.matches) - 1
	}

	ensure(index >= 0)
	query.match_index[match.archetype.component_set.hash] = index
}

@(private = "file")
get_match_location :: proc(query: ^Query, match: ^Query_Match) -> int {
	for &m, index in query.matches {
		if m.archetype.component_set.hash == match.archetype.component_set.hash {
			return index
		}
	}

	return -1
}

@(private = "file")
match_depth_sort :: proc(m1, m2: Query_Match) -> bool {
	return m1.archetype.depth < m2.archetype.depth
}

@(private = "file")
delete_match :: proc(query: ^Query, hash: u64) {
	match_index, exists := query.match_index[hash]
	ensure(exists)

	if query.cascade {
		ordered_remove(&query.matches, match_index)
		clear(&query.match_index)

		for match, i in query.matches {
			query.match_index[match.archetype.component_set.hash] = i
		}
	} else {
		delete_key(&query.match_index, hash)
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

