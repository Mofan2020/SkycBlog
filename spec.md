## 📦 项目概览

**项目名称**：SkycBlog

**核心定位**：运行于 macOS 15+ 的原生静态博客框架，提供图形化界面（SwiftUI）与命令行工具双模式，支持导入 Hexo/Hugo 主题，生成可部署到 Cloudflare Pages、GitHub Pages 等的静态站点。

**技术底座**：
- 语言：Swift（主应用）
- GUI 框架：SwiftUI（macOS 15+）
- 模板引擎：自建 SwiftUI 风格 DSL（基于 `@resultBuilder`）
- Markdown 解析：Apple SwiftMarkdown 库 + Yams（Front Matter 解析）
- 脚本插件：JavaScriptCore

---

## 🧱 第一部分：核心架构与配置系统

### 1.1 项目初始化
- 提供「新建项目」向导（GUI 窗体和 CLI 命令）
- 生成标准目录结构：
  ```
  my-blog/
  ├── config.yaml          # 主配置文件
  ├── content/             # 所有内容源文件
  │   ├── _posts/          # 博客文章（Hexo 风格）
  │   ├── _drafts/         # 草稿（构建时默认忽略）
  │   ├── pages/           # 独立页面（about、contact 等）
  │   └── albums/          # 相册数据（图片+描述）
  ├── themes/              # 主题目录（可存放多个）
  │   └── my-theme/
  │       ├── templates/   # 模板文件（.html 或 .swift-dsl）
  │       ├── static/      # 主题专用静态资源
  │       └── theme.yaml   # 主题配置文件
  ├── static/              # 全局静态资源（会被复制到输出目录）
  ├── scripts/             # 用户自定义脚本（插件）
  └── output/              # 构建输出目录（可配置）
  ```

### 1.2 配置文件（支持 YAML/TOML/JSON）
- 站点元信息：`title`、`description`、`author`、`language`、`baseURL`
- 构建参数：`outputDir`、`buildDrafts`（是否包含草稿）、`paginationSize`
- 主题配置：`themeName`、`themeConfig`（主题自定义字段，透传给模板）
- 部署配置：`deploy` 字段，包含 `github`、`cloudflare` 等目标平台的认证占位符（实际 Token 存钥匙串）
- 扩展配置：自定义参数，供模板和插件读取

### 1.3 配置优先级
- 默认值 > 全局配置文件 > 命令行参数覆盖（如 `--output ./dist`）

---

## 📝 第二部分：内容管理

### 2.1 Markdown 文件解析
- **Front Matter 解析**：使用 Yams 库解析文件开头的 YAML/TOML/JSON 元数据
- **正文解析**：将 Front Matter 之后的内容交由 SwiftMarkdown 渲染为 HTML
- 支持的元数据字段（标准）：
  - `title`（文章标题）
  - `date`（发布日期，支持 ISO 8601 格式）
  - `tags`（字符串数组）
  - `categories`（字符串数组，支持层级如 `["技术", "Swift"]`）
  - `draft`（布尔值，标记草稿）
  - `layout`（指定使用的模板名称，默认为 `post`）
  - `slug`（自定义 URL 路径）
  - `cover`（封面图片路径）
  - `excerpt`（手动摘要，如未提供则自动截取正文前 150 字）
  - `albums`（相册专用：图片列表、拍摄时间、地点等）

### 2.2 内容类型
- **文章（Posts）**：位于 `content/_posts/`，按时间倒序在首页或归档页展示
- **独立页面（Pages）**：位于 `content/pages/`，如 about.md，通过自定义路径访问（如 `/about`）
- **草稿（Drafts）**：位于 `content/_drafts/`，构建时默认跳过，除非启用 `--buildDrafts` 标志
- **相册（Albums）**：位于 `content/albums/`，每个相册是一个文件夹，内含一个 `index.md`（描述）和若干图片/视频文件，构建时生成相册展示页

