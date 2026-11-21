extends Node
## Looks up art in res://assets_ext/ (a junction to the local, non-git asset folder) and falls
## back to generated placeholders, so a fresh clone of the repo runs without any art.
##
##   res://assets_ext/textures/<key>.png
##   res://assets_ext/models/<key>.glb   (origin at the bottom centre of one 1x1 cell)
##
## Keys used so far: floor, outside, soft_block, hard_block, wall_block.

const EXT_ROOT := "res://assets_ext/"
const MODEL_EXTENSIONS := [".glb", ".gltf", ".tscn"]
const TEX_SIZE := 64

var _textures := {}
var _materials := {}


func texture(key: String) -> Texture2D:
	if not _textures.has(key):
		var path := EXT_ROOT + "textures/" + key + ".png"
		if ResourceLoader.exists(path):
			_textures[key] = load(path)
		else:
			_textures[key] = ImageTexture.create_from_image(_placeholder_image(key))
	return _textures[key]


## Imported model for a key, or null when only the placeholder exists.
func model(key: String) -> PackedScene:
	for ext in MODEL_EXTENSIONS:
		var path: String = EXT_ROOT + "models/" + key + ext
		if ResourceLoader.exists(path):
			return load(path)
	return null


## Shared material for a key. uv_scale tiles the texture; a BoxMesh needs (3, 2) so each
## face shows the whole texture.
func material(key: String, uv_scale := Vector2.ONE) -> StandardMaterial3D:
	var cache_key := "%s@%s" % [key, uv_scale]
	if not _materials.has(cache_key):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = texture(key)
		# Generated ImageTextures are not flagged sRGB like imported ones; without this
		# they render far too bright.
		mat.albedo_texture_force_srgb = true
		mat.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
		mat.roughness = 0.85
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_materials[cache_key] = mat
	return _materials[cache_key]


# --- Placeholders ------------------------------------------------------------

func _placeholder_image(key: String) -> Image:
	var img := Image.create_empty(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	match key:
		"floor":
			_paint_floor(img)
		"soft_block":
			_paint_bricks(img)
		"hard_block":
			_paint_bevel(img, Color(0.72, 0.76, 0.80), 7)
		"wall_block":
			_paint_bevel(img, Color(0.42, 0.52, 0.64), 5)
			_paint_rivets(img)
		"outside":
			_paint_bevel(img, Color(0.24, 0.29, 0.36), 3)
		_:
			img.fill(Color.MAGENTA)
	img.generate_mipmaps()
	return img


## 2x2 checker of green tiles (one texture repeat covers 2x2 cells).
func _paint_floor(img: Image) -> void:
	var half := TEX_SIZE / 2
	var dark := Color(0.10, 0.42, 0.18)
	var light := Color(0.17, 0.53, 0.25)
	for ty in 2:
		for tx in 2:
			var base := dark if (tx + ty) % 2 == 0 else light
			var rect := Rect2i(tx * half, ty * half, half, half)
			img.fill_rect(rect, base.darkened(0.3))
			img.fill_rect(rect.grow(-1), base)
			img.fill_rect(Rect2i(rect.position + Vector2i(3, 3), Vector2i(half / 3, 2)), base.lightened(0.15))


## Red bricks in staggered rows with mortar, top highlight and bottom shadow.
func _paint_bricks(img: Image) -> void:
	img.fill(Color(0.66, 0.46, 0.40))
	var rows := 4
	var row_h := TEX_SIZE / rows
	var brick_w := TEX_SIZE / 2
	var bounds := Rect2i(0, 0, TEX_SIZE, TEX_SIZE)
	for r in rows:
		var offset := brick_w / 2 if r % 2 == 1 else 0
		for i in 3:
			var rect := Rect2i(i * brick_w - offset + 1, r * row_h + 1, brick_w - 2, row_h - 2).intersection(bounds)
			if rect.size.x <= 0:
				continue
			var base := Color(0.80, 0.38, 0.30).darkened(0.06 * ((r * 3 + i) % 3))
			img.fill_rect(rect, base)
			img.fill_rect(Rect2i(rect.position, Vector2i(rect.size.x, 2)), base.lightened(0.3))
			img.fill_rect(Rect2i(rect.position.x, rect.end.y - 2, rect.size.x, 2), base.darkened(0.3))


## Flat block face with a bevelled edge: light top/left, dark bottom/right.
func _paint_bevel(img: Image, base: Color, bevel: int) -> void:
	img.fill(base)
	var light := base.lightened(0.35)
	var dark := base.darkened(0.35)
	for i in bevel:
		var span := TEX_SIZE - 2 * i
		img.fill_rect(Rect2i(i, i, span, 1), light)
		img.fill_rect(Rect2i(i, i, 1, span), light)
		img.fill_rect(Rect2i(i, TEX_SIZE - 1 - i, span, 1), dark)
		img.fill_rect(Rect2i(TEX_SIZE - 1 - i, i, 1, span), dark)


func _paint_rivets(img: Image) -> void:
	var inset := 11
	for corner in [Vector2i(inset, inset), Vector2i(TEX_SIZE - inset - 3, inset),
			Vector2i(inset, TEX_SIZE - inset - 3), Vector2i(TEX_SIZE - inset - 3, TEX_SIZE - inset - 3)]:
		img.fill_rect(Rect2i(corner, Vector2i(3, 3)), Color(0.15, 0.18, 0.22))
		img.set_pixelv(corner, Color(0.85, 0.9, 0.95))
