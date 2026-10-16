# TextureRescale 使用说明 / User Guide

面向像素画/贴图的轻量图像处理工具。支持打开图片、缩放、转真像素、颜色精简、删除/替换颜色、拆分导出。

A lightweight image tool for pixel art / texture: open, resize, convert to true pixels, simplify colors, delete/replace colors, split export.

---

## 打开与保存 / Open & Save

**中文**

- **打开图片**：点击工具栏「打开图片」，或直接将图片拖入窗口。
- **保存 PNG**：有文件句柄时直接保存，否则触发下载。
- **另存为…**：使用系统文件选择器保存为 PNG。
- **关闭**：关闭当前图片，恢复空状态。

**English**

- **Open Image**: click the toolbar button, or drag an image into the window.
- **Save PNG**: save to current file handle if available, otherwise download.
- **Save As…**: use the system file picker to save as PNG.
- **Close**: close current image and return to empty state.

---

## 视图与缩放 / View & Zoom

**中文**

- **滚轮缩放**：以鼠标为中心缩放。
- **拖空白平移**：按住鼠标中键，或按住空格 + 左键拖动。
- **原始尺寸**：将当前显示尺寸重置为原始尺寸（不影响缩放比例）。
- **适应窗口**：自动缩放并居中显示。
- **1:1 / ½ / ¼ / ⅛ / ×2**：快速按比例调整当前尺寸。
- **W / H 输入框**：直接输入目标宽高。
- **锁定比例**：勾选后修改宽或高会自动同步另一项。
- **吸附像素**：开启后框选边沿自动吸附到像素网格。
- **显示像素格**：在缩放 ≥ 4 时显示像素网格。
- **背景切换**：白底 / 灰底 / 黑底 / 格子，循环切换。

**English**

- **Wheel zoom**: zoom centered on the mouse cursor.
- **Drag empty to pan**: middle mouse button, or hold Space + left drag.
- **Original Size**: reset the current display size to the original size (zoom ratio unaffected).
- **Fit to Window**: auto-scale and center the view.
- **1:1 / ½ / ¼ / ⅛ / ×2**: quickly scale by ratio.
- **W / H inputs**: type the target width/height directly.
- **Lock Ratio**: editing one dimension updates the other.
- **Snap to Pixels**: selection edges snap to the pixel grid.
- **Show Pixel Grid**: show pixel grid when zoom ≥ 4.
- **Background**: cycle White / Gray / Black / Checker.

---

## 选区操作 / Selection

**中文**

- **矩形选择**：默认模式，拖拽创建选区。
- **套索选择**：按 `M` 键切换套索模式，拖拽绘制路径，松开生成选区。
- **加选**：按住 `Ctrl`（或 `Cmd`）拖拽。
- **减选**：按住 `Alt` 拖拽。
- **正方形 / 正圆**：按住 `Shift` 拖拽。
- **移动选区**：在选区内直接拖动可移动选区位置（仅移动选区，不移动像素）。
- **删除选区像素**：按 `Delete` 键，将选区像素置为透明。
- **全选 / 取消 / 反选**：`Ctrl+A` / `Ctrl+D` / `Ctrl+I`。
- **复制选区**：`Ctrl+C` 复制为 PNG 到剪贴板。

**English**

- **Rectangle select**: default mode; drag to create.
- **Lasso select**: press `M` to toggle lasso mode, drag to draw a path, release to create.
- **Add**: hold `Ctrl` (or `Cmd`) and drag.
- **Subtract**: hold `Alt` and drag.
- **Square / Circle**: hold `Shift` and drag.
- **Move selection**: drag inside the selection to move it (selection only, not pixels).
- **Delete selection pixels**: press `Delete` to make them transparent.
- **Select All / Deselect / Invert**: `Ctrl+A` / `Ctrl+D` / `Ctrl+I`.
- **Copy selection**: `Ctrl+C` copies as PNG to clipboard.

---

## 转真像素 / True Pixels

**中文**

将模拟像素图转换为硬边、纯色、无半透明像素的真实像素图。

- **打开面板**：点击「转真像素…」。
- **像素块**：自动检测的原始像素块大小，可手动调整。点「自动」重新检测。
- **采样 — 众数**：取块内出现最多的颜色。
- **采样 — 中心**：取块中心像素颜色（默认）。
- **合并色**：0–100，越大合并越多相近色，默认 40。
- **边缘清理**：去毛刺、硬边，默认开启。
- **去除半透明像素**：alpha < 128 变为全透明，其余变为完全不透明，默认开启。
- **实时预览**：所有调整立即生效，底部显示输出尺寸和颜色数。
- **应用 / 取消**：应用写入历史，取消恢复原图。

**English**

Convert simulated pixel art into hard-edged, flat-color, non-semi-transparent true pixels.

