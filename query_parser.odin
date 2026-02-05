package nbecs

import "core:fmt"
import "core:log"
import "core:mem"
import "core:strings"

QueryString_MaxTokens :: 32

Query_TokenType :: enum {
	Unknown,
	Component,
	Pair,
}

Query_Token :: struct {
	type: Query_TokenType,
	str:  string,
}

query_parse :: proc(
	world: ^World,
	query_str: string,
	cascade := false,
	allocator := context.allocator,
) -> ^Query {
	tokens, err := tokenize_query_string(query_str, allocator)
	defer delete(tokens)
	ensure(err == .None)

	terms := make([dynamic]QueryTerm, allocator)
	defer delete(terms)

	for token in tokens {
		token := token
		not := false
		optional := false
		is_pair := false

		fmt.ensuref(token.type != .Unknown, "Unknown token type")

		if token.type == .Component {
			if strings.starts_with(token.str, "!") {
				not = true
				token.str = string(token.str[1:])
			} else if strings.starts_with(token.str, "?") {
				optional = true
				token.str = string(token.str[1:])
			}
		} else if token.type == .Pair {
			is_pair = true
		}

		term: QueryTerm

		if is_pair {
			term = parse_pair(world, token.str)
		} else {
			component, exists := ecs_find(world, token.str)

			if !exists {
				fmt.panicf("Failed to parse query: %s does not exist", token.str)
			}

			term = query_term(world, component)
			term.not = not
			term.optional = optional
		}

		append(&terms, term)
	}

	return query_build(world, ..terms[:], cascade = cascade, allocator = allocator)
}

tokenize_query_string :: proc(
	query_str: string,
	allocator := context.allocator,
) -> (
	tokens: []Query_Token,
	err: mem.Allocator_Error,
) {
	token_count := 0
	query_len := len(query_str)
	tokens = make([]Query_Token, QueryString_MaxTokens, allocator) or_return

	for i := 0; i < query_len; i += 1 {
		if query_str[i] != ' ' {
			if token_count >= len(tokens) {
				return tokens, mem.Allocator_Error.Out_Of_Memory
			}

			token_len := 0
			token_type := Query_TokenType.Unknown
			token_end_char: u8

			if query_str[i] == '(' {
				token_type = .Pair
				token_end_char = ')'
				i += 1
			} else {
				token_type = .Component
				token_end_char = ' '
			}

			for i + token_len < query_len && query_str[i + token_len] != token_end_char {
				token_len += 1
			}

			tokens[token_count] = Query_Token{token_type, query_str[i:(i + token_len)]}
			token_count += 1
			i += token_len
		}
	}

	return tokens[0:token_count], .None
}

parse_pair :: proc(world: ^World, pair_str: string, allocator := context.allocator) -> QueryTerm {
	parts, err := strings.split(pair_str, ",", allocator)
	ensure(err == .None)
	defer delete(parts)

	fmt.ensuref(len(parts) == 2, "Invalid pair format: %s", pair_str)

	first_name := strings.trim(parts[0], " ")
	second_name := strings.trim(parts[1], " ")
	first, second: EntityId
	exists: bool

	first, exists = ecs_find(world, first_name)
	ensure(exists)
	second, exists = ecs_find(world, second_name)
	ensure(exists)

	return query_term(world, first, second)
}
