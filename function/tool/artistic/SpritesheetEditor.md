# SpritesheetEditor 使用说明 / User Guide

面向像素精灵表/多帧动画的编辑器。支持多图层、选区、套索、裁切、动画预览、色板、参考线等。

A pixel sprite-sheet / frame animation editor supporting multiple layers, selection, lasso, crop, animation preview, palettes, guides.

---

## 文件与工程 / File & Project

**中文**

- **新建…**：输入宽高创建新画布。
- **打开 PNG**：打开一张图片作为背景层。
- **打开工程**：打开 `.pxproj` 工程文件（JSON 格式，含图层、网格、参考线、动画设置等）。
- **保存 PNG**：导出当前合成结果为 PNG。
- **另存为 PNG…**：选择路径导出。
- **保存工程 / 另存为工程…**：保存为 `.pxproj`，保留图层、网格、参考线、色板、动画参数等。
- **拖拽图片到窗口**：直接打开为背景层。

**English**

- **New…**: create a new canvas with given width/height.
- **Open PNG**: open an image as a background layer.
- **Open Project**: open a `.pxproj` project file (JSON containing layers, grid, guides, animation settings, etc.).
- **Save PNG**: export current composite as PNG.
- **Save As PNG…**: export with a chosen path.
- **Save Project / Save As Project…**: save as `.pxproj`, preserving layers, grid, guides, palettes, animation params.
- **Drag & drop an image**: opens it as a background layer.

---

## 工具 / Tools

**中文**

| 按钮 | 快捷键 | 说明 |
|------|--------|------|
| Sel | `V` | 矩形选择 |
| Lasso | `M` | 套索选择 |
| Pen | `B` | 铅笔 |
| Era | `E` | 橡皮 |
| Pick | `I` | 吸管 |
| Fill | `G` | 油漆桶 |
| Rep | `J` | 替换颜色 |

- 数字键 `1`–`7` 也可快速切换工具。
- 按住 `V` 或 `M` 拖动选区内可仅移动选区；直接拖动选区内会浮起像素并移动（`Shift` 锁定水平/垂直）。
- 按住 `R` 并移动鼠标可围绕选区中心旋转（`Shift` 按 45° 步进）。
- `C` 键或工具栏「Crop」按钮可裁切到选区。

**English**

| Button | Shortcut | Description |
|--------|----------|-------------|
| Sel | `V` | Rectangle selection |
| Lasso | `M` | Lasso selection |
| Pen | `B` | Pencil |
| Era | `E` | Eraser |
| Pick | `I` | Eyedropper |
| Fill | `G` | Bucket fill |
| Rep | `J` | Replace color |

- Number keys `1`–`7` also switch tools quickly.
- Hold `V` or `M` and drag inside a selection to move only the selection; directly drag inside to float & move pixels (`Shift` locks to one axis).
- Hold `R` and move the mouse to rotate around the selection center (`Shift` steps by 45°).
- Press `C` or the toolbar "Crop" button to crop to selection.

---

## 裁切到选区 / Crop to Selection

**中文**

- **触发方式**：工具栏「Lasso」右侧的「Crop」按钮，键盘 `C`，或编辑菜单「Crop to Selection」。
- **条件**：必须有有效选区。
- **弹窗**：显示原尺寸、裁切后尺寸、选区位置，确认后执行。
- **效果**：所有图层同步裁切，画布尺寸变为选区大小，选区清空。
- **撤销**：裁切写入历史，`Ctrl+Z` 可撤销，`Ctrl+Shift+Z` / `Ctrl+Y` 重做。

**English**

- **Triggers**: toolbar "Crop" (right of Lasso), key `C`, or Edit menu "Crop to Selection".
- **Requirement**: a valid selection must exist.
- **Dialog**: shows original size, cropped size, and selection region; confirm to run.
- **Effect**: all layers are cropped together; canvas becomes the selection size; selection is cleared.
- **Undo**: crop is written to history; `Ctrl+Z` undo, `Ctrl+Shift+Z` / `Ctrl+Y` redo.

---

## 变换 / Transform

**中文**

- **旋转 90° 逆时针 / 顺时针 / 180°**：对选区内容（浮动像素）旋转，或先浮起选区再旋转。
- **水平翻转 / 垂直翻转**：同上。

**English**

