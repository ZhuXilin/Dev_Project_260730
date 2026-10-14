# TextureRescale · 像素缩放工具

一个纯前端的像素图缩放 / 清理 / 拆分工具，适用于分辨率处理、颜色精简和 spritesheet 拆分导出。

A pure front-end pixel rescale / cleanup / split tool for resolution handling, color reduction and spritesheet splitting.

> [中文](#中文文档) ｜ [English](#english-documentation)

---

## 中文文档

### 一、简介

TextureRescale 是一款轻量的像素图处理工具，专注于「缩放」场景。它可以快速放大 / 缩小像素图，保留硬边缘（无插值），并附带清理像素、颜色统计、合并相似色、删除指定颜色、按行列拆分导出等实用功能。

默认英文界面，可一键切换中文。无需安装，双击 HTML 文件即可使用。

### 二、快速开始

1. 用浏览器打开 `TextureRescale.html`。
2. 点击 `打开图片` 或直接拖入图片。
3. 在顶部输入框中修改 `W`（宽）/ `H`（高），或点击 `½` / `¼` / `⅛` / `×2` 快速缩放。
4. 勾选 `锁定比例` 保持宽高比。
5. 完成后 `保存 PNG` 或 `另存为…`。

### 三、界面说明

**顶部工具栏（从左到右）**

| 按钮 | 说明 |
| --- | --- |
| 打开图片 | 载入 PNG / JPG / WebP 等 |
| 保存 PNG | 保存到上次保存的文件（若无则下载） |
| 另存为… | 弹出系统保存对话框 |
| 关闭 | 清空当前图片 |
| 撤销 / 重做 | 撤销栈最多 24 步 |
| 原始尺寸 | 回到载入时的尺寸 |
| 适应窗口 | 视图自动缩放填满窗口 |
| 1:1 | 视图 100% |
| ½ / ¼ / ⅛ | 图片尺寸缩小到 1/2、1/4、1/8 |
| ×2 | 图片尺寸放大 2 倍 |
| 宽 / 高 | 输入目标尺寸 |
| 锁定比例 | 保持原始宽高比 |
| 背景 | 循环切换 白底 / 灰底 / 黑底 / 格子 |
| 选择 | 切换选择模式（默认开） |
| 全选 / 取消选择 / 反选 | 选区操作 |
| 复制 | 复制选区为新 PNG |
| 删除选区 | 将选区像素变为透明 |
| 清理像素 | 去除杂色、半透明 |
| 颜色统计… | 统计图片使用的全部颜色 |
| 合并相似色… | 合并相近颜色 |
| 删除颜色… | 按颜色批量删除 |
| 拆分导出… | 按行列拆成小图并导出 |
| CH / EN | 语言切换 |

**底部状态栏**

- 原始尺寸、当前尺寸、视图缩放比
- 选区信息
- 历史步数
- 临时状态消息

### 四、缩放

1. **手动输入**：修改 `宽` 或 `高` 后按回车或点击其他区域。锁定比例时，只改一个值即可等比缩放。
2. **快速按钮**：`½`、`¼`、`⅛`、`×2` 一键缩放。
3. **拖拽手柄**：图片四周有 8 个控制点，可直接拖拽缩放（`Shift` 反向锁定比例）。
4. **恢复**：点击 `原始尺寸` 回到载入时的尺寸。

所有缩放都使用**最近邻插值**（无模糊），保持像素硬边缘。

### 五、选区

- 用鼠标在画布上拖拽框选。
- **`Shift`** = 正方形选区。
- **`Ctrl`** = 加选，**`Alt`** = 减选。
- 右键 = 取消当前选区。
- `Ctrl+A` 全选，`Ctrl+D` 取消，`Ctrl+I` 反选。

### 六、清理像素

点击 `清理像素` 将执行：
- 把 alpha < 128 的像素设为完全透明。
- 把 128 ≤ alpha < 255 的像素设为完全不透明。
- 用多数投票法（4 邻域内同色 ≥ 4）平滑噪点，最多 4 轮。

适合去除抗锯齿残留、JPEG 压缩杂色。

### 七、颜色处理

**颜色统计**
- 点击 `颜色统计…` 打开模态框，列出图片中所有颜色及其出现次数。
- 点击色块可将该色设为主色。

**合并相似色**
- 点击 `合并相似色…` 打开面板。
- 拖动 `相似阈值` 滑块（1–100，颜色 RGB 欧氏距离）。
- 面板实时显示合并前后的颜色数量。
- 点击 `应用合并` 执行。

**删除颜色**
- 点击 `删除颜色…` 打开面板。
- 在画布上点击要删除的颜色。
- 拖动 `相似阈值`（0 = 精确匹配，越大包含越多相近色）。
- 点击 `应用删除`。

### 八、拆分导出

1. 点击 `拆分导出…`。
2. 输入 `列数` 和 `行数`。面板会实时显示每块的尺寸。
3. 点击 `选择目录并导出`：
   - **支持 File System Access API 的浏览器**（Chrome / Edge）：弹出文件夹选择框，直接写入所有小图。
   - **其他浏览器**：依次触发多个 PNG 下载，请允许浏览器「下载多个文件」。

导出文件命名格式：`原文件名_r行号_c列号.png`（行列均从 1 开始）。

### 九、快捷键速查表

| 快捷键 | 功能 |
| --- | --- |
| `Ctrl+Z` / `Ctrl+Shift+Z` / `Ctrl+Y` | 撤销 / 重做 |
| `Ctrl+A` / `Ctrl+D` / `Ctrl+I` | 全选 / 取消 / 反选 |
| `Ctrl+C` | 复制选区 |
| `Ctrl+S` | 保存 PNG |
| `Delete` | 删除选区（变透明） |
| `V` | 切换选择模式 |
| `F` | 适应窗口 |
| `空格 + 左键拖动` | 平移视图 |
| 滚轮 | 缩放视图（`Ctrl + 滚轮` 更细腻） |
| `Esc` | 关闭当前面板 / 取消选区 |

### 十、常见问题

**Q：为什么缩小图片会丢失细节？**
A：像素图缩放采用最近邻插值，缩小会按采样点丢弃像素。建议先放大处理，最后再统一缩小。

**Q：为什么「选择目录并导出」没弹出文件夹选择框？**
A：该功能依赖 File System Access API，仅 Chrome / Edge 88+ 支持。其他浏览器会自动回退到多次下载模式。

**Q：能处理的最大尺寸？**
A：单边最大 16384 像素，总像素数上限约 9600 万。

**Q：撤销栈有限制吗？**
A：最多 24 步历史。可通过源码中的 `MAX_HISTORY` 修改。

---

## English Documentation

### 1. Introduction

TextureRescale is a lightweight pixel image tool focused on **rescaling**. It quickly enlarges or shrinks pixel art with hard edges (nearest-neighbor, no blur), plus a set of handy utilities: clean pixels, color stats, merge similar colors, delete color, and split export by rows/cols.

Default language is English, with one-click switch to Chinese. No installation — just open the HTML file.

### 2. Quick Start

1. Open `TextureRescale.html` in a modern browser.
2. Click `Open Image` or drag & drop an image.
3. Edit `W` (width) / `H` (height), or click `½` / `¼` / `⅛` / `×2`.
4. Keep `Lock Ratio` checked to preserve aspect ratio.
5. `Save PNG` or `Save As…` when done.

### 3. Interface

**Toolbar (left to right)**

| Button | Description |
| --- | --- |
| Open Image | Load PNG / JPG / WebP etc. |
| Save PNG | Save to previous file, or download |
| Save As… | Show system save dialog |
| Close | Clear the current image |
| Undo / Redo | Up to 24 steps |
| Original Size | Restore original dimensions |
| Fit to Window | Auto-fit zoom |
| 1:1 | Zoom to 100% |
| ½ / ¼ / ⅛ | Shrink image to 1/2, 1/4, 1/8 |
| ×2 | Enlarge image 2× |
| W / H | Target width / height |
| Lock Ratio | Preserve aspect ratio |
| Background | Cycle White / Gray / Black / Checker |
| Select | Toggle selection mode (on by default) |
| Select All / Deselect / Invert | Selection operations |
| Copy | Copy selection as a new PNG |
| Delete Selection | Make selection transparent |
| Clean Pixels | Remove noise & semi-transparency |
| Color Stats… | Count all colors used |
| Merge Similar… | Merge nearby colors |
| Delete Color… | Bulk delete a color |
| Split Export… | Split into tiles by rows/cols |
| CH / EN | Language toggle |

**Status bar**

- Original size, current size, zoom
- Selection info
- History step
- Transient message

### 4. Rescaling

1. **Manual input**: edit `W` or `H`, then press Enter or click elsewhere. With `Lock Ratio` on, only one value is needed.
2. **Quick buttons**: `½`, `¼`, `⅛`, `×2`.
3. **Drag handles**: 8 handles around the image let you resize directly (`Shift` inverts the ratio lock behavior).
4. **Restore**: click `Original Size`.

All rescaling uses **nearest-neighbor interpolation** (no blur), preserving crisp pixel edges.

### 5. Selection

- Drag on the canvas to create a selection.
- **`Shift`** = square selection.
- **`Ctrl`** = add, **`Alt`** = subtract.
- Right-click = clear selection.
- `Ctrl+A` select all, `Ctrl+D` deselect, `Ctrl+I` invert.

### 6. Clean Pixels

Click `Clean Pixels` to:
- Set pixels with alpha < 128 fully transparent.
- Set pixels with 128 ≤ alpha < 255 fully opaque.
- Smooth noise with majority vote (≥ 4 same-color neighbors), up to 4 rounds.

Ideal for removing anti-aliasing remnants and JPEG artifacts.

### 7. Color Handling

**Color Stats**
- Click `Color Stats…` to open a modal listing every color and its count.
- Click a swatch to set it as primary.

**Merge Similar Colors**
- Click `Merge Similar…`.
- Drag the `Similarity` slider (1–100, RGB Euclidean distance).
- The panel shows before/after color counts live.
- Click `Apply Merge`.

**Delete Color**
- Click `Delete Color…`.
- Click a color on the canvas.
- Adjust `Similarity` (0 = exact match, larger includes more nearby colors).
- Click `Apply`.

### 8. Split Export

1. Click `Split Export…`.
2. Enter `Cols` and `Rows`. Tile size is shown live.
3. Click `Choose Folder & Export`:
   - **Browsers with File System Access API** (Chrome / Edge): a folder picker appears, all tiles are written directly.
   - **Other browsers**: multiple PNG downloads will be triggered. Please allow "download multiple files".

File naming: `basename_r{row}_c{col}.png` (rows/cols start at 1).

### 9. Keyboard Shortcuts

| Shortcut | Action |
| --- | --- |
| `Ctrl+Z` / `Ctrl+Shift+Z` / `Ctrl+Y` | Undo / Redo |
| `Ctrl+A` / `Ctrl+D` / `Ctrl+I` | Select All / Deselect / Invert |
| `Ctrl+C` | Copy selection |
| `Ctrl+S` | Save PNG |
| `Delete` | Delete selection (transparent) |
| `V` | Toggle selection mode |
| `F` | Fit to window |
| `Space + drag` | Pan |
| Mouse wheel | Zoom view (`Ctrl + wheel` for finer steps) |
| `Esc` | Close current panel / deselect |

### 10. FAQ

**Q: Why do details get lost when shrinking?**
A: Nearest-neighbor sampling drops pixels when shrinking. For best results, work at high resolution first, then shrink at the very end.

**Q: Why didn't a folder picker appear for Split Export?**
A: This feature uses File System Access API (Chrome / Edge 88+). Other browsers fall back to multiple downloads.

**Q: Maximum size?**
A: Max 16384 px per side; max ~96 million pixels total.

**Q: Undo limit?**
A: Up to 24 steps. Modify `MAX_HISTORY` in the source to change.