package nbecs

import "core:fmt"
import "core:log"
import "core:strconv"
import "core:strings"

ecs_debug_log :: proc(msg: string, args: ..any, loc := #caller_location) {
	fmt_msg := fmt.aprintf(msg, ..args)
	defer delete(fmt_msg)

	log.debugf("ECS: %s", fmt_msg, location = loc)
}

ecs_entity_to_str :: proc(world: ^World, entity: EntityId) -> string {
	if ecs_is_pair(entity) {
		return ecs_pair_to_str(world, entity)
	} else {
		ensure(ecs_is_valid(world, entity))

		entry := world.entities[entity]
		return fmt.aprintf("Entity(ID = %d, Name = %s)", entry.id, entry.name)
	}
}

ecs_pair_to_str :: proc(world: ^World, entity: EntityId) -> string {
	ensure(ecs_is_pair(entity))

	first, second := ecs_pair_split(entity)
	first_entry, first_exists := world.entities[first]
	second_entry, second_exists := world.entities[second]
	first_name := first_entry.name
	second_name := second_entry.name

	ensure(first_exists)

	if first_name == "" {
		buf: [16]byte
		first_name = strconv.write_uint(buf[:], first_entry.id, 10)
	}

	if second_exists {
		if second_name == "" {
			buf: [16]byte
			second_name = strconv.write_uint(buf[:], second_entry.id, 10)
		}
	} else {
		buf: [16]byte
		second_name = strconv.write_uint(buf[:], second, 10)
	}

	return fmt.aprintf("(%s, %s)", first_name, second_name)
}

archetype_graph_to_str :: proc(world: ^World) -> string {
	sb := strings.Builder{}

	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)

	strings.write_string(&sb, "ArchetypeGraph:\n")

	for _, node in world.archetypes.nodes {
		arch_str := archetype_to_str(world, &node.archetype, chunks = true)
		defer delete(arch_str)

		strings.write_string(&sb, arch_str)
		strings.write_string(&sb, "\n")
	}

	str := strings.to_string(sb)

	return strings.clone(str)
}

archetype_to_str :: proc(world: ^World, archetype: ^Archetype, chunks := false) -> string {
	sb := strings.Builder{}

	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)

	if archetype.is_root {
		strings.write_string(&sb, "Archetype (ROOT)")
	} else {
		strings.write_string(&sb, "Archetype ")
		set_str := component_set_to_str(world, &archetype.component_set)
		defer delete(set_str)
		strings.write_string(&sb, set_str)
	}

	strings.write_string(&sb, "\n")

	if chunks && !archetype.is_root {
		for &chunk in archetype.chunks {
			chunk_str := archetype_chunk_to_str(world, chunk)
			defer delete(chunk_str)

			strings.write_string(&sb, chunk_str)
		}
	}

	str := strings.to_string(sb)

	return strings.clone(str)
}

archetype_chunk_to_str :: proc(world: ^World, chunk: ^Archetype_Chunk) -> string {
	sb := strings.Builder{}

	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)

	for entity in chunk.entities {
		strings.write_string(&sb, "\t- ")
		entity_str := ecs_entity_to_str(world, entity)
		defer delete(entity_str)
		strings.write_string(&sb, entity_str)
		strings.write_string(&sb, "\n")
	}

	str := strings.to_string(sb)

	return strings.clone(str)
}

component_set_to_str :: proc(world: ^World, set: ^Component_Set) -> string {
	sb := strings.Builder{}

	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)

	component_ids := set_to_arr(set)
	defer delete(component_ids)

	strings.write_string(&sb, "[")

	for component_id, idx in component_ids {
		if ecs_is_pair(component_id) {
			pair_name := ecs_pair_to_str(world, component_id)
			defer delete(pair_name)

			strings.write_string(&sb, pair_name)
		} else {
			component_name := ecs_get_name(world, component_id)

			if component_name != "" {
				strings.write_string(&sb, component_name)
			} else {
				strings.write_u64(&sb, component_id)
			}
		}

		if idx < len(set.components) - 1 {
			strings.write_string(&sb, ", ")
		}
	}
	strings.write_string(&sb, "]")

	str := strings.to_string(sb)

	return strings.clone(str)
}

query_to_str :: proc(query: ^Query) -> string {
	sb := strings.Builder{}

	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)

	terms := make([]string, len(query.terms))
	defer delete(terms)

	for term, i in query.terms {
		terms[i] = query_term_str(query.world, term)
	}

	terms_str := strings.join(terms, ", ")
	defer delete(terms_str)

	strings.write_string(&sb, "Query[")
	strings.write_string(&sb, terms_str)
	strings.write_string(&sb, "]")

	if query.cascade {
		strings.write_string(&sb, " CASCADE")
	}

	str := strings.to_string(sb)
	return strings.clone(str)
}

query_term_str :: proc(world: ^World, term: Query_Term) -> string {
	sb := strings.Builder{}

	strings.builder_init(&sb)
	defer strings.builder_destroy(&sb)

	if term.is_pair {
		first, second := ecs_pair_split(term.component_id)
		first_name := ecs_is_valid(world, first) ? ecs_get_name(world, first) : ""
		second_name := ecs_is_valid(world, second) ? ecs_get_name(world, second) : ""

		strings.write_string(&sb, "(")

		if first_name == "" {
			strings.write_u64(&sb, first)
		} else {
			strings.write_string(&sb, first_name)
		}

		strings.write_string(&sb, ", ")

		if second_name == "" {
			strings.write_u64(&sb, second)
		} else {
			strings.write_string(&sb, second_name)
		}

		strings.write_string(&sb, ")")
	} else {
		name := ecs_get_name(world, term.component_id)

		if term.not {
			strings.write_string(&sb, "!")
		}

		if term.optional {
			strings.write_string(&sb, "?")
		}

		if name == "" {
			strings.write_u64(&sb, term.component_id)
		} else {
			strings.write_string(&sb, name)
		}
	}

	str := strings.to_string(sb)
	return strings.clone(str)
}
