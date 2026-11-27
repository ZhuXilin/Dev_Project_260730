# 项目长期约定（Godot Dev_Project_260730）

## 引擎设置：绝不用代码兜底硬编码
- **规则**：凡是引擎资源/节点的属性设置（StyleBox 的 margin/axis_stretch、UI 布局、颜色、纹理参数等），一律交给 Godot 编辑器/检查器（Inspector）配置，写进 `.tres`/`.tscn`，**不要用代码在运行时兜底覆盖**。
- **原因**：代码兜底会静默覆盖 Inspector 里的调整，表现为"我改了但不生效"，排查成本极高（v6.72af 就踩过：Config.gd:_ready 强制 margin 5/8/5/8，覆盖了用户在 Inspector 设的 9/9/9/9 + Tile）。
- **反过来**：如果 Inspector 改了不生效，第一反应是查有没有代码在运行时改同一属性，而不是继续调参数。
- 资源单例缓存：`load()` 同一路径返回同一实例，代码里改属性会全局生效——所以尤其不能在代码里随手改资源属性。

## 美术素材：不许擅自重新生成
- **规则**：任何图片/资源（`*.png`、`*.tres` 等）在"重新生成 / 修色 / 覆盖"之前，先看 mtime、先问用户——**用户手改过的素材以用户版本为准，不要按旧规则重刷**（v6.72ap 事故：用户手改的 `8bit_frame_button.png` 被我按旧配色覆盖，旧 ctex 被 Godot 重导入清掉、git untracked，原图不可恢复）。
- 曾经的"必改配色"之类的规则若与用户手改冲突，一律以用户当前文件为准，先确认再动。

## 9-slice 边框（8bit_style_box_texture.tres）
- 源图 `8bit_frame.png` 保持 22×22，**用户明确不要放大分辨率**；编织装饰纹要保留。
- 9-slice 参数全部在 `.tres` 里配（texture_margin / axis_stretch Tile / region_rect），由用户在 Inspector 调整，代码不介入。
- Godot 4 的 StyleBoxTexture 9-slice 属性名是 `texture_margin_*`（不是 `patch_margin_*`，那是 NinePatchRect）。

## 头像列表
- 所有头像按钮走 `UnitDataManager.create_unit_avatar_button` / `create_unit_avatar_with_frame`；头像下不垫任何 UI 块（v6.72z 已删画框 Panel）。
- 对话/信息面板的 AvatarBg 用内联 `StyleBoxEmpty` 显式透明（删 style override 会回退 Godot 默认灰底）。