### 2.3 标签与分类系统（Taxonomies）
- 自动扫描所有文章的 `tags` 和 `categories` 字段
- 生成标签聚合页（如 `/tags/swift/`）和分类聚合页（如 `/categories/tech/`）
- 支持多级分类（如 `/categories/tech/swift/`）

### 2.4 摘要自动生成
- 若文章未提供 `excerpt` 字段，自动截取正文纯文本前 150 个字符
- 截断点自动在完整单词处（避免截断英文单词或中文乱码）

### 2.5 永久链接（Permalink）
- 支持可配置的 URL 模式，例如：
  - `/:year/:month/:day/:slug/`
  - `/:category/:slug/`
  - `/:slug/`
- 配置文件中的 `permalink` 字段控制全局模式，文章 Front Matter 中的 `slug` 可局部覆盖

### 2.6 相册功能（类似 Apple “照片” App）
- **导入支持**：批量导入图片（JPEG/PNG/GIF/WebP）和视频（MP4/MOV）
- **元数据读取**：自动读取 EXIF 信息（拍摄时间、GPS 坐标、相机型号、镜头参数）
- **相簿管理**：在 GUI 中创建相簿，拖拽分组，支持嵌套相簿（如“旅行/2025/日本”）
- **展示形式**：生成网格布局的相册页，点击图片弹出灯箱（Lightbox）查看原图及 EXIF 信息
- **视频支持**：相册中视频显示为可播放的缩略图，点击后 HTML5 播放器播放

---

## 🎨 第三部分：模板与主题系统

### 3.1 自建 DSL 模板引擎（基于 @resultBuilder）
- **核心功能**：将 SwiftUI 风格的声明式语法编译为 HTML 字符串
- **基础组件**：
  - `HTML`、`Head`、`Body`、`Div`、`Span`、`H1`-`H6`、`P`、`A`、`Img`、`Ul`、`Ol`、`Li`、`Table` 等
  - 条件渲染：`If`、`Else`、`ElseIf`
  - 循环渲染：`ForEach`（用于遍历文章列表）
  - 变量插值：`\(variable)` 语法
  - 布局继承：支持 `BaseLayout` 和 `Content` 插槽（类似 SwiftUI 的 `@ViewBuilder`）
- **自定义组件（Shortcodes）**：用户可在主题中定义可复用的 Swift 结构体作为短代码，在 Markdown 中通过 `{% component_name params %}` 调用

### 3.2 Hexo/Hugo 主题导入适配器
- **目标**：用户下载 Hexo/Hugo 主题后，直接放入 `themes/` 文件夹，框架自动转换并保持展示效果基本一致
- **适配内容**：
  - 模板转换：将 Hexo 的 `.ejs` 或 Hugo 的 `.html` 模板，通过内置转换器映射为 DSL 模板（对于无法映射的部分，记录警告日志并保留原样占位）
  - 配置映射：将 Hexo 的 `_config.yml` 或 Hugo 的 `config.toml` 中的主题相关字段，映射到本框架的主题配置
  - 静态资源：直接复制主题的 `static/` 或 `assets/` 目录到输出文件夹
  - 辅助函数：自动识别 Hexo 的 `_` 开头的辅助函数（如 `_p`、`_link`）并尽量提供等价实现
- **降级处理**：对于无法自动转换的复杂模板，在 GUI 中以「兼容模式」预览，并给出具体修改建议（如高亮不兼容的代码段）

### 3.3 主题开发支持
- **主题预览**：在 GUI 中切换不同主题，实时预览效果（不重新构建全站，仅刷新预览区）
- **主题配置**：每个主题可在 `theme.yaml` 中声明自己的配置字段（如 `colors`、`menu`），GUI 自动生成对应的配置面板

### 3.4 静态资源处理
- 将 `static/` 目录和每个主题的 `static/` 目录合并，复制到输出目录根路径
- 支持文件指纹（如 `style.abc123.css`）用于缓存控制，可配置开启/关闭

---

## 🖥️ 第四部分：macOS GUI 应用（SwiftUI）