- **Rotate 90° CCW / CW / 180°**: rotate selection content (floating pixels), or float the selection first.
- **Flip Horizontal / Vertical**: same as above.

---

## 动画预览 / Animation Preview

**中文**

- **预览窗口**：显示当前图片，黄色框标记当前帧。
- **点击预览**：切换当前帧。
- **播放 / 停止**：按设定 FPS 播放动画。
- **起始 / 结束**：帧范围。
- **FPS**：播放速度。
- **循环**：是否循环播放。
- **全范围**：将范围设为 0 到最大帧。
- **洋葱皮**：可显示前一帧（红）和后一帧（蓝），透明度可调。
- **逐帧快捷键**：`←` / `→` 或 `A` / `D` 切换帧，长按连续播放，松开停止。
- **空格**：短按播放/暂停；按住空格 + 拖动可平移画布。

**English**

- **Preview window**: shows current image; yellow box marks current frame.
- **Click preview**: switch current frame.
- **Play / Stop**: play animation at set FPS.
- **Start / End**: frame range.
- **FPS**: playback speed.
- **Loop**: whether to loop.
- **Full Range**: set range to 0..max.
- **Onion skin**: show previous frame (red) and next frame (blue), opacity adjustable.
- **Frame stepping**: `←` / `→` or `A` / `D` switches frames; hold for continuous, release to stop.
- **Space**: short press plays/pauses; hold Space + drag to pan.

---

## 颜色 / Color

**中文**

- **主色 / 辅色**：点击色块打开颜色选择器。
- **颜色选择器**：SV 面板、色相条、HEX、RGB 输入、屏幕取色（EyeDropper，若不支持则点击画布取色）。
- **全图替换**：将主色替换为辅色。

**English**

- **Primary / Secondary**: click a chip to open the color picker.
- **Color picker**: SV panel, hue bar, HEX, RGB inputs, screen eyedropper (falls back to canvas click if EyeDropper is unsupported).
- **Replace All**: replace primary with secondary across the image.

---

## 色板 / Palettes

**中文**

- **NES 色板**：只读，左键设为主色，右键设为辅色。
- **自定义色板**：
  - 左键设为主色。
  - 中键删除该色。
  - 添加：将当前主色加入。
  - 重置：恢复默认 16 色。
  - 载入 / 保存：JSON 文件导入导出。

**English**

- **NES Palette**: read-only; left-click sets primary, right-click sets secondary.
- **Custom Palette**:
  - Left-click sets primary.
  - Middle-click removes that color.
  - Add: add current primary.
  - Reset: restore default 16 colors.
  - Load / Save: import/export as a JSON file.

---

## 图层 / Layers

**中文**

- **新建 / 复制 / 删除**：操作图层。
- **上移 / 下移**：调整顺序。
- **合并向下**：将当前图层合并到下一层。
- **拼合可见**：将所有可见图层合并为一层。
- **粘贴为新图层**：粘贴剪贴板图片为新图层（`Ctrl+Shift+V`）。
- **拖动排序**：直接拖动图层项。
- **重命名**：双击图层名。
- **显示 / 隐藏**：点击眼睛图标。

**English**

- **New / Duplicate / Delete**: manage layers.
- **Up / Down**: reorder.
- **Merge Down**: merge current layer into the one below.
- **Flatten**: merge all visible layers into one.
- **Paste as Layer**: paste clipboard image as a new layer (`Ctrl+Shift+V`).
- **Drag to reorder**: drag layer items directly.
- **Rename**: double-click the layer name.
- **Show / Hide**: click the eye icon.

---

## 参考线与吸附 / Guides & Snap

**中文**

- **创建参考线**：从顶部标尺往下拖 → 水平参考线；从左侧标尺往右拖 → 垂直参考线。
- **移动参考线**：按住 `Ctrl` 并靠近参考线拖动。
- **删除参考线**：双击参考线。
- **吸附**：开启后参考线和选区会吸附到格子边沿/中心。
- **显示 / 隐藏**：按钮切换。
- **清空**：删除所有参考线。

**English**

- **Create guide**: drag from the top ruler down → horizontal guide; from the left ruler right → vertical guide.
- **Move guide**: hold `Ctrl` and drag near the guide.
- **Delete guide**: double-click a guide.
- **Snap**: guides and selection snap to grid edges/centers.
- **Show / Hide**: toggle via the button.
- **Clear**: delete all guides.

---

