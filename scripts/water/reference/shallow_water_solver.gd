class_name ShallowWaterReference
extends RefCounted

## Conservative 2D shallow-water reference with hydrostatic reconstruction.
## This is a CPU comparison solver for T02; it is not yet the production backend.

const GRAVITY := 9.81
const DRY_DEPTH := 0.001
const VELOCITY_DEPTH := 0.005
const COURANT := 0.35

var domain: SandWaterDomain
var momentum_x := PackedFloat32Array()
var momentum_y := PackedFloat32Array()
var negative_depth_events := 0
var max_substeps_used := 0
var overload_events := 0
var overload_first_tick := -1
var overload_requested_substeps := 0
var overload_speed_mps := 0.0
var velocity_limit_events := 0
var velocity_limit_shallow_events := 0
var velocity_limit_boundary_events := 0
var velocity_limit_ocean_edge_events := 0
var velocity_limit_opposite_edge_events := 0
var velocity_limit_cross_edge_events := 0
var velocity_limit_first_tick := -1
var velocity_limit_first_cell := -1
var velocity_limit_max_raw_speed_mps := 0.0
var prescribed_tide_boundary := false


func _init(p_domain: SandWaterDomain) -> void:
	domain = p_domain
	momentum_x.resize(domain.water.size())
	momentum_y.resize(domain.water.size())
	momentum_x.fill(0.0)
	momentum_y.fill(0.0)


func step(delta: float) -> void:
	if delta <= 0.0:
		return
	_limit_momentum()
	var maximum_speed := 0.01
	for i in domain.water.size():
		var depth: float = domain.water[i]
		if depth > DRY_DEPTH:
			var speed := maxf(absf(momentum_x[i]), absf(momentum_y[i])) / maxf(depth, VELOCITY_DEPTH)
			maximum_speed = maxf(maximum_speed, speed + sqrt(GRAVITY * depth))
	var safe_step := COURANT * domain.cell_size_m / maximum_speed
	var substeps := maxi(1, ceili(delta / safe_step))
	if substeps > 64:
		overload_events += 1
		if overload_first_tick < 0:
			overload_first_tick = domain.sim_tick
			overload_requested_substeps = substeps
			overload_speed_mps = maximum_speed
		return
	max_substeps_used = maxi(max_substeps_used, substeps)
	var sub_delta := delta / float(substeps)
	for _substep in substeps:
		_step_once(sub_delta)
		_limit_momentum()
	domain.sim_tick += 1


func set_tide_boundary(level_m: float) -> void:
	# The x=0 prescribed ocean-level cell is a reservoir, not a reflecting wall with
	# independently evolving momentum. Its water-volume change is ledgered by
	# the domain, while its momentum is held at rest between flux evaluations.
	prescribed_tide_boundary = true
	domain.set_tide_boundary(level_m)
	_zero_tide_boundary_momentum()


func _zero_tide_boundary_momentum() -> void:
	for y in domain.grid_size:
		var i := domain.index(0, y)
		momentum_x[i] = 0.0
		momentum_y[i] = 0.0


func _limit_momentum() -> void:
	for i in domain.water.size():
		var depth: float = domain.water[i]
		if depth <= DRY_DEPTH:
			momentum_x[i] = 0.0
			momentum_y[i] = 0.0
			continue
		var momentum_length := Vector2(momentum_x[i], momentum_y[i]).length()
		var raw_speed := momentum_length / depth
		var maximum_velocity := maxf(1.5, 3.0 * sqrt(GRAVITY * depth))
		var maximum_momentum := maximum_velocity * depth
		if momentum_length > maximum_momentum:
			if depth < 0.01:
				velocity_limit_shallow_events += 1
			if i % domain.grid_size == 0 or i % domain.grid_size == domain.grid_size - 1 or i < domain.grid_size or i >= domain.water.size() - domain.grid_size:
				velocity_limit_boundary_events += 1
				if i % domain.grid_size == 0:
					velocity_limit_ocean_edge_events += 1
				if i % domain.grid_size == domain.grid_size - 1:
					velocity_limit_opposite_edge_events += 1
				if i < domain.grid_size or i >= domain.water.size() - domain.grid_size:
					velocity_limit_cross_edge_events += 1
			if velocity_limit_first_tick < 0:
				velocity_limit_first_tick = domain.sim_tick
				velocity_limit_first_cell = i
			velocity_limit_max_raw_speed_mps = maxf(velocity_limit_max_raw_speed_mps, raw_speed)
			var scale := maximum_momentum / momentum_length
			momentum_x[i] *= scale
			momentum_y[i] *= scale
			velocity_limit_events += 1