### 4.1 主界面布局
- **侧边栏（三栏式）**：
  - 第一栏：站点管理（项目列表 + 新建/打开项目）
  - 第二栏：内容目录树（按类型分组：文章、页面、草稿、相册）
  - 第三栏：主内容区（文章列表或编辑器）
- **顶部工具栏**：包含「构建站点」「预览」「部署」三大按钮，以及当前项目路径显示

### 4.2 文章编辑器
- **双栏布局**：左栏为 Markdown 编辑区（带语法高亮），右栏为实时预览区（渲染后效果）
- **元数据面板**：侧滑抽屉形式，集中管理 Front Matter 字段（标题、标签、分类、日期、封面等）
- **草稿开关**：一键切换草稿状态
- **图片插入**：拖拽图片到编辑器，自动复制到项目 `static/images/` 并生成 Markdown 引用

### 4.3 相册管理器
- **网格视图**：显示所有相簿，点击进入后展示图片/视频缩略图网格
- **导入功能**：从访达拖拽导入，或通过文件选择器批量添加
- **元数据查看**：选中图片后，侧边栏显示 EXIF 信息（拍摄时间、地点、设备等）
- **排序方式**：按拍摄时间、导入时间、文件名排序

### 4.4 站点预览
- **内嵌 WebView**：构建完成后，在应用内直接预览生成的站点
- **热重载**：修改 Markdown 文件或模板后，预览自动刷新（需保存文件触发）
- **设备模拟**：提供 iPhone、iPad、桌面三种尺寸切换预览

### 4.5 设置与偏好
- **全局偏好**：默认输出目录、默认主题、自动保存间隔
- **部署凭证管理**：通过 macOS 钥匙串安全存储 GitHub/Cloudflare Token，提供添加/删除/更新界面
- **主题管理**：浏览已安装主题，从 ZIP 包导入新主题，删除主题

---

## 🏗️ 第五部分：构建与输出

### 5.1 构建流程（顺序执行）
1. **初始化**：读取配置文件，加载主题，准备输出目录（清空或增量）
2. **内容收集**：遍历 `content/` 下所有 Markdown 文件，解析 Front Matter 和正文
3. **分类聚合**：生成标签、分类索引
4. **模板渲染**：将页面数据注入 DSL 模板，生成 HTML 文件
5. **资源复制**：复制静态资源到输出目录
6. **后处理**：生成 RSS、sitemap、搜索索引（JSON）
7. **清理**：删除临时文件

### 5.2 输出产物
- 完整的静态 HTML 文件树
- `rss.xml`（Atom/RSS 2.0 格式，可配置）
- `sitemap.xml`（符合 sitemap 协议）
- `search.json`（包含所有文章标题、链接、摘要、标签，供前端搜索使用）
- `404.html`（自定义 404 页面）

### 5.3 增量构建（v1.1 特性，首版可标记为实验性）
- 维护一个 `.buildcache` 文件，记录每个源文件的修改时间戳和内容哈希
- 构建时仅处理发生变化的文件，以及受其影响的聚合页（如首页、标签页）
- 首版可简单实现：仅检查文件修改时间，若早于上次构建时间则跳过

---

## 🚀 第六部分：部署模块

### 6.1 GitHub Pages 部署
- 支持两种方式：
  1. **Git 推送**：自动将输出目录提交到仓库的 `gh-pages` 分支（或主分支的 `/docs` 文件夹）
  2. **直接上传**：通过 GitHub API 上传构建产物（需 Personal Access Token）
- GUI 中提供「部署到 GitHub」按钮，进度条显示上传状态

### 6.2 Cloudflare Pages 部署
- 通过 Cloudflare API 创建新部署（需 Account ID + API Token）
- 自动上传构建产物（支持直接上传 ZIP 或目录映射）
- 部署完成后，在 GUI 中显示预览链接和部署状态

### 6.3 其他平台
- **Netlify / Vercel**：提供“导出为平台标准包”功能，生成适配这些平台的部署文件夹结构（如 Netlify 的 `_redirects` 文件）

