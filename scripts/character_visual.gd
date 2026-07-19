extends RefCounted
class_name CharacterVisual

const HULL := Color(0.14, 0.16, 0.22, 1.0)
const HULL_LIT := Color(0.28, 0.32, 0.42, 1.0)
const ARMOR := Color(0.20, 0.24, 0.32, 1.0)
const CYAN := Color(0.35, 0.95, 1.0, 1.0)
const GOLD := Color(1.0, 0.82, 0.25, 1.0)
const MUZZLE := Color(0.75, 1.0, 0.95, 1.0)

## In-game scale — BodyLR / BodyRotate node scale in player.tscn animations.
const COMBAT_SCALE := 0.72
## Soldier mesh multiplier inside BodyLR (bigger silhouette vs gun).
const BODY_MESH_SCALE := 1.55
## Rifle mesh multiplier inside BodyRotate (smaller vs soldier).
const WEAPON_MESH_SCALE := 0.68
const WEAPON_MUZZLE_X := 54.0 * WEAPON_MESH_SCALE

const WALK_SHEET_PATH := "res://assets/sprites/player_walk_spritesheet.png"
const WALK_FRAME_COUNT := 6
## Spritesheet art faces right (frame 0 = idle, frames advance toward a rightward stride).
const SPRITE_TARGET_HEIGHT := 145.0
## Muzzle distance along BodyRotate +X (aim axis); sprite gun points upward in side view.
const SPRITE_MUZZLE_X := 48.0

const EQUIPMENT_PANEL_PATH := "res://assets/png/player_character.png"
const EQUIPMENT_PANEL_H_OVER_W := 1024.0 / 738.0
const EQUIPMENT_IMAGE_SIZE := Vector2(738.0, 1024.0)

## Gear slot icon positions around the character (738×1024 layout).
const EQUIPMENT_SLOT_RECTS := {
	"Helmet": Rect2(42, 95, 141, 131),
	"Gloves": Rect2(42, 360, 141, 141),
	"Boots": Rect2(42, 696, 141, 154),
	"Armor": Rect2(560, 95, 141, 131),
	"Ring1": Rect2(560, 360, 140, 141),
	"Weapon": Rect2(560, 694, 141, 156),
}

static func get_equipment_slot_layout() -> Array:
	var out: Array = []
	var groups := {
		"Ring1": ["Ring1", "Ring2"],
	}
	for slot_name in ["Helmet", "Gloves", "Boots", "Armor", "Ring1", "Weapon"]:
		var rect: Rect2 = EQUIPMENT_SLOT_RECTS[slot_name]
		out.append({
			"slot": slot_name,
			"group": groups.get(slot_name, [slot_name]),
			"x": rect.position.x / EQUIPMENT_IMAGE_SIZE.x,
			"y": rect.position.y / EQUIPMENT_IMAGE_SIZE.y,
			"w": rect.size.x / EQUIPMENT_IMAGE_SIZE.x,
			"h": rect.size.y / EQUIPMENT_IMAGE_SIZE.y,
		})
	return out

## Place a control over a slot; inset_frac shrinks toward the inner icon area.
static func apply_equipment_slot_rect(node: Control, entry: Dictionary, inset_frac: float = 0.0) -> void:
	var ix: float = float(entry["x"]) + float(entry["w"]) * inset_frac
	var iy: float = float(entry["y"]) + float(entry["h"]) * inset_frac
	var iw: float = float(entry["w"]) * (1.0 - inset_frac * 2.0)
	var ih: float = float(entry["h"]) * (1.0 - inset_frac * 2.0)
	node.anchor_left = ix
	node.anchor_top = iy
	node.anchor_right = ix + iw
	node.anchor_bottom = iy + ih
	node.offset_left = 0
	node.offset_top = 0
	node.offset_right = 0
	node.offset_bottom = 0

## Character screen — soldier art + gear slot overlay. Returns overlay for hotspots.
static func build_equipment_panel(parent: Control) -> Control:
	for c in parent.get_children():
		c.queue_free()

	var tex_rect := TextureRect.new()
	tex_rect.name = "EquipmentArt"
	tex_rect.z_index = 0
	tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.texture = PlayerData.load_png_texture(EQUIPMENT_PANEL_PATH)
	tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tex_rect)

	var overlay := Control.new()
	overlay.name = "EquipmentOverlay"
	overlay.z_index = 1
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(overlay)
	return overlay

