---
name: compositor-dev
description: 在 g-star1024/Compositor（robbietilton/Compositor 的 fork）上做开发、版本升级、本地化与发版的标准工作流。当用户要求升级 Compositor 版本、支持新系统/新架构、加中文(i18n)、构建、打 tag 或发布时使用。涵盖：构建环境约束、macOS 部署目标与架构改造、Sparkle 本地 vendoring 绕过代理、String Catalog 中文本地化、版本号/ appcast/README 同步、以及因 git 协议被代理拦截而改用 GitHub MCP 推送与打 tag 的流程。
---

# Compositor 工程开发 Skill

Compositor 是一款 macOS 原生图像编辑器（合成/后期），Swift（SwiftUI + AppKit，部分像素操作用 C），fork 自 `robbietilton/Compositor`，本 fork 仓库为 `g-star1024/Compositor`。

原项目要求 **macOS 26 + 仅 Apple Silicon**，本 fork 已改造为 **macOS 14+ 通用架构（arm64 + x86_64）** 并新增简体中文。

## 关键事实（先读）

- 技术栈：Swift / SwiftUI / AppKit / Metal + 少量 C；自动更新用 **Sparkle 2.10.0+**（SPM 远程包，指向 `github.com/sparkle-project/Sparkle`）。
- 当前部署目标：`MACOSX_DEPLOYMENT_TARGET = 14.0`（原为 26.0）。
- 架构：`ARCHS = "arm64 x86_64"`（原为仅 `arm64`）。
- 版本号来源：Xcode 工程 `Compositor.xcodeproj/project.pbxproj` 的 build settings `MARKETING_VERSION`（市场版本，如 `1.5.0`）与 `CURRENT_PROJECT_VERSION`（构建号，如 `42`）。`Config/Info.plist` **不含**显式版本键，由 Xcode 从 build settings 注入。
- 发布：Sparkle 自动更新 + `scripts/release.sh`（需 Developer ID 证书 + `notarytool` 凭据 + `create-dmg`），本环境无法签名公证。

## 本地构建（重要：本机环境约束）

本机（WorkBuddy 沙箱）的代理**只允许 `api.github.com` 与 `codeload.github.com` / `release-assets.githubusercontent.com`，禁止直连 `github.com` 的 git 协议**。因此：

1. `git clone` / `git push` 到 `github.com` 会失败（CONNECT 502）。获取源码请用 GitHub API tarball：
   `curl -sSL "https://api.github.com/repos/g-star1024/Compositor/tarball/<ref>" -o c.tgz` 然后解包。
2. Sparkle 通过 SPM 远程拉取会被代理拦截。本地构建验证时**临时 vendoring**：把 `https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-for-Swift-Package-Manager.zip` 下载到本地，解包为 `Sparkle.xcframework`，在仓库内建 `Vendor/SparkleLocal/`（含一个指向该 xcframework 的 `binaryTarget` Package.swift），并把 `project.pbxproj` 里的 `XCRemoteSwiftPackageReference "Sparkle"` 临时改成 `XCLocalSwiftPackageReference` + `relativePath = "Vendor/SparkleLocal"`。**此 vendoring 仅用于本地验证，提交/发版时必须还原为远程 Sparkle 引用，且不要提交 `Vendor/`**——用户的机器有 github 访问，远程引用即可正常构建。
3. Xcode 16.2（macOS 15 SDK）。因为 SDK 是 15，部署目标不能高于 15，这也是为何要把 26.0 降到 14.0 才能在本地编译。
4. 构建命令：
   `xcodebuild -project Compositor.xcodeproj -scheme Compositor -configuration Debug -destination 'platform=macOS' build`
   验证通用架构：`file Compositor.app/Contents/MacOS/Compositor` 应同时含 `x86_64` 与 `arm64`。

## 部署目标 / 架构改造铁律

- 部署目标保持 **≥ 14.0**；任何使用 macOS 15/26 独占 API 的地方必须用 `@available(macOS 15, *)`（或更高）守卫，并提供 14.0 可用的回退路径。
- 架构保持 **`arm64 x86_64` 通用**；禁止改回仅 `arm64`（除非明确放弃 Intel 支持）。
- 升级部署目标前，先 `xcodebuild build` 跑一遍，按编译器报的 availability 错误逐个修复。

## 本地化（中文 i18n）

- 体系：使用 **String Catalog**（`Compositor/Localizable.xcstrings`），development language = English（Base），目标语言 `zh-Hans`。
- SwiftUI 的 `Text("字面量")` / `Button("字面量")` / `.navigationTitle("字面量")` 会自动查 catalog，无需改调用；只需保证 UI 文案用**字符串字面量**。
- 动态拼接的字符串（如 `"\(n) 个图层"`）用 `String(localized:)` 并在 catalog 中加入对应 key 与 zh-Hans 译文。
- 严禁在源码里写死面向用户的英文/中文混排；所有面向用户文案走 catalog。
- 新增 UI 文案时必须同步加 key + zh-Hans 译文，否则视为未完成。

## 版本号 / 发版

- 升级版本：改 `Compositor.xcodeproj/project.pbxproj` 的 `MARKETING_VERSION` 与 `CURRENT_PROJECT_VERSION`，并同步 `appcast.xml`（version + sparkle 下载/签名信息）、`README.md`（Requirements/Building）。
- 若开启 Sparkle 自动更新，需把 `Info.plist` 的 `SUFeedURL` 指向本 fork 的 appcast 原始地址，并**重新生成 `SUPublicEDKey`**（上游的 key 不属于本 fork）。不改则自动更新不可用，但不影响手动安装。
- 语义化版本：新增系统/架构支持与本地化属兼容增强，用 minor 位（如 1.4.6 → 1.5.0）。

## 打 tag 与推送（本机特殊流程）

因 `git` 直连 `github.com` 被代理拦截，**不能用 `git push`**。改用已连接的 GitHub MCP：

1. 用 `mcp__github__push_files` 把改动文件作为一次 commit 推到 fork 的 `main`（或发版分支）。注意**只推源码/文档改动**，**不要推 `Vendor/` 与本地 Sparkle 引用**——`project.pbxproj` 推之前要还原 Sparkle 为远程引用（保留部署目标 14 + 通用架构）。
2. 用 GitHub Git Data API（走 `api.github.com`，代理可达）创建 tag：先 `POST /repos/g-star1024/Compositor/git/refs` 需要知道目标 commit SHA（可由 push_files 返回或 `GET /repos/.../git/refs/heads/main` 取得），再 `POST .../git/tags`（annotated tag 对象）+ `POST .../git/refs` 建 `refs/tags/vX.Y.Z`。
3. 可选：用 `POST /repos/g-star1024/Compositor/releases` 建 GitHub Release，附未签名构建产物（本环境无法签名，仅作归档）。

## 代码风格（对齐上游）

- 美式拼写（"color" 非 "colour"），SwiftUI + AppKit，像素操作用 C。
- 改动时匹配周围的命名、注释密度与风格。
- 项目文件格式见 `docs/project-format.md`；保存结构变化时需同步 `ProjectManifest.current` 与文档里的格式版本。
