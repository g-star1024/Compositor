# 上游 v1.4.7 UI 改动吸收 Backlog

> 上游 `robbietilton/Compositor` 在 2026-10-08 发布 v1.4.7，我们 fork `g-star1024/Compositor` v1.5.0 已合入纯逻辑 commit（Camera Raw curves、Don't Save destructive、Scanlines 全部）。剩余 **9 个 UI 层 commit** 因与我们 macOS 14 适配 / 简中 i18n / Xcode 26 编译器绕行 的改动在同一批文件上，需要**逐个评估冲突成本**再决定吸收策略。

---

## 冲突评估维度

我们改过的关键文件（不可轻易丢弃的本地改动）：

- `Compositor/ContentView.swift` — 3 处 `#available(macOS 26, *)` 包裹（ToolbarSpacer × 2、sharedBackgroundVisibility）+ View.modify 扩展 + PanelResizeEdge NSCursor 回退
- `Compositor/CompositorApp.swift` — Scene.defaultWindowPlacementIfAvailable() 扩展
- `Compositor/Rendering/EditorCanvas.swift` — FrameResizePosition / frameResize 用 `if #available(macOS 15.0, *)` 包裹 + macOS 14 回退 `.crosshair`
- `Compositor/UI/KeyboardShortcuts.swift` — 简中 i18n 翻译（418 条之一）
- `Compositor/UI/LayersPanel.swift` — 简中 i18n 翻译
- `README.md` — v1.5.0 What's New 区块 + Automated/Manual release 两小节
- `Compositor/Document/EditorSession.swift` — 简中 i18n（状态字符串）

---

## 待吸收 commit（按风险从低到高）

### 🟢 低风险（独立文件 / 纯新增）

| SHA | 功能 | 影响文件 | 吸收策略 |
|---|---|---|---|
| `c0a1cd0` | The hand stays closed for a whole Space or Hand tool pan | `Rendering/EditorCanvas.swift` (+8) | cherry-pick，仅 +8 行，大概率零冲突 |
| `1aad384` | Quit works mid-gradient or with a dialog open | `ProjectWorkspace.swift` + `ApplicationDelegate.swift` + Tests | cherry-pick，我们未碰 ProjectWorkspace |

### 🟡 中风险（撞我们 i18n / Xcode 26 绕行）

| SHA | 功能 | 影响文件 | 吸收策略 |
|---|---|---|---|
| `790195f` | Disabled Layers footer buttons dim as far as its menus do | `UI/LayerMaskMenu.swift` + `UI/LayersPanel.swift` | cherry-pick，LayersPanel 撞 i18n——需手工补简中翻译 |
| `7fb40a9` | Layers footer buttons use the primary color, for readability | `UI/LayerMaskMenu.swift` + `UI/LayersPanel.swift` | 同上，且应在 790195f 之后合入（同区域） |
| `8f7d344` | LayerCell name field stays the same size while renaming | `UI/NativeLayerList.swift` | cherry-pick，NativeLayerList 未大改，但 +3/-5 行需对照 i18n |

### 🟠 高风险（撞我们 macOS 14 适配核心）

| SHA | 功能 | 影响文件 | 吸收策略 |
|---|---|---|---|
| `0415aa4` | Filter › Last Filter (⌘F): the last filter again, with same settings | `CompositorApp` + `ContentView` + `EditorSession` + `Filters` + `KeyboardShortcuts` + Tests + README | **手工合**——ContentView 撞我们 `#available` 包裹、EditorSession 撞 i18n、README 撞 v1.5.0 What's New |
| `6b81d4a` | Last Filter on ⌃⌘F, ⌘F is the command palette | `CompositorApp` + `KeyboardShortcuts` + Tests + README | 依赖 0415aa4，需一并处理快捷键冲突 |
| `720c121` | Toggle Fullscreen on F and Esc; Search Commands on ⌘F | `CompositorApp` + `EditorSession` + `ApplicationDelegate` + `CommandPaletteView` + `KeyboardShortcuts` + Tests + README | 依赖 6b81d4a；⌘F 重映射会影响整个简中快捷键表，**需重写翻译** |

### 🔴 极高风险（重写我们已修过的 UI 文件）

| SHA | 功能 | 影响文件 | 吸收策略 |
|---|---|---|---|
| `68396ff` | Tool headers scroll when the window is too narrow, instead of squeezing | `UI/BrushControls.swift` (231 行重写) + `UI/GradientControls.swift` + `UI/LassoControls.swift` | **暂不合**——这是 3 个 Tool Header 控件的全面重写，会撞我们 TypeControls/BlendModePicker 的 `#available` 修复；且收益只在「窗口过窄」场景，对我们 macOS 14 + universal 价值不大 |

---

## 建议吸收顺序

### 第 1 批（立即可做，零风险）

```bash
git cherry-pick c0a1cd0  # Hand closed for whole pan (+8 行 EditorCanvas)
git cherry-pick 1aad384  # Quit mid-gradient
```

### 第 2 批（Layers 面板 UI 三件套，需补简中）

```bash
git cherry-pick 790195f  # Disabled dim
git cherry-pick 7fb40a9  # Primary color
git cherry-pick 8f7d344  # LayerCell rename bezel
```

合完后**必须**：
- 重跑 Localizable.xcstrings 提取新增字符串
- 补 3-5 条简中翻译（Layer footer 相关）

### 第 3 批（快捷键重映射三件套，需重写简中快捷键表）

```bash
git cherry-pick 0415aa4  # Last Filter (⌘F)
git cherry-pick 6b81d4a  # ⌃⌘F 重映射
git cherry-pick 720c121  # Fullscreen on F/Esc
```

合完后**必须**：
- 手工解 `ContentView.swift` 冲突（保留我们 `#available` 包裹 + 合入上游 Filter 菜单项）
- 手工解 `EditorSession.swift` 冲突（保留我们 i18n + 合入上游 `lastFilter` 状态）
- 手工解 `README.md` 冲突（保留 v1.5.0 What's New + 合入上游快捷键表更新）
- 重跑 Localizable.xcstrings 提取
- 补 10+ 条简中翻译（Last Filter、Fullscreen、Search Commands、⌘F/⌃⌘F 提示）

### 第 4 批（暂缓，先观察）

`68396ff` Tool headers scroll——等用户反馈「窗口过窄时工具头被挤压」是否是真痛点再决定。如真需要，策略是**手工 cherry-pick + 重跑 3 批 macOS 14 `#available` 修复**（因为上游重写了 BrushControls/GradientControls/LassoControls 这 3 个文件，我们没修过但这 3 个文件如果引入 macOS 15+/26+ API 会再次撞 universal build）。

---

## 验收标准（每批合入后）

- [ ] `xcodebuild build-for-testing` 在 macos-26 + Xcode 26.6 universal (arm64 + x86_64) 通过
- [ ] `verify.yml` CI 全绿
- [ ] `lipo -info` 确认双切片
- [ ] 简中界面新增字符串 100% 翻译（Localizable.xcstrings 无 missing）
- [ ] `xcodebuild test-without-building` 单元测试通过

---

## 当前状态

- ✅ **已合入**：Camera Raw curves、Don't Save destructive、Scanlines (9c99853 + cd2f998)（v1.4.6 fork 起点已含）
- ✅ **已合入**：`a316b62` Don't Save destructive（v1.5.0 之后单独 cherry-pick）
- 🟡 **待办**：本 backlog 中 9 个 commit 分 3 批处理
- 📝 **最近更新**：2026-10-09 00:31 GMT+8
