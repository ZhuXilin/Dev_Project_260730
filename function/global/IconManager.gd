class_name IconManager
extends RefCounted

# ★ 路径更新为 res://content/images/item/
const ICON_DIR = "res://content/images/item/"
static var _cache : Dictionary = {}

static func get_icon(icon_name: String) -> Texture2D:
	if icon_name == "":
		return _get_placeholder()
	
	if _cache.has(icon_name):
		return _cache[icon_name]
		
	# 兼容旧版的直接路径写法
	if icon_name.begins_with("res://"):
		if ResourceLoader.exists(icon_name):
			var tex = load(icon_name)
			_cache[icon_name] = tex
			return tex
		return _get_placeholder()
		
	# 加载统一图标机制 item_xxx
	var path = ICON_DIR + icon_name + ".png"
	if ResourceLoader.exists(path):
		var tex = load(path)
		_cache[icon_name] = tex
		return tex
	
	# 找不到则返回占位图并警告
	push_warning("[IconManager] 找不到图标: " + path)
	var placeholder = _get_placeholder()
	_cache[icon_name] = placeholder
	return placeholder

static func _get_placeholder() -> Texture2D:
	if not _cache.has("__placeholder__"):
		var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color.MAGENTA) # 品红占位图
		_cache["__placeholder__"] = ImageTexture.create_from_image(img)
	return _cache["__placeholder__"]
