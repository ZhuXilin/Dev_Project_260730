class_name IconManager
extends RefCounted

const IMAGE_ROOT = "res://content/images/"

static var _cache : Dictionary = {}
static var _placeholder : Texture2D = null

## 核心入口：
## 1. 如果是 "res://..." 绝对路径，直接加载。
## 2. 如果是 "characters/avatar/avatar_003"，自动补全前缀和 .png
## 3. 如果是纯文件名 "item_100" 或 "avatar_003"，自动去各个常用目录里搜索。
static func get_icon(icon_name: String, use_placeholder: bool = true) -> Texture2D:
	if icon_name == "":
		return _get_placeholder() if use_placeholder else null
		
	if _cache.has(icon_name):
		return _cache[icon_name]
		
	var candidates := _get_candidate_paths(icon_name)
	for path in candidates:
		if ResourceLoader.exists(path):
			var tex = load(path)
			if tex:
				_cache[icon_name] = tex
				return tex
				
	if use_placeholder:
		push_warning("[IconManager] 找不到图标: " + icon_name + " (尝试过: " + str(candidates) + ")")
		var placeholder = _get_placeholder()
		_cache[icon_name] = placeholder
		return placeholder
	else:
		_cache[icon_name] = null
		return null

## 专门给可能没有图的资源（如对话头像）用，找不到返回 null，不显示占位图
static func get_icon_or_null(icon_name: String) -> Texture2D:
	return get_icon(icon_name, false)

# --- 内部方法 ---
static func _get_candidate_paths(icon_name: String) -> Array[String]:
	var paths: Array[String] = []
	
	# 1. 绝对路径
	if icon_name.begins_with("res://"):
		paths.append(icon_name)
		if not icon_name.get_extension():
			paths.append(icon_name + ".png")
		return paths
		
	var has_ext = icon_name.get_extension() != ""
	var add_ext = "" if has_ext else ".png"
	
	# 2. 包含斜杠：视为相对于 images/ 的路径
	if icon_name.contains("/"):
		paths.append(IMAGE_ROOT + icon_name + add_ext)
		return paths
		
	# 3. 纯文件名：按优先级搜索各个常用目录
	paths.append(IMAGE_ROOT + "item/" + icon_name + add_ext)
	paths.append(IMAGE_ROOT + "characters/avatar/" + icon_name + add_ext)
	paths.append(IMAGE_ROOT + "sanctuary/" + icon_name + add_ext)
	paths.append(IMAGE_ROOT + "ui/" + icon_name + add_ext)
	paths.append(IMAGE_ROOT + icon_name + add_ext)
	
	return paths

static func _get_placeholder() -> Texture2D:
	if _placeholder == null:
		var img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color.MAGENTA) 
		_placeholder = ImageTexture.create_from_image(img)
	return _placeholder