## Side-view walk spritesheet body (weapon baked into frames).
static func build_sprite_body(parent: Node2D) -> AnimatedSprite2D:
	for c in parent.get_children():
		if c.name != "Shadow":
			c.queue_free()

	var anim := AnimatedSprite2D.new()
	anim.name = "SpriteBody"
	anim.centered = true
	anim.z_index = 1

	var tex: Texture2D = load(WALK_SHEET_PATH) as Texture2D
	var frames := SpriteFrames.new()
	if tex:
		var sheet_size := tex.get_size()
		var frame_w := int(sheet_size.x / WALK_FRAME_COUNT)
		var frame_h := int(sheet_size.y)

		frames.add_animation("idle")
		frames.set_animation_speed("idle", 4.0)
		frames.set_animation_loop("idle", true)
		var idle_frame := AtlasTexture.new()
		idle_frame.atlas = tex
		idle_frame.region = Rect2(0, 0, frame_w, frame_h)
		frames.add_frame("idle", idle_frame)

		frames.add_animation("walk")
		frames.set_animation_speed("walk", 10.0)
		frames.set_animation_loop("walk", true)
		for i in WALK_FRAME_COUNT:
			var frame_tex := AtlasTexture.new()
			frame_tex.atlas = tex
			frame_tex.region = Rect2(i * frame_w, 0, frame_w, frame_h)
			frames.add_frame("walk", frame_tex)

		var mesh_scale := SPRITE_TARGET_HEIGHT / float(frame_h)
		anim.scale = Vector2(mesh_scale, mesh_scale)
		anim.position = Vector2(-6.0, frame_h * mesh_scale * 0.22)

	anim.sprite_frames = frames
	anim.animation = "idle"
	parent.add_child(anim)
	return anim

