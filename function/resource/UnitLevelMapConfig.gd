extends Resource
class_name UnitLevelMapConfig

@export var default_entry: UnitLevelMapEntry      # 默认条目（当未找到单位时使用）
@export var entries: Array[UnitLevelMapEntry] = []  # 可添加多个单位条目