## 图片色板 / Image Palette

**中文**

- **刷新**：统计当前合成图中所有颜色及像素数。
- **点击色块**：在画布上高亮该颜色，再次点击取消。
- **对比 NES**：（占位功能，当前无操作）

**English**

- **Refresh**: count all colors in current composite and their pixel counts.
- **Click swatch**: highlight that color on the canvas; click again to cancel.
- **Compare NES**: (placeholder, no action currently)

---

## 选区 / Selection

**中文**

- **模式**：新建 / 加选 / 减选。
- **全选 / 取消 / 反选 / 选格 / 删除**：快捷按钮。
- **移动选区**：按住 `V` 或 `M` 在选区内拖动（仅移动选区）。
- **浮起像素移动**：直接拖动选区内（默认替换模式），像素浮起并可移动，`Shift` 锁定轴。
- **旋转浮起像素**：按住 `R` 并移动鼠标。
- **裁切到选区**：`C` 或工具栏按钮。

**English**

- **Modes**: Replace / Add / Subtract.
- **All / None / Invert / Cell / Del**: quick buttons.
- **Move selection**: hold `V` or `M` and drag inside (selection only).
- **Float & move pixels**: directly drag inside (Replace mode); pixels float and can move, `Shift` locks axis.
- **Rotate floating pixels**: hold `R` and move mouse.
- **Crop to selection**: `C` or toolbar button.

---

## 视图 / View

**中文**

- **缩放**：`+` / `-` 按钮、滚轮、适应窗口。
- **单格 / 全图**：切换显示当前格或整张图。
- **背景**：白底 / 灰底 / 黑底 / 格子循环。
- **标尺**：顶部和左侧显示像素坐标。

**English**

- **Zoom**: `+` / `-` buttons, wheel, Fit.
- **Single / Full**: toggle current cell or full sheet.
- **Background**: cycle White / Gray / Black / Checker.
- **Rulers**: pixel coordinates at top and left.

---

## 快捷键总览 / Keyboard Shortcuts

**中文**

| 快捷键 | 功能 |
|--------|------|
| `V` / `M` / `B` / `E` / `I` / `G` / `J` | 切换工具 |
| `1`–`7` | 切换工具 |
| `C` | 裁切到选区 |
| `R` + 鼠标移动 | 旋转浮起像素 |
| `空格` | 播放 / 暂停 |
| `空格` + 拖动 | 平移画布 |
| `←` / `→` / `A` / `D` | 逐帧切换 |
| `Ctrl+Z` / `Ctrl+Shift+Z` / `Ctrl+Y` | 撤销 / 重做 |
| `Ctrl+A` / `Ctrl+D` / `Ctrl+I` | 全选 / 取消 / 反选 |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | 复制 / 剪切 / 粘贴 |
| `Ctrl+Shift+V` | 粘贴为新图层 |
| `Ctrl+S` | 保存 PNG |
| `Delete` / `Backspace` | 删除选中像素 |
| `F` | 适应窗口 |
| `Esc` | 取消当前操作 / 关闭弹窗 |
| 方向键（有浮动像素时） | 移动浮动像素 |

**English**

| Shortcut | Action |
|----------|--------|
| `V` / `M` / `B` / `E` / `I` / `G` / `J` | Switch tools |
| `1`–`7` | Switch tools |
| `C` | Crop to selection |
| `R` + mouse move | Rotate floating pixels |
| `Space` | Play / pause |
| `Space` + drag | Pan canvas |
| `←` / `→` / `A` / `D` | Frame step |
| `Ctrl+Z` / `Ctrl+Shift+Z` / `Ctrl+Y` | Undo / Redo |
| `Ctrl+A` / `Ctrl+D` / `Ctrl+I` | Select All / Deselect / Invert |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | Copy / Cut / Paste |
| `Ctrl+Shift+V` | Paste as new layer |
| `Ctrl+S` | Save PNG |
| `Delete` / `Backspace` | Delete selected pixels |
| `F` | Fit to window |
| `Esc` | Cancel op / close dialog |
| Arrow keys (with floating pixels) | Move floating pixels |

---

## 状态栏 / Status Bar

**中文**

- 左侧显示操作提示与反馈。
- 右侧显示鼠标像素坐标和当前格索引。

**English**

- Left side shows operation hints and feedback.
- Right side shows mouse pixel coordinates and current cell index.