## Top-down sci-fi soldier body (no weapon — gun lives on BodyRotate).
static func build_combat_body(parent: Node2D) -> void:
	for c in parent.get_children():
		if c.name != "Shadow":
			c.queue_free()

	var root := Node2D.new()
	root.name = "VisualRoot"
	root.scale = Vector2(BODY_MESH_SCALE, BODY_MESH_SCALE)
	root.z_index = 1
	parent.add_child(root)

	var shadow := Polygon2D.new()
	shadow.polygon = _ellipse(Vector2(0, 46), Vector2(42, 14), 14)
	shadow.color = Color(0, 0, 0, 0.45)
	shadow.z_index = -3
	root.add_child(shadow)

	# Boots
	for side in [-1, 1]:
		var boot := Polygon2D.new()
		boot.polygon = PackedVector2Array([
			Vector2(-8 * side, 28), Vector2(-18 * side, 30), Vector2(-20 * side, 46),
			Vector2(-6 * side, 48), Vector2(2 * side, 42)
		])
		boot.color = HULL_LIT.darkened(0.2)
		root.add_child(boot)

	# Legs
	for side in [-1, 1]:
		var leg := Polygon2D.new()
		leg.polygon = PackedVector2Array([
			Vector2(-6 * side, 8), Vector2(-14 * side, 10), Vector2(-16 * side, 30), Vector2(-4 * side, 28)
		])
		leg.color = ARMOR
		root.add_child(leg)

	# Torso / tactical vest
	var torso := Polygon2D.new()
	torso.polygon = PackedVector2Array([
		Vector2(-24, 8), Vector2(-28, -8), Vector2(-20, -26), Vector2(20, -26),
		Vector2(28, -8), Vector2(24, 8), Vector2(14, 14), Vector2(-14, 14)
	])
	torso.color = ARMOR
	root.add_child(torso)

	var vest_edge := Line2D.new()
	vest_edge.points = torso.polygon
	vest_edge.width = 1.5
	vest_edge.default_color = HULL_LIT
	vest_edge.closed = true
	root.add_child(vest_edge)

	# Chest light
	var core := Polygon2D.new()
	core.name = "ChestCore"
	core.polygon = _scale_poly(_hex(7, 6), Vector2(1, 1))
	core.position = Vector2(0, -6)
	core.color = CYAN
	root.add_child(core)

	# Shoulder pads
	for side in [-1, 1]:
		var pad := Polygon2D.new()
		pad.polygon = PackedVector2Array([
			Vector2(18 * side, -22), Vector2(34 * side, -16), Vector2(32 * side, -2), Vector2(14 * side, -6)
		])
		pad.color = HULL_LIT
		root.add_child(pad)

		var pad_stripe := Line2D.new()
		pad_stripe.points = PackedVector2Array([
			Vector2(22 * side, -18), Vector2(28 * side, -8)
		])
		pad_stripe.width = 2.0
		pad_stripe.default_color = CYAN
		root.add_child(pad_stripe)

	# Arms / gauntlets (reach toward rifle grip)
	for side in [-1, 1]:
		var arm := Polygon2D.new()
		arm.polygon = PackedVector2Array([
			Vector2(12 * side, -2), Vector2(24 * side, -6), Vector2(28 * side, 6), Vector2(16 * side, 10)
		])
		arm.color = HULL_LIT.darkened(0.06)
		root.add_child(arm)

		var gauntlet := Polygon2D.new()
		gauntlet.polygon = _scale_poly(_hex(5, 6), Vector2(1, 1))
		gauntlet.position = Vector2(26 * side, 2)
		gauntlet.color = ARMOR.lightened(0.08)
		root.add_child(gauntlet)

	# Helmet
	var helm := Polygon2D.new()
	helm.polygon = _ellipse(Vector2(0, -36), Vector2(22, 24), 14)
	helm.color = HULL
	root.add_child(helm)

	var helm_ridge := Line2D.new()
	helm_ridge.points = PackedVector2Array([
		Vector2(0, -58), Vector2(0, -44)
	])
	helm_ridge.width = 3.0
	helm_ridge.default_color = HULL_LIT
	root.add_child(helm_ridge)

	var visor := Polygon2D.new()
	visor.polygon = PackedVector2Array([
		Vector2(-18, -44), Vector2(18, -44), Vector2(16, -28), Vector2(-16, -28)
	])
	visor.color = Color(CYAN.r, CYAN.g, CYAN.b, 0.75)
	root.add_child(visor)

	var visor_glow := Line2D.new()
	visor_glow.points = visor.polygon
	visor_glow.width = 1.5
	visor_glow.default_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.9)
	visor_glow.closed = true
	root.add_child(visor_glow)

	# Backpack / comm pack
	var pack := Polygon2D.new()
	pack.polygon = PackedVector2Array([
		Vector2(-10, -18), Vector2(10, -18), Vector2(8, 6), Vector2(-8, 6)
	])
	pack.color = HULL.darkened(0.1)
	pack.z_index = -1
	root.add_child(pack)

	_start_soldier_pulse(root)

## Sci-fi assault rifle on BodyRotate — points along +X toward BulletSpawnPoint.
static func build_combat_weapon(parent: Node2D) -> void:
	var existing := parent.get_node_or_null("WeaponVisual")
	if existing:
		existing.queue_free()

	var gun := Node2D.new()
	gun.name = "WeaponVisual"
	gun.position = Vector2(0, -6)
	gun.scale = Vector2(WEAPON_MESH_SCALE, WEAPON_MESH_SCALE)
	gun.z_index = 3
	parent.add_child(gun)
	parent.move_child(gun, 0)

	# Stock
	var stock := Polygon2D.new()
	stock.polygon = PackedVector2Array([
		Vector2(-22, -5), Vector2(-8, -7), Vector2(-6, 5), Vector2(-20, 7)
	])
	stock.color = HULL_LIT.darkened(0.15)
	gun.add_child(stock)

	# Receiver
	var receiver := Polygon2D.new()
	receiver.polygon = PackedVector2Array([
		Vector2(-8, -8), Vector2(14, -8), Vector2(16, 8), Vector2(-6, 8)
	])
	receiver.color = HULL
	gun.add_child(receiver)

	# Magazine
	var mag := Polygon2D.new()
	mag.polygon = PackedVector2Array([
		Vector2(2, 8), Vector2(10, 8), Vector2(8, 20), Vector2(0, 20)
	])
	mag.color = HULL_LIT.darkened(0.2)
	gun.add_child(mag)

	# Barrel shroud
	var barrel := Polygon2D.new()
	barrel.polygon = PackedVector2Array([
		Vector2(14, -5), Vector2(52, -4), Vector2(54, 0), Vector2(52, 4), Vector2(14, 5)
	])
	barrel.color = ARMOR
	gun.add_child(barrel)

	# Energy rails on barrel
	for y in [-2.5, 2.5]:
		var rail := Line2D.new()
		rail.points = PackedVector2Array([Vector2(18, y), Vector2(48, y)])
		rail.width = 1.5
		rail.default_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.85)
		gun.add_child(rail)

	# Scope
	var scope := Polygon2D.new()
	scope.polygon = PackedVector2Array([
		Vector2(4, -12), Vector2(16, -12), Vector2(16, -8), Vector2(4, -8)
	])
	scope.color = HULL_LIT
	gun.add_child(scope)

	# Muzzle brake
	var muzzle := Polygon2D.new()
	muzzle.name = "MuzzleGlow"
	muzzle.polygon = _scale_poly(_hex(5, 6), Vector2(1.2, 1.0))
	muzzle.position = Vector2(54, 0)
	muzzle.color = MUZZLE
	gun.add_child(muzzle)

	var tw := gun.create_tween().set_loops()
	tw.tween_property(muzzle, "modulate:a", 0.45, 0.35)
	tw.tween_property(muzzle, "modulate:a", 1.0, 0.35)

