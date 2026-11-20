extends Node

# ============================================================
#  配置
# ============================================================

## 全局最低输出级别（低于此级别不输出）
## 0=DEBUG, 1=INFO, 2=WARN, 3=ERROR, 4=OFF
enum Level { DEBUG, INFO, WARN, ERROR, OFF }

## 正式发布时改为 Level.INFO 或 Level.WARN
const MIN_LEVEL : Level = Level.DEBUG

## 是否给输出加时间戳前缀
const WITH_TIMESTAMP : bool = true

## 是否输出到文件（user://logs/godot_YYYYMMDD.log）
const WRITE_TO_FILE : bool = false

# ============================================================
#  内部状态
# ============================================================
var _file : FileAccess = null

# ============================================================
#  生命周期
# ============================================================
func _ready():
	if WRITE_TO_FILE:
		_open_log_file()

func _exit_tree():
	if _file:
		_file.close()
		_file = null

# ============================================================
#  公开 API
# ============================================================

func debug(msg: String, tag: String = ""):
	_log(Level.DEBUG, "DEBUG", msg, tag)

func info(msg: String, tag: String = ""):
	_log(Level.INFO, "INFO ", msg, tag)

func warn(msg: String, tag: String = ""):
	_log(Level.WARN, "WARN ", msg, tag)

func error(msg: String, tag: String = ""):
	_log(Level.ERROR, "ERROR", msg, tag)

# ============================================================
#  内部实现
# ============================================================
func _log(level: Level, level_str: String, msg: String, tag: String):
	if level < MIN_LEVEL:
		return

	var prefix := ""
	if WITH_TIMESTAMP:
		prefix += "[" + _timestamp() + "] "
	prefix += "[" + level_str + "]"
	if tag != "":
		prefix += "[" + tag + "]"

	var line := prefix + " " + msg
	print(line)

	if WRITE_TO_FILE and _file:
		_file.store_line(line)

func _timestamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%02d:%02d:%02d" % [t.hour, t.minute, t.second]

func _open_log_file():
	var date_str := Time.get_date_string_from_system()
	var path := "user://logs/godot_%s.log" % date_str

	DirAccess.make_dir_recursive_absolute("user://logs/")
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning("Logger: 无法打开日志文件 " + path)