- **Open panel**: click "True Pixels…".
- **Block**: auto-detected original pixel block size; adjustable. Click "Auto" to re-detect.
- **Sample — Majority**: most frequent color in the block.
- **Sample — Center**: color at the block center (default).
- **Merge**: 0–100, larger merges more similar colors, default 40.
- **Edge cleanup**: de-noise and hard edges, default on.
- **Remove semi-transparent**: alpha < 128 → fully transparent; otherwise fully opaque, default on.
- **Live preview**: adjustments apply immediately; footer shows output size and color count.
- **Apply / Cancel**: Apply commits to history, Cancel restores original.

---

## 清理像素 / Clean Pixels

**中文**

- 将 alpha < 128 的像素置为透明，alpha ≥ 128 的变为完全不透明。
- 对非透明像素进行 4 轮 3×3 多数投票去噪，减少孤立杂色。

**English**

- Make alpha < 128 pixels transparent; alpha ≥ 128 fully opaque.
- Run 4 rounds of 3×3 majority-vote de-noise on non-transparent pixels to reduce isolated noise.

---

## 颜色统计 / Color Stats

**中文**

- 统计所有非透明像素的颜色及出现次数。
- 点击色块可设为“主色”并提示。

**English**

- Count all non-transparent pixel colors and their occurrences.
- Click a swatch to set it as "primary color".

---

## 合并相似色 / Merge Similar Colors

**中文**

- 通过相似度阈值合并颜色，减少颜色总数。
- 实时预览合并前后颜色数量。
- 点击「应用合并」执行。

**English**

- Merge colors by similarity threshold to reduce color count.
- Live preview of color count before/after merge.
- Click "Apply Merge" to run.

---

## 删除 / 替换颜色 / Delete / Replace Color

**中文**

- 点击「删除/替换颜色…」打开面板。
- 在画布上点击要处理的颜色，显示颜色样本和十六进制值。
- **相似阈值**：0 为精确匹配，越大包含越多相近色。
- **启用替换**：勾选后可选择替换色，否则默认删除（置为透明）。
- **应用**：按匹配像素数执行删除或替换。

**English**

- Click "Delete/Replace Color…" to open the panel.
- Click a color on the canvas; shows swatch and hex.
- **Similarity**: 0 = exact match; larger includes more similar colors.
- **Enable replace**: check to choose a replacement color; otherwise delete (make transparent).
- **Apply**: performs delete or replace on the matched pixel count.

---

## 拆分导出 / Split Export

**中文**

- 按行列数将当前图片拆分为多个小图。
- 显示每块尺寸。
- 点击「选择目录并导出」选择文件夹（支持文件系统访问 API 时），否则依次触发下载。

**English**

- Split current image into tiles by rows/cols.
- Shows tile size.
- Click "Choose Folder & Export" to select a folder (uses File System Access API if available), otherwise triggers downloads in sequence.

---

## 撤销 / 重做 / Undo & Redo

**中文**

- `Ctrl+Z` 撤销，`Ctrl+Shift+Z` 或 `Ctrl+Y` 重做。
- 历史步数上限 24。

**English**

- `Ctrl+Z` undo, `Ctrl+Shift+Z` or `Ctrl+Y` redo.
- History limit: 24 steps.

---

## 快捷键总览 / Keyboard Shortcuts

**中文**

| 快捷键 | 功能 |
|--------|------|
| `Ctrl+Z` / `Ctrl+Shift+Z` | 撤销 / 重做 |
| `Ctrl+A` / `Ctrl+D` / `Ctrl+I` | 全选 / 取消 / 反选 |
| `Ctrl+C` | 复制选区 |
| `Ctrl+S` | 保存 PNG |
| `M` | 切换套索模式 |
| `Shift` + 拖拽 | 正方形 / 正圆 |
| `Ctrl` + 拖拽 | 加选 |
| `Alt` + 拖拽 | 减选 |
| `Delete` | 删除选区像素 |
| `F` | 适应窗口 |
| `Esc` | 取消当前操作 / 关闭面板 |
| `空格` + 拖拽 | 平移画布 |

**English**

| Shortcut | Action |
|----------|--------|
| `Ctrl+Z` / `Ctrl+Shift+Z` | Undo / Redo |
| `Ctrl+A` / `Ctrl+D` / `Ctrl+I` | Select All / Deselect / Invert |
| `Ctrl+C` | Copy selection |
| `Ctrl+S` | Save PNG |
| `M` | Toggle lasso mode |
| `Shift` + drag | Square / circle |
| `Ctrl` + drag | Add to selection |
| `Alt` + drag | Subtract from selection |
| `Delete` | Delete selection pixels |
| `F` | Fit to window |
| `Esc` | Cancel op / close panel |
| `Space` + drag | Pan canvas |

---

## 底部状态栏 / Status Bar

**中文**

- 显示原始尺寸、当前尺寸、缩放比例、选区信息、历史步数。
- 右侧消息区实时显示操作反馈。
- 坐标显示当前鼠标像素位置。

**English**

- Shows original size, current size, zoom, selection info, history steps.
- Right-side message area shows live operation feedback.
- Coordinate display shows current mouse pixel position.