## Character screen — soldier holding rifle.
static func build_paper_doll(parent: Control) -> void:
	for c in parent.get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = Color(0.025, 0.03, 0.055)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)

	var frame := PanelContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 8
	frame.offset_top = 8
	frame.offset_right = -8
	frame.offset_bottom = -8
	var fstyle := StyleBoxFlat.new()
	fstyle.bg_color = Color(0.04, 0.05, 0.09, 0.95)
	fstyle.border_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.45)
	fstyle.set_border_width_all(2)
	fstyle.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", fstyle)
	parent.add_child(frame)

	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.offset_left = 16
	canvas.offset_top = 16
	canvas.offset_right = -16
	canvas.offset_bottom = -16
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(canvas)

	var draw_host := Node2D.new()
	canvas.add_child(draw_host)
	_layout_doll_canvas(canvas, draw_host, parent.custom_minimum_size)
	_add_doll_bg_rings(draw_host)
	_add_doll_soldier(draw_host)

static func _layout_doll_canvas(canvas: Control, draw_host: Node2D, fallback_size: Vector2) -> void:
	var sz := canvas.size
	if sz.x < 8.0:
		sz = fallback_size - Vector2(32, 32)
	draw_host.position = sz * 0.5
	var s: float = minf(sz.x, sz.y) / 360.0
	draw_host.scale = Vector2(s, s)
	if not canvas.resized.is_connected(_on_doll_canvas_resized):
		canvas.resized.connect(_on_doll_canvas_resized.bind(draw_host))

static func _on_doll_canvas_resized(draw_host: Node2D) -> void:
	var canvas := draw_host.get_parent() as Control
	if canvas == null:
		return
	var sz := canvas.size
	draw_host.position = sz * 0.5
	var s: float = minf(sz.x, sz.y) / 360.0
	draw_host.scale = Vector2(s, s)

static func _add_doll_bg_rings(host: Node2D) -> void:
	for i in 3:
		var ring := Line2D.new()
		var r: float = 90.0 + float(i) * 28.0
		ring.points = _ellipse(Vector2.ZERO, Vector2(r, r * 0.92), 28)
		ring.width = 1.2
		ring.default_color = Color(CYAN.r, CYAN.g, CYAN.b, 0.12 - float(i) * 0.02)
		ring.closed = true
		ring.z_index = -2
		host.add_child(ring)

