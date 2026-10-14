# SpritesheetEditor · 像素图 / Sprite Sheet 编辑器

一个纯前端的像素图编辑器，支持精灵图切分、逐帧动画预览、图层编辑、NES 色板对比等功能。

A pure front-end pixel art & sprite sheet editor. Supports sprite slicing, frame-by-frame animation preview, layers, NES palette comparison and more.

> [中文](#中文文档) ｜ [English](#english-documentation)

---

## 中文文档

### 一、简介

SpritesheetEditor 是一款浏览器内的像素图编辑器，专为像素艺术家和独立游戏开发者设计。它可以直接打开 PNG 精灵图，按网格切分单元格，逐格编辑、预览动画，并利用内置的 NES 色板进行复古风格创作。

无需安装，双击 HTML 文件即可使用。默认英文界面，可一键切换中文。

### 二、快速开始

1. 用浏览器打开 `SpritesheetEditor.html`。
2. 通过 `文件 ▾ → 打开 PNG…` 或直接拖入 PNG 文件载入图片。
3. 在右侧「网格 / 分格」中设置格宽/格高（或列数/行数），把整张精灵图切分为单元格。
4. 用顶部工具（铅笔、橡皮、油漆桶等）编辑像素。
5. 「动画预览」区域可点击单元格进行快速定位，按 `播放` 预览逐帧动画。
6. 完成后 `另存 PNG` 导出图像，或 `另存工程` 保存为 `.pxproj` 以便后续继续编辑。

### 三、界面说明

**顶部工具栏（从左到右）**
- `文件 ▾` / `编辑 ▾`：下拉菜单。
- `打开 PNG` / `打开工程` / `另存 PNG` / `另存工程`：快捷文件操作。
- 工具按钮：选、套、笔、擦、吸、桶、换（详见下表）。
- `撤销` / `重做`。
- 缩放：`－` / `＋` / `适应`。
- 背景切换：`白底 / 灰底 / 黑底 / 格子` 循环切换。
- `单格 / 全图`：切换视图模式。
- `CH / EN`：语言切换按钮（右上角）。

**右侧边栏**

| 区块 | 说明 |
| --- | --- |
| 网格 / 分格 | 设置格宽、格高、列数、行数；显示/隐藏分格网格与像素格 |
| 动画预览 | 缩略图 + 可拖拽定位格；起始/结束帧、FPS、循环、播放/停止 |
| 颜色 | 主色、辅色、全图替换 |
| NES 色板 | 只读的 NTSC 2C02 色板（64 色） |
| 自定义色板 | 可增删、载入、保存 JSON |
| 图层 | 新建/复制/删除/上移/下移/合并/拼合 |
| 参考线 / 吸附 | 从标尺拖出参考线；开关吸附 |
| 图片色板 | 统计图片实际用到的颜色，可对比 NES 色板 |
| 选区 | 选区模式、全选、反选、选当前格、删除像素 |

### 四、工具详解

| 工具 | 快捷键 | 说明 |
| --- | --- | --- |
| 选择 | `V` / `1` | 框选矩形区域；拖动选区内可移动像素 |
| 套索 | `M` / `7` | 自由绘制选区；`Shift` 拖出正圆 |
| 铅笔 | `B` / `2` | 逐像素绘制；`Alt` + 点击吸色 |
| 橡皮 | `E` / `3` | 将像素变为透明 |
| 吸管 | `I` / `5` | 从画布取色 |
| 油漆桶 | `G` / `4` | 同色填充；`Alt` + 点击吸色 |
| 替换色 | `J` / `6` | 将图中所有该色替换为主色 |

**笔刷大小**：`[` 减小、`]` 增大。

### 五、选区与移动

- 用「选择」工具拖拽出矩形选区。
- **`Shift`** = 正方形选区 / 正圆套索。
- **`Ctrl`** = 加选，**`Alt`** = 减选。
- **普通拖动**选区内 → 浮起像素并跟随鼠标移动（`Shift` 可锁定水平/垂直轴向）。
- **按住 `V` 或 `M` 再拖动**选区内 → **只移动选区**，不移动像素。
- **方向键**：每按一次移动浮动像素 1 像素；长按可连续移动。
- `Ctrl+C` 复制、`Ctrl+X` 剪切、`Ctrl+V` 粘贴、`Ctrl+Shift+V` 粘贴为新图层。
- 右键：取消选择 / 取色。

### 六、动画预览

1. 在「动画预览」区域点击任意单元格可定位到该帧。
2. 设置 `起始` 与 `结束` 帧号。**起始帧必须小于结束帧**，输入时会自动纠正。
3. 设置 `FPS`（帧率）并勾选 `循环`。
4. 点击 `播放` 预览动画；`停止` 暂停；`全范围` 一键使用全部帧。
5. 勾选 `前帧` / `后帧` 可开启洋葱皮，滑动条调整不透明度。

### 七、图层

- 双击图层名可重命名。
- 点击眼睛图标切换可见性。
- 拖动图层可重新排序（顶部为上）。
- `合并 ↓`：将当前图层合并到下一层。
- `拼合可见`：将所有可见图层合并为单层。
- `粘贴为新图层`：使用 `Ctrl+Shift+V`。

### 八、参考线与吸附

- 从顶部标尺向下拖 → 水平参考线。
- 从左侧标尺向右拖 → 垂直参考线。
- 按住 `Ctrl` 并靠近参考线拖动 → 移动参考线。
- 拖动参考线时自动吸附到格子边沿 / 中心。
- **双击参考线** → 删除。
- 选区终点会吸附到邻近参考线（起点不吸附）。
- 隐藏参考线后不吸附、不可拖动。

### 九、图片色板与 NES 对比

- 点击 `刷新` 统计图片实际使用的颜色。
- 点击色块可高亮图中该颜色的所有像素。
- 点击 `对比 NES` 弹出模态框，列出：
  - ✅ 在 NES 色板中的颜色及其索引、像素数。
  - ❌ 不在 NES 色板中的颜色，并给出最接近的 NES 色（带 RGB 欧氏距离）。

### 十、快捷键速查表

| 快捷键 | 功能 |
| --- | --- |
| `V` / `M` / `B` / `E` / `I` / `G` / `J` | 切换工具 |
| `1` ~ `7` | 切换工具 |
| `[` / `]` | 减小 / 增大笔刷 |
| `F` | 适应窗口 |
| `空格 + 左键拖动` 或 中键拖动 | 平移视图 |
| 滚轮 | 缩放（以鼠标为中心） |
| `Ctrl+Z` / `Ctrl+Shift+Z` / `Ctrl+Y` | 撤销 / 重做 |
| `Ctrl+A` / `Ctrl+D` / `Ctrl+I` | 全选 / 取消 / 反选 |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | 复制 / 剪切 / 粘贴 |
| `Ctrl+Shift+V` | 粘贴为新图层 |
| `Ctrl+S` | 保存 PNG |
| `Delete` / `Backspace` | 删除选中像素 |
| `←` `→` `↑` `↓` | 移动浮动像素 1 像素 |
| `Esc` | 取消当前操作 / 取消选择 |

### 十一、工程文件（.pxproj）

「另存工程」会导出 JSON 格式的 `.pxproj` 文件，包含：
- 画布尺寸、图层数据（PNG Base64 编码）
- 网格与参考线
- 动画起始/结束帧、FPS、循环、洋葱皮状态
- 自定义色板、主/辅色、笔刷大小

再次打开工程即可恢复完整编辑状态。

### 十二、常见问题

**Q：为什么像素格网格在单格模式下看不到？**
A：像素格仅在缩放 ≥ 400% 时显示（`z >= 4`）。放大视图即可看到。

**Q：能否撤销超过 60 步？**
A：当前历史最多保存 60 步快照。可通过修改源码中的 `HISTORY_MAX` 调整。

**Q：支持导出 GIF 吗？**
A：暂不支持。可使用「另存 PNG」导出整张精灵图，再用其他工具打包为 GIF。

---

## English Documentation

### 1. Introduction

SpritesheetEditor is a browser-based pixel art editor designed for pixel artists and indie game developers. It opens PNG sprite sheets, slices them into grid cells, lets you edit frame by frame with live animation preview, and provides a built-in NES palette for retro work.

No installation needed — just open the HTML file. Default language is English, with one-click switch to Chinese.

### 2. Quick Start

1. Open `SpritesheetEditor.html` in any modern browser.
2. Use `File ▾ → Open PNG…` or drag & drop a PNG.
3. In the right-side "Grid / Cells" panel, set cell width/height (or columns/rows).
4. Edit pixels using tools on the toolbar.
5. Click a cell in the "Animation" preview to jump to a frame; press `Play` to preview.
6. Export with `Save As PNG`, or `Save As Project` to keep working later (`.pxproj`).

### 3. Interface

**Toolbar (left to right)**
- `File ▾` / `Edit ▾` dropdowns.
- `Open PNG` / `Open Project` / `Save As PNG` / `Save As Project`.
- Tool buttons: Select, Lasso, Pencil, Eraser, Picker, Bucket, Replace.
- `Undo` / `Redo`.
- Zoom: `−` / `+` / `Fit`.
- Background cycle: White / Gray / Black / Checker.
- `Single / Full` view toggle.
- `CH / EN` language toggle (top-right).

**Sidebar**

| Section | Description |
| --- | --- |
| Grid / Cells | Cell width/height, columns/rows; grid & pixel grid toggles |
| Animation | Thumbnail + clickable cell locator; start/end frame, FPS, loop, play/stop |
| Color | Primary, secondary, replace-all |
| NES Palette | Read-only NTSC 2C02 palette (64 colors) |
| Custom Palette | Add / remove / load / save JSON |
| Layers | New / Duplicate / Delete / Move / Merge / Flatten |
| Guides / Snap | Drag guides from rulers; toggle snapping |
| Image Palette | Count colors used in the image; compare against NES |
| Selection | Selection modes, Select All, Invert, Select Cell, Delete Pixels |

### 4. Tools

| Tool | Shortcut | Description |
| --- | --- | --- |
| Select | `V` / `1` | Rectangular selection; drag inside to move pixels |
| Lasso | `M` / `7` | Freeform selection; `Shift` for a circle |
| Pencil | `B` / `2` | Draw per-pixel; `Alt` + click to pick |
| Eraser | `E` / `3` | Erase pixels to transparent |
| Picker | `I` / `5` | Pick color from canvas |
| Bucket | `G` / `4` | Flood fill; `Alt` + click to pick |
| Replace | `J` / `6` | Replace every occurrence of the clicked color with primary |

**Brush size**: `[` smaller, `]` larger.

### 5. Selection & Moving

- Drag with Select tool to create a rectangular selection.
- **`Shift`** = square selection / circle lasso.
- **`Ctrl`** = add to selection, **`Alt`** = subtract.
- **Normal drag** inside selection → float pixels and move them (hold `Shift` to lock to one axis).
- **Hold `V` or `M` and drag** inside → move **selection only** (pixels stay in place).
- **Arrow keys**: move floating pixels 1px per press, hold for continuous movement.
- `Ctrl+C` copy, `Ctrl+X` cut, `Ctrl+V` paste, `Ctrl+Shift+V` paste as new layer.
- Right-click: deselect / pick color.

### 6. Animation Preview

1. Click any cell in the preview area to jump to that frame.
2. Set `Start` and `End` frames. **Start must be < End** — invalid input is auto-corrected.
3. Set `FPS` and check `Loop`.
4. `Play` / `Stop` / `Full Range`.
5. Enable `Prev` / `Next` for onion skinning; slider adjusts opacity.

### 7. Layers

- Double-click a layer name to rename.
- Click the eye icon to toggle visibility.
- Drag layers to reorder (top = front).
- `Merge Down`: merge current layer into the one below.
- `Flatten`: merge all visible layers into one.
- `Paste as Layer`: use `Ctrl+Shift+V`.

### 8. Guides & Snapping

- Drag down from the top ruler → horizontal guide.
- Drag right from the left ruler → vertical guide.
- Hold `Ctrl` and drag near a guide → move it.
- While dragging, guides auto-snap to cell edges / centers.
- **Double-click** a guide → delete.
- Selection endpoint snaps to nearby guides (start point does not).
- When hidden, guides are neither snappable nor draggable.

### 9. Image Palette & NES Comparison

- Click `Refresh` to count colors used in the image.
- Click a swatch to highlight all pixels of that color.
- Click `Compare NES` to open a modal:
  - ✅ Colors in the NES palette (with index & pixel count).
  - ❌ Colors not in the palette, each with the nearest NES color and RGB distance.

### 10. Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `V` / `M` / `B` / `E` / `I` / `G` / `J` | Switch tools |
| `1` – `7` | Switch tools |
| `[` / `]` | Decrease / increase brush size |
| `F` | Fit to view |
| `Space + drag` or middle-drag | Pan |
| Mouse wheel | Zoom (centered on cursor) |
| `Ctrl+Z` / `Ctrl+Shift+Z` / `Ctrl+Y` | Undo / Redo |
| `Ctrl+A` / `Ctrl+D` / `Ctrl+I` | Select All / Deselect / Invert |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | Copy / Cut / Paste |
| `Ctrl+Shift+V` | Paste as new layer |
| `Ctrl+S` | Save PNG |
| `Delete` / `Backspace` | Delete selected pixels |
| `←` `→` `↑` `↓` | Move floating pixels 1px |
| `Esc` | Cancel current action / deselect |

### 11. Project Files (.pxproj)

"Save As Project" exports a JSON `.pxproj` containing:
- Canvas size, layer data (PNG Base64)
- Grid & guides
- Animation start/end, FPS, loop, onion skin
- Custom palette, primary/secondary colors, brush size

Re-opening the project restores the complete editing state.

### 12. FAQ

**Q: Why is the pixel grid not visible in single-cell view?**
A: Pixel grid appears only when zoom ≥ 400% (`z >= 4`). Zoom in further.

**Q: Can I undo more than 60 steps?**
A: History holds up to 60 snapshots. Modify `HISTORY_MAX` in the source to change.

**Q: GIF export?**
A: Not supported. Use "Save As PNG" to export the sheet, then pack with another tool.