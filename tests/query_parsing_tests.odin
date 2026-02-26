package tests

import ecs ".."
import "core:log"
import "core:mem"
import "core:testing"

@(test)
query_parse_tests :: proc(t: ^testing.T) {
	world := ecs.ecs_create()
	defer ecs.ecs_destroy(world)

	foo := ecs.ecs_declare(world, Foo, "Foo")
	bar := ecs.ecs_declare(world, Bar, "Bar")
	plop := ecs.ecs_new(world, "Plop")
	plap := ecs.ecs_new(world, "Plap")
	pair1 := ecs.ecs_build_pair(foo, bar)

	query1 := ecs.query_parse(world, "Foo Bar Plap")
	query2 := ecs.query_parse(world, " Bar Plop Foo  ")
	query3 := ecs.query_parse(world, "Bar Plop !Foo")
	query4 := ecs.query_parse(world, "Plop (Foo, Plap)")
	query5 := ecs.query_parse(world, "?Plop !Foo ?Bar")

	check_terms(t, query1, ecs.term(world, Foo), ecs.term(world, Bar), ecs.term(world, plap))
	check_terms(t, query2, ecs.term(world, Bar), ecs.term(world, plop), ecs.term(world, Foo))

	neg_foo := ecs.term(world, Foo)
	neg_foo.not = true

	check_terms(t, query3, ecs.term(world, Bar), ecs.term(world, plop), neg_foo)
	check_terms(t, query4, ecs.term(world, plop), ecs.term(world, foo, plap))
	check_terms(
		t,
		query5,
		ecs.term(world, plop, optional = true),
		neg_foo,
		ecs.term(world, Bar, optional = true),
	)
}

@(test)
cleanup_query_string_tests :: proc(t: ^testing.T) {
	check_parsed_query_tokens(t, "  Foo  Bar Plop  !Test ", "Foo", "Bar", "Plop", "!Test")
	check_parsed_query_tokens(t, "Foo Bar Plop !Test ", "Foo", "Bar", "Plop", "!Test")
	check_parsed_query_tokens(t, "Foo", "Foo")
	check_parsed_query_tokens(t, "    !Foo     ", "!Foo")
	check_parsed_query_tokens(t, "    ?Foo !Bar     ", "?Foo", "!Bar")
}

check_terms :: proc(
	t: ^testing.T,
	query: ^ecs.Query,
	expected_terms: ..ecs.Query_Term,
	loc := #caller_location,
) {
	expected_term_count := len(expected_terms) + 1 // '!Prefab' is always added to queries

	testing.expect_value(t, len(query.terms), expected_term_count, loc)

	for term, idx in query.terms[0:(expected_term_count - 1)] {
		testing.expect_value(t, term.component_id, expected_terms[idx].component_id, loc)
		testing.expect_value(t, term.not, expected_terms[idx].not, loc)
		testing.expect_value(t, term.optional, expected_terms[idx].optional, loc)
	}
}

check_parsed_query_tokens :: proc(
	t: ^testing.T,
	query_str: string,
	expected_tokens: ..string,
	loc := #caller_location,
) {
	expected_word_count := len(expected_tokens)
	tokens, err := ecs.tokenize_query_string(query_str)
	defer delete(tokens)

	testing.expect_value(t, err, mem.Allocator_Error.None, loc)
	testing.expect_value(t, len(tokens), expected_word_count, loc)

	for token, idx in tokens[0:expected_word_count] {
		testing.expect_value(t, token.str, expected_tokens[idx], loc)
	}
}