static func _add_doll_soldier(host: Node2D) -> void:
	# Legs
	for side in [-1, 1]:
		var leg := Polygon2D.new()
		leg.polygon = PackedVector2Array([
			Vector2(14 * side, 68), Vector2(28 * side, 72), Vector2(24 * side, 118), Vector2(8 * side, 118)
		])
		leg.color = HULL_LIT.darkened(0.15)
		host.add_child(leg)

	# Torso
	var torso := Polygon2D.new()
	torso.polygon = PackedVector2Array([
		Vector2(-42, -10), Vector2(-46, 42), Vector2(-22, 72), Vector2(22, 72),
		Vector2(46, 42), Vector2(42, -10), Vector2(24, -38), Vector2(-24, -38)
	])
	torso.color = ARMOR
	host.add_child(torso)

	var torso_edge := Line2D.new()
	torso_edge.points = torso.polygon
	torso_edge.width = 2.0
	torso_edge.default_color = HULL_LIT
	torso_edge.closed = true
	host.add_child(torso_edge)

	# Helmet
	var helm := Polygon2D.new()
	helm.polygon = _ellipse(Vector2(0, -72), Vector2(36, 40), 16)
	helm.color = HULL
	host.add_child(helm)

	var visor := Polygon2D.new()
	visor.polygon = PackedVector2Array([
		Vector2(-24, -88), Vector2(24, -88), Vector2(20, -68), Vector2(-20, -68)
	])
	visor.color = Color(CYAN.r, CYAN.g, CYAN.b, 0.6)
	host.add_child(visor)

	# Arms
	for side in [-1, 1]:
		var arm := Polygon2D.new()
		arm.polygon = PackedVector2Array([
			Vector2(42 * side, -6), Vector2(68 * side, 4), Vector2(62 * side, 38), Vector2(40 * side, 32)
		])
		arm.color = HULL_LIT.darkened(0.08)
		host.add_child(arm)

	# Rifle (held across chest, angled up-right)
	var rifle := Node2D.new()
	rifle.position = Vector2(20, -10)
	rifle.rotation = -0.55
	rifle.z_index = 3
	host.add_child(rifle)
	_add_rifle_shape(rifle, 1.15)

	var core := Polygon2D.new()
	core.polygon = _scale_poly(_hex(12, 8), Vector2(1, 1))
	core.position = Vector2(0, 10)
	core.color = Color(CYAN.r, CYAN.g, CYAN.b, 0.7)
	core.z_index = 2
	host.add_child(core)

static func _add_rifle_shape(parent: Node2D, scale_mul: float = 1.0) -> void:
	var s := scale_mul
	var stock := Polygon2D.new()
	stock.polygon = PackedVector2Array([
		Vector2(-28 * s, -4 * s), Vector2(-10 * s, -6 * s), Vector2(-8 * s, 6 * s), Vector2(-26 * s, 8 * s)
	])
	stock.color = HULL_LIT.darkened(0.15)
	parent.add_child(stock)

	var receiver := Polygon2D.new()
	receiver.polygon = PackedVector2Array([
		Vector2(-10 * s, -10 * s), Vector2(18 * s, -10 * s), Vector2(20 * s, 10 * s), Vector2(-8 * s, 10 * s)
	])
	receiver.color = HULL
	parent.add_child(receiver)

	var barrel := Polygon2D.new()
	barrel.polygon = PackedVector2Array([
		Vector2(18 * s, -6 * s), Vector2(62 * s, -5 * s), Vector2(64 * s, 0), Vector2(62 * s, 5 * s), Vector2(18 * s, 6 * s)
	])
	barrel.color = ARMOR
	parent.add_child(barrel)

	for y in [-2.0, 2.0]:
		var rail := Line2D.new()
		rail.points = PackedVector2Array([Vector2(22 * s, y * s), Vector2(58 * s, y * s)])
		rail.width = 2.0
		rail.default_color = CYAN
		parent.add_child(rail)

	var muzzle := Polygon2D.new()
	muzzle.polygon = _scale_poly(_hex(6 * s, 6), Vector2(1, 1))
	muzzle.position = Vector2(64 * s, 0)
	muzzle.color = MUZZLE
	parent.add_child(muzzle)

static func _start_soldier_pulse(root: Node2D) -> void:
	var core: Node = root.get_node_or_null("ChestCore")
	if core == null:
		return
	var tw := root.create_tween().set_loops()
	tw.tween_property(core, "modulate", Color(0.7, 1.2, 1.2), 0.6)
	tw.tween_property(core, "modulate", Color(1.0, 1.0, 1.0), 0.6)

static func _hex(r: float, seg: int) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i in seg:
		var a: float = TAU * float(i) / float(seg) - PI / 2.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

static func _ellipse(center: Vector2, radii: Vector2, seg: int) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i in seg:
		var a: float = TAU * float(i) / float(seg)
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts

static func _scale_poly(pts: PackedVector2Array, scale: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = []
	for p in pts:
		out.append(Vector2(p.x * scale.x, p.y * scale.y))
	return out
