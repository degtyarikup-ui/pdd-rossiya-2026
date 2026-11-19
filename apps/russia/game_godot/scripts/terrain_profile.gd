## Height offset authored in the scene; horizontal traffic/collision paths stay unchanged.
class_name TerrainProfile
extends RefCounted

static func height(data: Dictionary, x: float, z: float) -> float:
	var points: Array = data.get('profile', [])
	var y := 0.0
	if not points.is_empty():
		y = float(points[0][1] if z <= float(points[0][0]) else points[-1][1])
		for i in points.size()-1:
			var a: Array = points[i]; var b: Array = points[i+1]
			if z >= float(a[0]) and z <= float(b[0]):
				var t := smoothstep(float(a[0]),float(b[0]),z)
				y = lerpf(float(a[1]),float(b[1]),t)
				break
		var crop := float(points[-1][0])
		y *= smoothstep(0.0, minf(12.0,crop), crop-absf(x))
	for bump: Dictionary in data.get('bumps', []):
		var side := clampf((float(bump.width)/2-absf(x-float(bump.centre[0])))/.15,0,1)
		var u := absf(z-float(bump.centre[1]))/(float(bump.length)/2)
		if u < 1: y += float(bump.height)*(1+cos(PI*u))*.5*side
	return y

static func placement(data: Dictionary, x: float, z: float, yaw: float, half_length := 1.3) -> Vector3:
	var f := Vector2(sin(yaw),cos(yaw))*half_length
	var front := height(data,x+f.x,z+f.y)
	var rear := height(data,x-f.x,z-f.y)
	var side := Vector2(cos(yaw),-sin(yaw))*.8
	var roll := atan2(height(data,x+side.x,z+side.y)-height(data,x-side.x,z-side.y),1.6)
	return Vector3((front+rear)*.5,-atan2(front-rear,2*half_length),roll)

static func pose(node: Node3D, data: Dictionary, half_length := 1.3, base := 0.0) -> void:
	if data.is_empty(): return
	var at := placement(data,node.position.x,node.position.z,node.rotation.y,half_length)
	node.position.y = base+at.x
	node.rotation.x = at.y
	node.rotation.z = at.z
