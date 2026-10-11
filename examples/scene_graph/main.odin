package scene_graph

import ecs "../.."
import "core:log"
import m "core:math"
import lin "core:math/linalg"
import rl "vendor:raylib"

Transform :: struct {
	local_pos: Vec2,
	local_rot: f32,
	world_pos: Vec2,
	world_rot: f32,
}

Rect :: distinct Vec2
Circle :: distinct f32

Vec2 :: rl.Vector2
Vec3 :: rl.Vector3
Mat2x2 :: lin.Matrix2x2f32
Mat3x3 :: lin.Matrix3x3f32

main :: proc() {
	context.logger = log.create_console_logger()

	rl.InitWindow(800, 600, "nbecs - Scene Graph")

	world := ecs.create()
	defer ecs.destroy(world)

	ecs.declare(world, Transform, "Transform")
	ecs.declare(world, Rect, "Rect")
	ecs.declare(world, Circle, "Circle")

	ecs.system(world, update_transforms, nil, "Transform", cascade = true)
	ecs.system(world, draw_rects, nil, "Transform Rect")
	ecs.system(world, draw_links, nil, "Transform Rect")

	root := ecs.new(world, "ROOT")
	ecs.set(world, root, &Transform{Vec2{0, 0}, 0, Vec2{0, 0}, 0})

	create_scene(world)

	for !rl.WindowShouldClose() {
		ecs.update(world, f64(rl.GetFrameTime()))

		rl.BeginDrawing()
		{
			rl.ClearBackground(rl.LIGHTGRAY)
		}
		rl.EndDrawing()
	}
}

create_scene :: proc(world: ^ecs.World) {
	r1 := create_rect(world, Vec2{250, 250}, 45, Vec2{25, 25})
	r2 := create_rect(world, Vec2{0, 100}, -90, Vec2{25, 25})
	r3 := create_rect(world, Vec2{0, 100}, 60, Vec2{25, 25})
	r4 := create_rect(world, Vec2{0, 100}, 0, Vec2{25, 25})
	r5 := create_rect(world, Vec2{150, 0}, 0, Vec2{25, 25})
	r6 := create_rect(world, Vec2{350, 50}, 0, Vec2{25, 25})

	ecs.set_parent(world, r2, r1)
	ecs.set_parent(world, r3, r2)
	ecs.set_parent(world, r4, r3)
	ecs.set_parent(world, r5, r1)
}

create_rect :: proc(world: ^ecs.World, pos: Vec2, rot: f32, size: Vec2) -> ecs.Entity {
	entity := ecs.new(world)

	ecs.set(world, entity, &Transform{pos, rot, Vec2{0, 0}, 0})
	ecs.set(world, entity, &Rect{size.x, size.y})

	return entity
}

update_transforms :: proc(
	world: ^ecs.World,
	it: ^ecs.Query_Iterator,
	dt: f64,
	ctx: rawptr,
) -> bool {
	transform_col := ecs.column(it, 0)
	parent := ecs.query_get_parent(it)
	parent_matrix := lin.identity_matrix(Mat3x3)
	parent_rot: f32 = 0

	if parent != 0 {
		parent_transform := ecs.get(world, parent, Transform)

		parent_matrix = build_matrix(parent_transform)
		parent_rot = parent_transform.world_rot
	}

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < chunk.count; row += 1 {
			transform := ecs.get_mut(chunk, transform_col, row, Transform)
			world_pos := mul_v2_with_m3(transform.local_pos, parent_matrix)

			transform.world_pos = Vec2{world_pos.x, world_pos.y}
			transform.world_rot = transform.local_rot + parent_rot
		}
	}

	return true
}

build_matrix :: proc(transform: Transform) -> Mat3x3 {
	world_pos := transform.world_pos
	world_rot := transform.world_rot

	rads := m.to_radians(world_rot)
	rotate := lin.matrix3_from_matrix2_f32(lin.matrix2_rotate_f32(rads))

	to_world := lin.identity_matrix(Mat3x3)
	to_world[0, 2] = world_pos.x
	to_world[1, 2] = world_pos.y

	return to_world * rotate
}

build_local_rotation_matrix :: proc(transform: Transform) -> Mat3x3 {
	world_pos := transform.world_pos
	local_rot := transform.local_rot

	to_origin := lin.identity_matrix(Mat3x3)
	to_origin[0, 2] = -world_pos.x
	to_origin[1, 2] = -world_pos.y

	rads := m.to_radians(local_rot)
	rotate := lin.matrix3_from_matrix2_f32(lin.matrix2_rotate_f32(rads))

	to_world := lin.identity_matrix(Mat3x3)
	to_world[0, 2] = world_pos.x
	to_world[1, 2] = world_pos.y

	return to_world * rotate * to_origin
}

draw_rects :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	transform_col := ecs.column(it, 0)
	rect_col := ecs.column(it, 1)
	parent := ecs.query_get_parent(it)

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < chunk.count; row += 1 {
			transform := ecs.get(chunk, transform_col, row, Transform)
			size := ecs.get(chunk, rect_col, row, Rect)
			world_pos := transform.world_pos
			width := size.x
			heigth := size.y

			topleft_x := world_pos.x - width / 2
			topleft_y := world_pos.y - heigth / 2
			topright_x := world_pos.x + width / 2
			topright_y := world_pos.y - heigth / 2
			bottomright_x := world_pos.x + width / 2
			bottomright_y := world_pos.y + heigth / 2
			bottomleft_x := world_pos.x - width / 2
			bottomleft_y := world_pos.y + heigth / 2
			rotate_mat := build_local_rotation_matrix(transform)
			topleft := mul_v2_with_m3(Vec2{topleft_x, topleft_y}, rotate_mat)
			topright := mul_v2_with_m3(Vec2{topright_x, topright_y}, rotate_mat)
			bottomleft := mul_v2_with_m3(Vec2{bottomleft_x, bottomleft_y}, rotate_mat)
			bottomright := mul_v2_with_m3(Vec2{bottomright_x, bottomright_y}, rotate_mat)
			color := parent == 0 ? rl.RED : rl.GREEN

			rl.DrawLineEx(topleft, topright, 2, color)
			rl.DrawLineEx(topright, bottomright, 2, color)
			rl.DrawLineEx(bottomright, bottomleft, 2, color)
			rl.DrawLineEx(bottomleft, topleft, 2, color)
		}
	}

	return true
}

draw_links :: proc(world: ^ecs.World, it: ^ecs.Query_Iterator, dt: f64, ctx: rawptr) -> bool {
	transform_col := ecs.column(it, 0)
	rect_col := ecs.column(it, 1)

	parent := ecs.query_get_parent(it)

	if parent == 0 {
		return true
	}

	parent_transform := ecs.get(world, parent, Transform)
	parent_size := ecs.get(world, parent, Rect)
	parent_pos := parent_transform.world_pos

	for chunk in ecs.iter_next_chunk(it) {
		for row := 0; row < chunk.count; row += 1 {
			transform := ecs.get_mut(chunk, transform_col, row, Transform)
			size := ecs.get(chunk, rect_col, row, Rect)

			rl.DrawLineV(parent_pos, transform.world_pos, rl.BLUE)
		}
	}

	return true
}

mul_v2_with_m3 :: proc(v: Vec2, m: Mat3x3) -> Vec2 {
	v3 := m * Vec3{v.x, v.y, 1}

	return Vec2{v3.x, v3.y}
}