### 6.4 部署配置
- 在项目配置文件中记录部署目标列表（可配置多个，如同时部署到 GitHub Pages 和 Cloudflare）
- 每个目标独立存储认证信息（通过钥匙串）

---

## 🔌 第七部分：插件系统（基于 JavaScriptCore）

### 7.1 插件加载机制
- 启动构建时，扫描项目根目录的 `scripts/` 文件夹
- 加载所有 `.js` 文件，并在 JavaScriptCore 上下文中执行
- 暴露给 JS 的全局对象和方法：
  - `site`：包含站点配置、所有页面列表的只读对象
  - `hook(eventName, callback)`：注册生命周期钩子
  - `log(message)`：向 Swift 主控台输出日志
  - `readFile(path)` / `writeFile(path, content)`：读写文件（仅限于项目目录内）

### 7.2 支持的生命周期钩子
| 钩子名称         | 触发时机                     | 可操作数据                             |
| ---------------- | ---------------------------- | -------------------------------------- |
| `beforeBuild`    | 构建开始前                   | 无（可执行清理等操作）                 |
| `afterReadFiles` | 所有 Markdown 文件解析完成后 | 可修改 `site.pages` 数组               |
| `beforeRender`   | 模板渲染前                   | 可修改每个页面的 `context` 数据        |
| `afterRender`    | 所有 HTML 生成后             | 可修改生成的 HTML 字符串               |
| `afterBuild`     | 构建完成后                   | 可执行额外输出（如生成 JSON 统计文件） |

### 7.3 插件示例（概念）
一个简单的插件可以这样写：
```javascript
hook('afterReadFiles', function(site) {
    site.pages = site.pages.filter(p => p.tags.includes('featured'));
});
```

### 7.4 插件管理
- GUI 中提供“插件列表”页面，显示已加载的脚本文件
- 支持启用/禁用单个插件（通过重命名或添加 `.disabled` 后缀）
- 错误处理：如果某个插件抛出异常，在 GUI 中显示错误信息并继续构建（或中断，由用户配置）

---

## 📦 第八部分：命令行工具（CLI）

- `blog init <name>`：初始化新项目
- `blog new "标题"`：创建新文章（自动生成 Front Matter 模板）
- `blog build`：构建站点（可选参数 `--drafts` 包含草稿）
- `blog serve`：启动本地预览服务器（默认 `http://localhost:8080`）
- `blog deploy`：部署到配置的目标平台
- `blog theme install <url>`：从 URL（Git 仓库或 ZIP）安装主题
- 所有命令均支持 `--config` 指定自定义配置文件路径

---

## 🧪 第九部分：性能与优化

### 9.1 构建性能目标
- 100 篇文章以内：构建时间 < 3 秒（M1 Mac 基准）
- 1000 篇文章：构建时间 < 15 秒

### 9.2 优化策略
- 使用 `DispatchQueue` 并发解析 Markdown 文件
- 模板缓存：将解析后的 DSL 结构缓存，避免重复解析
- 资源去重：相同文件名（哈希一致）的图片只复制一次

### 9.3 输出优化
- 自动压缩 HTML 文件（去除多余空白和注释，可配置）
- 图片优化（可选）：调用 macOS 原生 ImageIO 压缩 PNG/JPEG 质量

---

## 📚 第十部分：文档与用户体验

### 10.1 用户文档
- 新手入门指南（新建项目 → 编写文章 → 选择主题 → 构建 → 部署）
- 主题开发指南（如何制作兼容本框架的主题）
- 插件开发指南（JS API 参考）
- 配置参考（所有配置项说明）

### 10.2 应用内帮助
- 菜单栏“帮助”菜单，指向在线文档
- 设置界面中的“教程”按钮，打开交互式引导

### 10.3 国际化（i18n）
- 应用界面支持英文和中文（简体/繁体）
- 生成的站点支持多语言内容（通过 `language` 配置和 `i18n/` 目录）

---

请完成**全部内容**，确保所有功能真实可用，不允许出现任何占位符功能，除非您无法独立实现，在此情况下，请务必向我**明确告知**，并寻求我的帮助，谢谢