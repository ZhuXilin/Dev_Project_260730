# SpritesheetEditor · 像素图 / Sprite Sheet 编辑器

纯前端的像素图编辑器，支持精灵图切分、逐帧动画预览、图层编辑、变换（旋转/翻转）、NES 色板对比等。

A pure front-end pixel art & sprite sheet editor. Supports sprite slicing, animation preview, layers, transform (rotate/flip), NES palette comparison and more.

> [中文](#中文文档) ｜ [English](#english-documentation)

---

## 中文文档

### 一、简介

SpritesheetEditor 是一款浏览器内的像素图编辑器，专为像素艺术家和独立游戏开发者设计。可直接打开 PNG 精灵图，按网格切分单元格，逐格编辑、预览动画、自由旋转/翻转，并利用内置的 NES 色板进行复古风格创作。

无需安装，双击 HTML 文件即可使用。默认英文界面，可一键切换中文。

### 二、快速开始

1. 用浏览器打开 `SpritesheetEditor.html`。
2. 通过 `文件 ▾ → 打开 PNG…`、`打开工程…` 或直接拖入 PNG 载入图片。
3. 在右侧「网格 / 分格」中设置格宽/格高（或列数/行数）。
4. 用顶部工具编辑像素；在「变换」中旋转或翻转选区。
5. 「动画预览」区域点击格可快速定位，按 `←` `→` 或 `A` `D` 逐帧查看。
6. 完成后 `另存 PNG` 导出图像，或 `另存工程` 保存为 `.pxproj`。

### 三、界面说明

**顶部工具栏（从左到右）**
- `文件 ▾` / `编辑 ▾`：下拉菜单。
- `打开 PNG` / `打开工程` / `另存 PNG` / `另存工程`。
- 工具按钮：选、套、笔、擦、吸、桶、换（详见下表）。
- `撤销` / `重做`。
- 缩放：`－` / `＋` / `适应`。
- 背景切换：`白底 / 灰底 / 黑底 / 格子`。
- `单格 / 全图`：视图模式切换。
- `CH / EN`：语言切换（右上角）。

**右侧边栏**

| 区块 | 说明 |
| --- | --- |
| 网格 / 分格 | 格宽、格高、列数、行数；分格网格与像素格开关 |
| 变换 | ⟲90 / ⟳90 / ↻180 / ↔ / ↕ |
| 动画预览 | 缩略图 + 可点击定位格；起始/结束帧、FPS、循环、播放/停止；洋葱皮（前帧/后帧） |
| 颜色 | 主色、辅色、全图替换 |
| NES 色板 | 只读 NTSC 2C02 色板 |
| 自定义色板 | 增删 / 载入 / 保存 JSON |
| 图层 | 新建/复制/删除/上移/下移/合并/拼合 |
| 参考线 / 吸附 | 从标尺拖出参考线；开关吸附 |
| 图片色板 | 统计图片实际颜色；高亮某色；对比 NES |
| 选区 | 模式、全选/取消/反选/选格/删除 |

### 四、工具详解

| 工具 | 快捷键 | 说明 |
| --- | --- | --- |
| 选择 | `V` / `1` | 框选矩形区域；拖动选区内可移动像素 |
| 套索 | `M` / `7` | 自由绘制选区；`Shift` 拖出正圆 |
| 铅笔 | `B` / `2` | 逐像素绘制；`Alt` + 点击吸色 |
| 橡皮 | `E` / `3` | 将像素变为透明 |
| 吸管 | `I` / `5` | 从画布取色 |
| 油漆桶 | `G` / `4` | 同色填充；`Alt` + 点击吸色 |
| 替换色 | `J` / `6` | 替换图中所有该色为主色 |

**笔刷大小**：`[` 减小，`]` 增大。

### 五、选区与移动

- 用「选择」工具拖拽出矩形选区。
- **`Shift`** = 正方形 / 正圆套索。
- **`Ctrl`** = 加选，**`Alt`** = 减选。
- **普通拖动**选区内 → 浮起像素并跟随鼠标移动（`Shift` 锁定水平/垂直）。
- **按住 `V` 或 `M` 再拖动**选区内 → **只移动选区**，不移动像素。
- **方向键**：每按一次移动浮动像素 1 像素；长按连续移动。
- `Ctrl+C` / `Ctrl+X` / `Ctrl+V` / `Ctrl+Shift+V`：复制 / 剪切 / 粘贴 / 粘贴为新图层。
- 右键：取消选择 / 取色。

### 六、变换（旋转 / 翻转）

**按钮变换**（作用于当前选区，自动浮动）：
- `⟲90` 逆时针 90°
- `⟳90` 顺时针 90°
- `↻180` 旋转 180°
- `↔` 水平翻转
- `↕` 垂直翻转

**鼠标自由旋转**：
1. 先做出选区（或已有浮动像素）。
2. **按住 `R` 键**不放，此时画布出现虚线圆和十字准心（选区中心）。
3. 移动鼠标 → 围绕选区中心自由旋转。
4. 配合 `Shift` → 每 45° 吸附一次。
5. 松开 `R` → 提交旋转并写入历史。

> 关键点：0° 是**按住 R 的那一刻鼠标角度**，不是上次旋转角度。每次按下 R 都会重新取基准。

### 七、动画预览

1. 在「动画预览」区域点击任意单元格 → 定位到该帧。
2. 设置 `起始` 与 `结束` 帧。**起始必须 < 结束**，输入时会自动纠正。
3. 设置 `FPS` 并勾选 `循环`。
4. 手动逐帧：
   - `←` 或 `A`：前一帧
   - `→` 或 `D`：后一帧
   - 长按可连续播放，松开停住
   - 遵守「循环」复选框：勾选后到首/尾自动回卷
5. `空格`：自动播放 / 暂停（与手动逐帧独立）。
6. 勾选 `前帧` / `后帧` 可开启洋葱皮，滑动条调整不透明度。

> 若当前有浮动像素，`←` `→` 会优先用于**移动浮动像素**；此时想切换帧请用 `A` / `D`。

### 八、图层

- 双击图层名可重命名。
- 点击眼睛图标切换可见性。
- 拖动图层可重新排序（顶部为上）。
- `合并 ↓`：当前层合并到下一层。
- `拼合可见`：所有可见图层合并为单层。
- `粘贴为新图层`：`Ctrl+Shift+V`。

### 九、参考线与吸附

- 顶部标尺往下拖 → 水平参考线。
- 左侧标尺往右拖 → 垂直参考线。
- `Ctrl` + 靠近参考线拖动 → 移动参考线。
- 拖动时自动吸附到格子边沿 / 中心。
- **双击参考线** → 删除。
- 选区终点会吸附到邻近参考线（起点不吸附）。
- 隐藏参考线后不吸附、不可拖动。

### 十、图片色板与 NES 对比

- 点击 `刷新` 统计图片实际使用的颜色。
- 点击色块 → 高亮图中该颜色的所有像素（再次点击取消）。
- 点击 `对比 NES` 弹出模态框：
  - ✅ 在 NES 色板中的颜色及其索引、像素数。
  - ❌ 不在 NES 色板中的颜色，附最近 NES 色（含 RGB 欧氏距离）。

### 十一、快捷键速查表

| 快捷键 | 功能 |
| --- | --- |
| `V` / `M` / `B` / `E` / `I` / `G` / `J` | 切换工具 |
| `1` ~ `7` | 切换工具 |
| `[` / `]` | 减小 / 增大笔刷 |
| `R` + 鼠标移动 | 围绕选区中心旋转 |
| `R` + `Shift` | 45° 整数旋转 |
| `←` / `→` / `A` / `D` | 动画逐帧（长按连续） |
| `空格` | 播放 / 暂停动画 |
| `F` | 适应窗口 |
| `空格 + 左键拖动` 或 中键拖动 | 平移 |
| 滚轮 | 缩放 |
| `Ctrl+Z` / `Ctrl+Shift+Z` / `Ctrl+Y` | 撤销 / 重做 |
| `Ctrl+A` / `Ctrl+D` / `Ctrl+I` | 全选 / 取消 / 反选 |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | 复制 / 剪切 / 粘贴 |
| `Ctrl+Shift+V` | 粘贴为新图层 |
| `Ctrl+S` | 保存 PNG |
| `Delete` / `Backspace` | 删除选中像素 |
| `←` `→` `↑` `↓` | 移动浮动像素（无浮动时切换动画帧） |
| `Esc` | 取消当前操作 / 取消选择 |

### 十二、工程文件（.pxproj）

「另存工程」导出 JSON 格式的 `.pxproj`，包含：
- 画布尺寸、图层数据（PNG Base64）
- 网格与参考线
- 动画起止帧、FPS、循环、洋葱皮状态
- 自定义色板、主/辅色、笔刷大小

再次打开工程即可恢复完整编辑状态。

### 十三、常见问题

**Q：为什么像素格网格在单格模式下看不到？**
A：像素格仅在缩放 ≥ 400% 时显示。放大视图即可。

**Q：动画快捷键按了没反应？**
A：请确认已打开图片（PNG 或工程）。若鼠标焦点停留在输入框中，快捷键不会生效。若当前有浮动像素，`←` `→` 会移动浮动像素，请用 `A` / `D` 切帧。

**Q：能不能导出 GIF？**
A：暂不支持。可用「另存 PNG」导出整张精灵图，再用其他工具打包为 GIF。

**Q：撤销栈有限制吗？**
A：最多 60 步。可通过源码中的 `HISTORY_MAX` 调整。

---

## English Documentation

### 1. Introduction

SpritesheetEditor is a browser-based pixel art editor designed for pixel artists and indie game developers. It opens PNG sprite sheets, slices them into grid cells, lets you edit frame by frame with live animation preview, supports free rotate/flip, and provides a built-in NES palette.

No installation needed — just open the HTML file. Default language is English, with one-click switch to Chinese.

### 2. Quick Start

1. Open `SpritesheetEditor.html` in any modern browser.
2. Use `File ▾ → Open PNG…`, `Open Project…`, or drag & drop a PNG.
3. In "Grid / Cells", set cell width/height (or columns/rows).
4. Edit pixels using the tools; use "Transform" to rotate or flip selections.
5. Click a cell in "Animation" to jump to a frame; press `←` `→` or `A` `D` to step.
6. Export with `Save As PNG`, or `Save As Project` (`.pxproj`).

### 3. Interface

**Toolbar (left to right)**
- `File ▾` / `Edit ▾` menus.
- `Open PNG` / `Open Project` / `Save As PNG` / `Save As Project`.
- Tools: Select, Lasso, Pencil, Eraser, Picker, Bucket, Replace.
- `Undo` / `Redo`.
- Zoom: `−` / `+` / `Fit`.
- Background cycle: White / Gray / Black / Checker.
- `Single / Full` view toggle.
- `CH / EN` language toggle.

**Sidebar**

| Section | Description |
| --- | --- |
| Grid / Cells | Cell W/H, cols/rows, cell grid & pixel grid toggles |
| Transform | ⟲90 / ⟳90 / ↻180 / ↔ / ↕ |
| Animation | Thumbnail + clickable cell locator; start/end, FPS, loop, play/stop; onion skin |
| Color | Primary, secondary, replace-all |
| NES Palette | Read-only NTSC 2C02 palette |
| Custom Palette | Add / remove / load / save JSON |
| Layers | New / Duplicate / Delete / Move / Merge / Flatten |
| Guides / Snap | Drag guides from rulers; toggle snapping |
| Image Palette | Count colors; highlight a color; compare against NES |
| Selection | Modes, Select All, Invert, Select Cell, Delete |

### 4. Tools

| Tool | Shortcut | Description |
| --- | --- | --- |
| Select | `V` / `1` | Rectangular selection; drag inside to move pixels |
| Lasso | `M` / `7` | Freeform selection; `Shift` for a circle |
| Pencil | `B` / `2` | Draw per-pixel; `Alt` + click to pick |
| Eraser | `E` / `3` | Erase pixels to transparent |
| Picker | `I` / `5` | Pick color from canvas |
| Bucket | `G` / `4` | Flood fill; `Alt` + click to pick |
| Replace | `J` / `6` | Replace clicked color with primary |

**Brush size**: `[` smaller, `]` larger.

### 5. Selection & Moving

- Drag with Select tool to make a rectangular selection.
- **`Shift`** = square selection / circle lasso.
- **`Ctrl`** = add, **`Alt`** = subtract.
- **Normal drag inside** → float pixels and move them (`Shift` locks axis).
- **Hold `V` or `M` and drag** inside → move **selection only**.
- **Arrow keys**: move floating pixels 1px per press, hold for continuous.
- `Ctrl+C` / `Ctrl+X` / `Ctrl+V` / `Ctrl+Shift+V`: copy / cut / paste / paste as new layer.
- Right-click: deselect / pick.

### 6. Transform (Rotate / Flip)

**Button transform** (applies to selection, auto-floats):
- `⟲90` 90° CCW
- `⟳90` 90° CW
- `↻180` 180°
- `↔` Flip Horizontal
- `↕` Flip Vertical

**Free mouse rotate**:
1. Make a selection (or have a floating layer).
2. **Hold `R`** — a dashed circle and crosshair appear at the selection center.
3. Move the mouse → the floating layer rotates around that center.
4. Hold `Shift` → snaps to 45° increments.
5. Release `R` → commit rotation to history.

> The 0° reference is **the mouse angle at the moment you press R**, not the previous rotation.

### 7. Animation Preview

1. Click any cell in the preview area to jump to that frame.
2. Set `Start` and `End` frames. **Start must be < End**; invalid input is auto-corrected.
3. Set `FPS` and check `Loop`.
4. Manual stepping:
   - `←` or `A` → previous frame
   - `→` or `D` → next frame
   - Hold for continuous play, release to stop
   - Respects the `Loop` checkbox (wraps at ends if enabled)
5. `Space` → auto play / pause (independent of manual stepping).
6. Enable `Prev` / `Next` for onion skinning; slider adjusts opacity.

> If there is a floating layer, `←` `→` will move it instead; use `A` / `D` to switch frames.

### 8. Layers

- Double-click a name to rename.
- Click the eye icon to toggle visibility.
- Drag layers to reorder (top = front).
- `Merge Down`: merge into layer below.
- `Flatten`: merge all visible layers into one.
- `Paste as Layer`: use `Ctrl+Shift+V`.

### 9. Guides & Snapping

- Drag down from top ruler → horizontal guide.
- Drag right from left ruler → vertical guide.
- Hold `Ctrl` and drag near a guide → move it.
- Auto-snaps to cell edges / centers.
- **Double-click** a guide → delete.
- Selection endpoint snaps to nearby guides (start point does not).
- When hidden, guides are neither snappable nor draggable.

### 10. Image Palette & NES Comparison

- Click `Refresh` to count colors used.
- Click a swatch → highlight all pixels of that color (click again to cancel).
- Click `Compare NES` to open a modal:
  - ✅ Colors in the NES palette (with index & pixel count).
  - ❌ Colors not in the palette, each with the nearest NES color and RGB distance.

### 11. Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `V` / `M` / `B` / `E` / `I` / `G` / `J` | Switch tools |
| `1` – `7` | Switch tools |
| `[` / `]` | Decrease / increase brush size |
| `R` + move mouse | Rotate around selection center |
| `R` + `Shift` | Snap rotation to 45° |
| `←` / `→` / `A` / `D` | Step animation frames (hold = continuous) |
| `Space` | Play / pause animation |
| `F` | Fit to view |
| `Space + drag` or middle-drag | Pan |
| Mouse wheel | Zoom |
| `Ctrl+Z` / `Ctrl+Shift+Z` / `Ctrl+Y` | Undo / Redo |
| `Ctrl+A` / `Ctrl+D` / `Ctrl+I` | Select All / Deselect / Invert |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | Copy / Cut / Paste |
| `Ctrl+Shift+V` | Paste as new layer |
| `Ctrl+S` | Save PNG |
| `Delete` / `Backspace` | Delete selected pixels |
| `←` `→` `↑` `↓` | Move floating pixels (or step frames if none) |
| `Esc` | Cancel current action / deselect |

### 12. Project Files (.pxproj)

"Save As Project" exports a JSON `.pxproj` containing:
- Canvas size, layer data (PNG Base64)
- Grid & guides
- Animation start/end, FPS, loop, onion skin
- Custom palette, primary/secondary colors, brush size

Re-opening the project restores the complete editing state.

### 13. FAQ

**Q: Why is the pixel grid not visible in single-cell view?**
A: Pixel grid appears only when zoom ≥ 400%. Zoom in further.

**Q: Animation shortcuts don't work?**
A: Make sure an image is loaded (PNG or project). If focus is in an input field, shortcuts are ignored. If a floating layer exists, `←` `→` moves it — use `A` / `D` to switch frames.

**Q: GIF export?**
A: Not supported. Use "Save As PNG" then pack with another tool.

**Q: Undo limit?**
A: Up to 60 steps. Modify `HISTORY_MAX` in the source to change.