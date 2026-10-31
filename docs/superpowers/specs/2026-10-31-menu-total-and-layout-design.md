# 展示布局修正：菜单合计行 + 主页越界 + 速率图标签固定

- 日期：2026-10-31
- 状态：已确认（用户选定「分隔线 + 加粗合计行」方案并批准整体设计）
- 分支：feature/menu-total-and-layout（自 develop）

## 背景与问题

1. **下拉面板缺总累计**：面板只展示 Wi-Fi / iPhone 各模块行，没有所有模块的合计行；合计口径（上行 + 下行合并）已在告警/里程碑使用，但面板不可见。
2. **模块行折行**：`MenuTextBuilder.interfaceRow` 用固定 tab 位（96pt / 196pt）。当「↑tx ↓rx」文本宽度超过 196pt 时第二个 tab 失效，合并总量被挤到第二行。
3. **主页模块卡片累计越界**：累计标签固定宽 140pt、右对齐、`byClipping`，文案为单行 `"累计  ↑ 123.4 MB    ↓ 567.8 MB"`（12pt）。数值整数部分 ≥ 3 位时整串约 160pt+，左端被裁。
4. **速率图端点标注被线穿过**：`RateGraphView.drawEndLabel` 的两个当前速率值跟随折线端点上下移动，线抬起时从文字中间穿过，不可读。

## 方案（用户已确认）

### 1. 菜单：合计行 + 动态 tab 位

- `MenuTextBuilder.interfaceRow(name:rx:tx:stops:emphasized:)`：tab 位由参数传入；`emphasized == true` 时整行 semibold（合计行用）。
- `MenuTextBuilder.columnStops(rows:)`：每次刷新按三行（Wi-Fi / iPhone / 合计）的实际文本用渲染字体测量，返回共享的两个 tab 位：
  - `stop1 = max(名称宽) + 20pt 列间距 + 4pt 前导缩进`
  - `stop2 = stop1 + max(↑tx ↓rx 段宽) + 20pt 列间距`
  - 三行共用同一组 tab 位 → 列对齐、永不折行；面板宽度自然撑开（即「左右加宽」）。
- `MenuBarController`：新增 `totalItem`；菜单顺序 `startTimeItem / — / wifiItem / iphoneItem / — / totalItem / — / 打开主页 …`。合计 = `store.wifi + store.iphone` 逐向求和。
- 合计行名称「合计」，`emphasized: true`；与模块行同列结构（`合计  ↑tx ↓rx  合并`）。

### 2. 主页模块卡片：累计改两行堆叠

- 累计标签由单行改为右对齐两行（11pt）：

  ```text
  累计 ↑ 123.4 MB
        ↓ 567.8 MB
  ```

- 「累计」仅第一行出现；两行同用 `monospacedDigitSystemFont` 数位对齐。最宽情形（`累计 ↑ 1234.5 TB` ≈ 90pt）远小于可用宽度（140pt），任何数值不越界。
- 布局：两行标签放卡片右下（替换原单行 total 标签位置区域），速率行（19pt 大字）位置不变。

### 3. 速率图：标签位置固定

- 删除端点跟随逻辑；`↓当前下载速率` 固定绘制在绘图区右上角（下载蓝着色），`↑当前上传速率` 固定绘制在右下角（上传橙着色）。
- 与底部图例「● 下载 ● 上传」色点呼应；任何波形不再遮挡。

## 不改动的部分

- 菜单栏标题（`StatusBarFormatter`）已有总量展示，不动。
- 告警/里程碑口径、采样与存储逻辑不动。
- 窗口尺寸、其余主页元素不动。

## 测试（无 XCTest，自测内置于主程序）

- `MenuTextBuilderTests`：
  - 合计行含「合计」且数值为两模块之和（含大数 999 GB 级）；
  - 布局不变式：`名称宽 < stop1`、`stop1 + ↑↓段宽 < stop2`（大数下仍成立）；
  - 三行 tab 位一致（columnStops 对多行输入返回同一组位）。
- 主页累计两行文本：抽出纯函数生成（输入 tx/rx → 两行字符串），断言行数与内容。
- 速率图标签：常量坐标绘制，无可测逻辑；以 `TRAFFICMONITOR_SHOWHOME=1` 人工目检。
- 回归：全部自测通过（`swift build && TRAFFICMONITOR_SELFTEST=1 .build/debug/TrafficMonitor`）。

## 验收标准

1. 下拉面板出现「合计」行（semibold、上方有分隔线），数值 = 两模块合并总量。
2. 数值到 TB 级、名称任意长时，模块行与合计行均单行展示、列对齐，面板随之加宽。
3. 主页模块卡片累计值（3 位以上整数）完整显示，不越界不裁切。
4. 速率图两速率值位置固定（上=下载、下=上传），不被折线穿过。
