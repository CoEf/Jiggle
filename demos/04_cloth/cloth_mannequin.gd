class_name ClothMannequin
extends Node3D

## 치마가 걸릴 하반신 마네킹. 골반 하나 + 다리 둘.
##
## 스켈레톤도 스키닝도 없다. 그냥 [CapsuleMesh] 세 개를 코드로 배치할 뿐이다.
## 천 데모에서 중요한 건 [b]충돌체의 위치[/b]이지 예쁜 모델이 아니다.
##
## 다리는 걷기 위상에 맞춰 흔들리고, 그때마다 치마를 [b]안쪽에서[/b] 밀어낸다.
## 천이 몸을 따라 움직이는 것처럼 보이는 이유의 대부분이 여기서 나온다.

const HIP_Y := 0.95
const HIP_HALF_WIDTH := 0.07
const HIP_RADIUS := 0.095
const LEG_OFFSET := 0.065
const LEG_TOP := 0.90
const LEG_SEGMENT := 0.78
const LEG_RADIUS := 0.062
const SKIN_COLOR := Color(0.80, 0.63, 0.56)

var colliders: Array[JiggleVerletBody.Collider] = []

var _legs: Array[MeshInstance3D] = []
var _leg_directions := PackedVector3Array()


func build() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = SKIN_COLOR
	material.roughness = 0.65

	var hips := MeshInstance3D.new()
	hips.name = "Hips"
	var hip_mesh := CapsuleMesh.new()
	hip_mesh.radius = HIP_RADIUS
	# CapsuleMesh 의 height 는 반구까지 포함한 전체 길이다.
	hip_mesh.height = HIP_HALF_WIDTH * 2.0 + HIP_RADIUS * 2.0
	hips.mesh = hip_mesh
	hips.material_override = material
	# 캡슐은 기본이 Y축 방향이라 눕히려면 Z축으로 90도 돌린다.
	hips.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, HIP_Y, 0.0))
	add_child(hips)

	for side in 2:
		var leg := MeshInstance3D.new()
		leg.name = "Leg%d" % side
		var leg_mesh := CapsuleMesh.new()
		leg_mesh.radius = LEG_RADIUS
		leg_mesh.height = LEG_SEGMENT + LEG_RADIUS * 2.0
		leg.mesh = leg_mesh
		leg.material_override = material
		add_child(leg)
		_legs.append(leg)
		_leg_directions.append(Vector3.DOWN)
		colliders.append(JiggleVerletBody.Collider.new(Vector3.ZERO, Vector3.ZERO, LEG_RADIUS))

	colliders.push_front(
		JiggleVerletBody.Collider.new(
			Vector3(HIP_HALF_WIDTH, HIP_Y, 0.0),
			Vector3(-HIP_HALF_WIDTH, HIP_Y, 0.0),
			HIP_RADIUS
		)
	)
	set_leg_swing(0.0)


## 다리를 앞뒤로 흔든다. 좌우가 서로 반대 위상이다.
func set_leg_swing(angle: float) -> void:
	for side in _legs.size():
		var swing := angle if side == 0 else -angle
		var direction := Vector3.DOWN.rotated(Vector3.RIGHT, swing)
		_leg_directions[side] = direction
		var pivot := _leg_pivot(side)
		# 캡슐 메쉬는 중심 기준이므로 선분의 중점에 놓는다.
		var center := pivot + direction * (LEG_SEGMENT * 0.5)
		_legs[side].transform = Transform3D(Basis(Vector3.RIGHT, swing), center)


## 충돌체를 현재 월드 좌표로 갱신한다. 몸이 움직이면 충돌체도 따라가야 한다.
func refresh_colliders() -> void:
	var world := global_transform
	colliders[0].point_a = world * Vector3(HIP_HALF_WIDTH, HIP_Y, 0.0)
	colliders[0].point_b = world * Vector3(-HIP_HALF_WIDTH, HIP_Y, 0.0)
	for side in _legs.size():
		var pivot := _leg_pivot(side)
		colliders[side + 1].point_a = world * pivot
		colliders[side + 1].point_b = world * (pivot + _leg_directions[side] * LEG_SEGMENT)


func _leg_pivot(side: int) -> Vector3:
	var side_sign := 1.0 if side == 0 else -1.0
	return Vector3(LEG_OFFSET * side_sign, LEG_TOP, 0.0)