func _step_once(delta: float) -> void:
	var count := domain.water.size()
	var dh := PackedFloat32Array()
	var dqx := PackedFloat32Array()
	var dqy := PackedFloat32Array()
	var edge_flux_x := PackedFloat32Array()
	var edge_flux_y := PackedFloat32Array()
	var edge_momentum_xx := PackedFloat32Array()
	var edge_momentum_xy := PackedFloat32Array()
	var edge_momentum_yx := PackedFloat32Array()
	var edge_momentum_yy := PackedFloat32Array()
	var outgoing_depth := PackedFloat32Array()
	dh.resize(count)
	dqx.resize(count)
	dqy.resize(count)
	edge_flux_x.resize(count)
	edge_flux_y.resize(count)
	edge_momentum_xx.resize(count)
	edge_momentum_xy.resize(count)
	edge_momentum_yx.resize(count)
	edge_momentum_yy.resize(count)
	outgoing_depth.resize(count)
	dh.fill(0.0)
	dqx.fill(0.0)
	dqy.fill(0.0)
	edge_flux_x.fill(0.0)
	edge_flux_y.fill(0.0)
	edge_momentum_xx.fill(0.0)
	edge_momentum_xy.fill(0.0)
	edge_momentum_yx.fill(0.0)
	edge_momentum_yy.fill(0.0)
	outgoing_depth.fill(0.0)
	domain.flux_left.fill(0.0)
	domain.flux_right.fill(0.0)
	domain.flux_up.fill(0.0)
	domain.flux_down.fill(0.0)
	var ratio := delta / domain.cell_size_m
	var edge_length := domain.cell_size_m
	for y in domain.grid_size:
		for x in domain.grid_size - 1:
			var left := domain.index(x, y)
			var right := domain.index(x + 1, y)
			var h_left: float = domain.water[left]
			var h_right: float = domain.water[right]
			var left_blocked := domain.obstacle[left] >= 0.5
			var right_blocked := domain.obstacle[right] >= 0.5
			if left_blocked or right_blocked:
				if not left_blocked:
					dqx[left] -= ratio * 0.5 * GRAVITY * h_left * h_left
				if not right_blocked:
					dqx[right] += ratio * 0.5 * GRAVITY * h_right * h_right
				continue
			var zmax := maxf(domain.bed_at(left), domain.bed_at(right))
			var hl := maxf(0.0, domain.surface_at(left) - zmax)
			var hr := maxf(0.0, domain.surface_at(right) - zmax)
			var ul := momentum_x[left] / maxf(h_left, VELOCITY_DEPTH) if h_left > DRY_DEPTH else 0.0
			var ur := momentum_x[right] / maxf(h_right, VELOCITY_DEPTH) if h_right > DRY_DEPTH else 0.0
			var vl := momentum_y[left] / maxf(h_left, VELOCITY_DEPTH) if h_left > DRY_DEPTH else 0.0
			var vr := momentum_y[right] / maxf(h_right, VELOCITY_DEPTH) if h_right > DRY_DEPTH else 0.0
			var qxl := hl * ul
			var qxr := hr * ur
			var qyl := hl * vl
			var qyr := hr * vr
			var wavespeed := maxf(absf(ul) + sqrt(GRAVITY * hl), absf(ur) + sqrt(GRAVITY * hr))
			var fh := 0.5 * (qxl + qxr) - 0.5 * wavespeed * (hr - hl)
			var fqx := 0.5 * (qxl * ul + qxr * ur + 0.5 * GRAVITY * (hl * hl + hr * hr)) - 0.5 * wavespeed * (qxr - qxl)
			var fqy := 0.5 * (qyl * ul + qyr * ur) - 0.5 * wavespeed * (qyr - qyl)
			edge_flux_x[left] = fh
			edge_momentum_xx[left] = fqx
			edge_momentum_xy[left] = fqy
			if fh > 0.0:
				outgoing_depth[left] += ratio * fh
			else:
				outgoing_depth[right] -= ratio * fh
			dh[left] -= ratio * fh
			dh[right] += ratio * fh
			dqx[left] -= ratio * (fqx + 0.5 * GRAVITY * (h_left * h_left - hl * hl))
			dqx[right] += ratio * (fqx + 0.5 * GRAVITY * (h_right * h_right - hr * hr))
			dqy[left] -= ratio * fqy
			dqy[right] += ratio * fqy
			if fh > 0.0:
				domain.flux_right[left] = fh * edge_length
			elif fh < 0.0:
				domain.flux_left[right] = -fh * edge_length
	for y in domain.grid_size - 1:
		for x in domain.grid_size:
			var top := domain.index(x, y)
			var bottom := domain.index(x, y + 1)
			var h_top: float = domain.water[top]
			var h_bottom: float = domain.water[bottom]
			var top_blocked := domain.obstacle[top] >= 0.5
			var bottom_blocked := domain.obstacle[bottom] >= 0.5
			if top_blocked or bottom_blocked:
				if not top_blocked:
					dqy[top] -= ratio * 0.5 * GRAVITY * h_top * h_top
				if not bottom_blocked:
					dqy[bottom] += ratio * 0.5 * GRAVITY * h_bottom * h_bottom
				continue
			var zmax := maxf(domain.bed_at(top), domain.bed_at(bottom))
			var ht := maxf(0.0, domain.surface_at(top) - zmax)
			var hb := maxf(0.0, domain.surface_at(bottom) - zmax)
			var ut := momentum_x[top] / maxf(h_top, VELOCITY_DEPTH) if h_top > DRY_DEPTH else 0.0
			var ub := momentum_x[bottom] / maxf(h_bottom, VELOCITY_DEPTH) if h_bottom > DRY_DEPTH else 0.0
			var vt := momentum_y[top] / maxf(h_top, VELOCITY_DEPTH) if h_top > DRY_DEPTH else 0.0
			var vb := momentum_y[bottom] / maxf(h_bottom, VELOCITY_DEPTH) if h_bottom > DRY_DEPTH else 0.0
			var qxt := ht * ut
			var qxb := hb * ub
			var qyt := ht * vt
			var qyb := hb * vb
			var wavespeed := maxf(absf(vt) + sqrt(GRAVITY * ht), absf(vb) + sqrt(GRAVITY * hb))
			var fh := 0.5 * (qyt + qyb) - 0.5 * wavespeed * (hb - ht)
			var fqy := 0.5 * (qyt * vt + qyb * vb + 0.5 * GRAVITY * (ht * ht + hb * hb)) - 0.5 * wavespeed * (qyb - qyt)
			var fqx := 0.5 * (qxt * vt + qxb * vb) - 0.5 * wavespeed * (qxb - qxt)
			edge_flux_y[top] = fh
			edge_momentum_yx[top] = fqx
			edge_momentum_yy[top] = fqy
			if fh > 0.0:
				outgoing_depth[top] += ratio * fh
			else:
				outgoing_depth[bottom] -= ratio * fh
			dh[top] -= ratio * fh
			dh[bottom] += ratio * fh
			dqy[top] -= ratio * (fqy + 0.5 * GRAVITY * (h_top * h_top - ht * ht))
			dqy[bottom] += ratio * (fqy + 0.5 * GRAVITY * (h_bottom * h_bottom - hb * hb))
			dqx[top] -= ratio * fqx
			dqx[bottom] += ratio * fqx
			if fh > 0.0:
				domain.flux_down[top] = fh * edge_length
			elif fh < 0.0:
				domain.flux_up[bottom] = -fh * edge_length
	# A reflecting wall has zero mass flux and hydrostatic pressure on its face.
	for y in domain.grid_size:
		var left := domain.index(0, y)
		var right := domain.index(domain.grid_size - 1, y)
		dqx[left] += ratio * 0.5 * GRAVITY * pow(domain.water[left], 2)
		dqx[right] -= ratio * 0.5 * GRAVITY * pow(domain.water[right], 2)
	for x in domain.grid_size:
		var top := domain.index(x, 0)
		var bottom := domain.index(x, domain.grid_size - 1)
		dqy[top] += ratio * 0.5 * GRAVITY * pow(domain.water[top], 2)
		dqy[bottom] -= ratio * 0.5 * GRAVITY * pow(domain.water[bottom], 2)
	# Rusanov fluxes are limited by the total water available to each upstream
	# cell across all four faces. Applying the same scale to both sides keeps
	# the discrete water balance conservative at wet/dry boundaries.
	var drain_scale := PackedFloat32Array()
	drain_scale.resize(count)
	drain_scale.fill(1.0)
	for i in count:
		if outgoing_depth[i] > domain.water[i]:
			drain_scale[i] = domain.water[i] / maxf(outgoing_depth[i], 0.000000001)
	for y in domain.grid_size:
		for x in domain.grid_size - 1:
			var left := domain.index(x, y)
			var right := domain.index(x + 1, y)
			var flux: float = edge_flux_x[left]
			var scale: float = drain_scale[left] if flux > 0.0 else drain_scale[right]
			var correction := ratio * flux * (1.0 - scale)
			dh[left] += correction
			dh[right] -= correction
			var momentum_correction_x := ratio * edge_momentum_xx[left] * (1.0 - scale)
			var momentum_correction_y := ratio * edge_momentum_xy[left] * (1.0 - scale)
			dqx[left] += momentum_correction_x
			dqx[right] -= momentum_correction_x
			dqy[left] += momentum_correction_y
			dqy[right] -= momentum_correction_y
			if flux > 0.0:
				domain.flux_right[left] *= scale
			else:
				domain.flux_left[right] *= scale
	for y in domain.grid_size - 1:
		for x in domain.grid_size:
			var top := domain.index(x, y)
			var bottom := domain.index(x, y + 1)
			var flux: float = edge_flux_y[top]
			var scale: float = drain_scale[top] if flux > 0.0 else drain_scale[bottom]
			var correction := ratio * flux * (1.0 - scale)
			dh[top] += correction
			dh[bottom] -= correction
			var momentum_correction_x := ratio * edge_momentum_yx[top] * (1.0 - scale)
			var momentum_correction_y := ratio * edge_momentum_yy[top] * (1.0 - scale)
			dqx[top] += momentum_correction_x
			dqx[bottom] -= momentum_correction_x
			dqy[top] += momentum_correction_y
			dqy[bottom] -= momentum_correction_y
			if flux > 0.0:
				domain.flux_down[top] *= scale
			else:
				domain.flux_up[bottom] *= scale
	for i in count:
		if domain.obstacle[i] >= 0.5:
			momentum_x[i] = 0.0
			momentum_y[i] = 0.0
			continue
		var new_depth: float = domain.water[i] + dh[i]
		if new_depth < -0.000001:
			negative_depth_events += 1
		domain.water[i] = maxf(new_depth, 0.0)
		if domain.water[i] <= DRY_DEPTH:
			momentum_x[i] = 0.0
			momentum_y[i] = 0.0
		else:
			momentum_x[i] += dqx[i]
			momentum_y[i] += dqy[i]
	if prescribed_tide_boundary:
		_zero_tide_boundary_momentum()
