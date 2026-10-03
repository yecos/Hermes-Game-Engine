extends SceneTree

func _init() -> void:
	var world := Node3D.new()
	world.name = "CollisionPhysicsTest"
	get_root().add_child(world)
	current_scene = world

	var light := ArcadeCarController3D.new()
	var heavy := ArcadeCarController3D.new()
	light.input_enabled = false
	heavy.input_enabled = false
	light.vehicle_mass = 1000.0
	heavy.vehicle_mass = 2000.0
	world.add_child(light)
	world.add_child(heavy)
	await process_frame

	light.global_position = Vector3(0.0, 0.48, 0.0)
	heavy.global_position = Vector3(2.0, 0.48, 0.0)
	light._set_world_planar_velocity(Vector3(10.0, 0.0, 0.0))
	heavy._set_world_planar_velocity(Vector3.ZERO)
	light._pre_move_velocity = Vector3(10.0, 0.0, 0.0)
	heavy._pre_move_velocity = Vector3.ZERO

	var pre_momentum := light.vehicle_mass * 10.0
	light._resolve_vehicle_impact(
		heavy,
		Vector3(-1.0, 0.0, 0.0),
		Vector3(1.0, 0.48, 0.35)
	)

	var light_v := light._world_planar_velocity().x
	var heavy_v := heavy._world_planar_velocity().x
	var post_momentum := light.vehicle_mass * light_v + heavy.vehicle_mass * heavy_v

	assert(light_v > 0.0 and light_v < 4.0, "Light car should lose most of its speed")
	assert(heavy_v > 2.0 and heavy_v < 5.0, "Heavy car should gain less speed than the light car lost")
	assert(absf(post_momentum - pre_momentum) < 2.0, "Linear momentum must be conserved in car-car impact")
	assert(absf(10.0 - light_v) > absf(heavy_v), "Lower mass car must receive larger delta-v")

	# Equal masses should exchange velocity approximately, softened by restitution.
	var car_a := ArcadeCarController3D.new()
	var car_b := ArcadeCarController3D.new()
	car_a.input_enabled = false
	car_b.input_enabled = false
	car_a.vehicle_mass = 1160.0
	car_b.vehicle_mass = 1160.0
	world.add_child(car_a)
	world.add_child(car_b)
	await process_frame

	car_a.global_position = Vector3(0.0, 0.48, 5.0)
	car_b.global_position = Vector3(2.0, 0.48, 5.0)
	car_a._set_world_planar_velocity(Vector3(10.0, 0.0, 0.0))
	car_b._set_world_planar_velocity(Vector3.ZERO)
	car_a._pre_move_velocity = Vector3(10.0, 0.0, 0.0)
	car_b._pre_move_velocity = Vector3.ZERO

	car_a._resolve_vehicle_impact(
		car_b,
		Vector3(-1.0, 0.0, 0.0),
		Vector3(1.0, 0.48, 5.0)
	)

	var a_v := car_a._world_planar_velocity().x
	var b_v := car_b._world_planar_velocity().x
	assert(a_v > 3.0 and a_v < 5.0, "Equal-mass striker response outside expected range")
	assert(b_v > 5.0 and b_v < 7.0, "Equal-mass target response outside expected range")
	assert(absf((a_v + b_v) - 10.0) < 0.01, "Equal-mass collision must conserve momentum")

	# Immovable wall: normal component rebounds slightly, tangential speed survives
	# with friction loss, and an off-center contact creates yaw.
	var wall_car := ArcadeCarController3D.new()
	wall_car.input_enabled = false
	wall_car.vehicle_mass = 1160.0
	world.add_child(wall_car)
	await process_frame

	wall_car.global_position = Vector3(0.0, 0.48, 10.0)
	wall_car._set_world_planar_velocity(Vector3(10.0, 0.0, 4.0))
	wall_car._pre_move_velocity = Vector3(10.0, 0.0, 4.0)
	wall_car._resolve_static_impact(
		Vector3(-1.0, 0.0, 0.0),
		Vector3(0.75, 0.48, 10.75),
		999
	)

	var wall_v := wall_car._world_planar_velocity()
	assert(wall_v.x < 0.0 and wall_v.x > -2.0, "Static wall should produce a small rebound, not a sticky stop")
	assert(absf(wall_v.z) < 4.0 and absf(wall_v.z) > 0.5, "Tangential friction should reduce but not erase scraping velocity")
	assert(absf(wall_car.yaw_rate) > 0.02, "Off-center collision must create rotational reaction")
	assert(wall_car.last_impact_impulse_ns > 0.0, "Impact impulse telemetry missing")

	print(
		"HGE_COLLISION_PHYSICS_OK light=", snappedf(light_v, 0.01),
		" heavy=", snappedf(heavy_v, 0.01),
		" momentum_error=", snappedf(post_momentum - pre_momentum, 0.01),
		" equal=", snappedf(a_v, 0.01), "/", snappedf(b_v, 0.01),
		" wall_v=", wall_v,
		" wall_yaw=", snappedf(rad_to_deg(wall_car.yaw_rate), 0.1)
	)

	world.free()
	quit(0)
