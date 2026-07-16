import Foundation

/// 内联默认主题（templates/、static/）。通过 Bundle 或 fallback 路径读取。
public enum EmbeddedTheme {
    /// 返回默认主题在磁盘上的路径（必要时从内嵌数据展开）。
    public static func materialize(targetDirectory: String) {
        let fm = FileManager.default
        if fm.fileExists(atPath: (targetDirectory as NSString).appendingPathComponent("theme.yaml")) {
            return
        }
        FSUtil.ensureDirectory(targetDirectory)
        FSUtil.ensureDirectory((targetDirectory as NSString).appendingPathComponent("templates"))
        FSUtil.ensureDirectory((targetDirectory as NSString).appendingPathComponent("static/css"))
        FSUtil.ensureDirectory((targetDirectory as NSString).appendingPathComponent("static/js"))
        for (name, content) in templates { FSUtil.writeText(content, to: (targetDirectory as NSString).appendingPathComponent("templates/\(name)")) }
        for (name, content) in staticFiles { FSUtil.writeText(content, to: (targetDirectory as NSString).appendingPathComponent("static/\(name)")) }
        FSUtil.writeText(themeYAML, to: (targetDirectory as NSString).appendingPathComponent("theme.yaml"))
    }

    public static let themeYAML = """
    name: default
    version: 1.0.0
    description: SkycBlog 内置默认主题
    author: SkycBlog Team
    config:
      colors:
        primary: "#3b82f6"
        background: "#ffffff"
        text: "#1f2937"
        accent: "#ef4444"
      menu:
        - { title: "首页", url: "/" }
        - { title: "归档", url: "/archives/" }
        - { title: "相册", url: "/albums/" }
        - { title: "关于", url: "/about/" }
      paginationSize: 10
    """

    /// 公共 HTML 框架。
    private static let htmlShell = """
    <!DOCTYPE html>
    <html lang="{{site.language}}">
    <head>
      <meta charset="UTF-8"/>
      <meta name="viewport" content="width=device-width, initial-scale=1"/>
      <meta name="description" content="{{site.description}}"/>
      <link rel="alternate" type="application/rss+xml" title="{{site.title}}" href="/rss.xml"/>
      <link rel="stylesheet" href="/static/css/main.css"/>
      <title>{{site.title}}</title>
    </head>
    <body>
    """

    private static let htmlTail = """
    <footer class="site-footer">
      <div class="container">
        <p>© {{year}} {{site.title}} · Powered by <a href="https://github.com/skycblog/skycblog">SkycBlog</a></p>
      </div>
    </footer>
    </body>
    </html>
    """

    private static let siteHeader = """
    <header class="site-header">
      <div class="container">
        <a class="site-title" href="/">{{site.title}}</a>
        <nav class="site-nav">
        {{#each theme.menu}}
          <a href="{{url}}">{{title}}</a>
        {{/each}}
        </nav>
      </div>
    </header>
    """

    public static let templates: [(String, String)] = [
        ("index.html", """
        \(htmlShell)
        \(siteHeader)
        <main class="container">
          <section class="post-list">
            {{#each posts}}
            <article class="post-card">
              <h2 class="post-title"><a href="{{url}}">{{title}}</a></h2>
              <div class="post-meta">
                <time datetime="{{isoDate}}">{{dateString}}</time>
                <span class="tags">{{#each tags}}<span class="tag">#{{this}}</span> {{/each}}</span>
              </div>
              {{#if cover}}<img class="cover" src="{{cover}}" alt="{{title}}"/>{{/if}}
              <p class="excerpt">{{excerpt}}</p>
              <a class="read-more" href="{{url}}">阅读全文 →</a>
            </article>
            {{/each}}
          </section>
          <nav class="pagination">
            {{#if hasPrev}}<a class="prev" href="/page/{{pageIndex}}/">← 上一页</a>{{/if}}
            <span class="page-info">第 {{pageIndex}} / {{pageCount}} 页</span>
            {{#if hasNext}}<a class="next" href="/page/{{pageIndex}}/">下一页 →</a>{{/if}}
          </nav>
        </main>
        \(htmlTail)
        """),
        ("post.html", """
        \(htmlShell)
        \(siteHeader)
        <main class="container">
          <article class="post">
            <header class="post-header">
              <h1 class="post-title">{{title}}</h1>
              <div class="post-meta">
                <time datetime="{{isoDate}}">{{dateString}}</time>
                <span class="tags">{{#each tags}}<a class="tag" href="/tags/{{this}}/">#{{this}}</a> {{/each}}</span>
                <span class="categories">{{#each categories}}<a href="/categories/{{this}}/">{{this}}</a> {{/each}}</span>
              </div>
            </header>
            <div class="post-content">
              {{{content}}}
            </div>
            <footer class="post-footer">
              <a href="/">← 返回首页</a>
            </footer>
          </article>
        </main>
        \(htmlTail)
        """),
        ("page.html", """
        \(htmlShell)
        \(siteHeader)
        <main class="container">
          <h1>{{title}}</h1>
          <div class="page-content">{{{content}}}</div>
        </main>
        \(htmlTail)
        """),
        ("archives.html", """
        \(htmlShell)
        \(siteHeader)
        <main class="container">
          <h1>归档</h1>
          <div class="archives">
            {{#each archives}}
            <section class="archive-year">
              <h2>{{year}}</h2>
              <ul>
                {{#each posts}}
                <li>
                  <time>{{dateString}}</time>
                  <a href="{{url}}">{{title}}</a>
                </li>
                {{/each}}
              </ul>
            </section>
            {{/each}}
          </div>
        </main>
        \(htmlTail)
        """),
        ("tag.html", """
        \(htmlShell)
        \(siteHeader)
        <main class="container">
          {{#if tag}}<h1>标签：{{tag.name}}</h1>{{/if}}
          {{#if category}}<h1>分类：{{category.name}}</h1>{{/if}}
          {{#if tags}}
          <h1>标签</h1>
          <div class="tag-cloud">
            {{#each tags}}
            <a class="tag" href="{{url}}">{{name}} <span class="count">({{count}})</span></a>
            {{/each}}
          </div>
          {{/if}}
          <ul class="post-list">
            {{#each posts}}
            <li>
              <time>{{dateString}}</time>
              <a href="{{url}}">{{title}}</a>
            </li>
            {{/each}}
          </ul>
        </main>
        \(htmlTail)
        """),
        ("category.html", """
        \(htmlShell)
        \(siteHeader)
        <main class="container">
          <h1>分类：{{category.name}}</h1>
          <ul class="post-list">
            {{#each posts}}
            <li>
              <time>{{dateString}}</time>
              <a href="{{url}}">{{title}}</a>
            </li>
            {{/each}}
          </ul>
        </main>
        \(htmlTail)
        """),
        ("tags.html", """
        \(htmlShell)
        \(siteHeader)
        <main class="container">
          <h1>标签</h1>
          <div class="tag-cloud">
            {{#each tags}}
            <a class="tag" href="{{url}}">{{name}} <span class="count">({{count}})</span></a>
            {{/each}}
          </div>
        </main>
        \(htmlTail)
        """),
        ("albums.html", """
        \(htmlShell)
        \(siteHeader)
        <main class="container">
          <h1>相册</h1>
          <div class="album-grid">
            {{#each albums}}
            <a class="album-card" href="{{url}}">
              <h2>{{title}}</h2>
              <p>{{excerpt}}</p>
            </a>
            {{/each}}
          </div>
        </main>
        \(htmlTail)
        """),
        ("album.html", """
        \(htmlShell)
        \(siteHeader)
        <main class="container">
          <article class="album-detail">
            <h1>{{album.title}}</h1>
            <div class="album-content">{{{album.content}}}</div>
            <div class="media-grid">
              {{#each media}}
              <figure class="media-item" data-type="{{type}}">
                <img class="media-thumb" src="{{url}}" loading="lazy" data-full="{{url}}" data-exif="{{exifSummary}}" alt="{{filename}}"/>
                {{#if exifSummary}}<figcaption>{{exifSummary}}</figcaption>{{/if}}
              </figure>
              {{/each}}
            </div>
          </article>
          <div class="lightbox" id="lightbox" style="display:none">
            <span class="lightbox-close">&times;</span>
            <img id="lightbox-img" alt=""/>
            <div class="lightbox-exif" id="lightbox-exif"></div>
          </div>
        </main>
        <script src="/static/js/lightbox.js"></script>
        \(htmlTail)
        """),
        ("404.html", """
        \(htmlShell)
        \(siteHeader)
        <main class="container not-found">
          <h1>404</h1>
          <p>页面不存在或已被移除。</p>
          <a href="/">返回首页</a>
        </main>
        \(htmlTail)
        """),
    ]

    public static let staticFiles: [(String, String)] = [
        ("css/main.css", cssMain),
        ("js/lightbox.js", jsLightbox),
    ]

    public static let cssMain = """
    :root {
      --color-bg: #ffffff;
      --color-text: #1f2937;
      --color-primary: #3b82f6;
      --color-muted: #6b7280;
      --color-border: #e5e7eb;
      --color-card: #f9fafb;
      --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", Helvetica, Arial, sans-serif;
      --font-mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      --max-width: 760px;
    }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; background: var(--color-bg); color: var(--color-text); font-family: var(--font-sans); line-height: 1.7; -webkit-font-smoothing: antialiased; }
    a { color: var(--color-primary); text-decoration: none; }
    a:hover { text-decoration: underline; }
    .container { max-width: var(--max-width); margin: 0 auto; padding: 0 1rem; }
    .site-header { border-bottom: 1px solid var(--color-border); padding: 1rem 0; background: #fff; position: sticky; top: 0; z-index: 100; }
    .site-header .container { display: flex; align-items: center; justify-content: space-between; }
    .site-title { font-size: 1.25rem; font-weight: 600; color: var(--color-text); }
    .site-nav a { margin-left: 1rem; color: var(--color-muted); }
    .site-nav a:hover { color: var(--color-primary); }
    main { padding: 2rem 0; min-height: 60vh; }
    .post-list { display: flex; flex-direction: column; gap: 1.5rem; }
    .post-card { padding: 1.25rem; border: 1px solid var(--color-border); border-radius: 8px; background: var(--color-card); }
    .post-title { margin: 0 0 .5rem 0; font-size: 1.25rem; }
    .post-meta { color: var(--color-muted); font-size: .9rem; margin-bottom: .5rem; }
    .post-meta .tag { color: var(--color-primary); margin-right: .35rem; }
    .post-card .cover { width: 100%; max-height: 240px; object-fit: cover; border-radius: 4px; margin-bottom: .5rem; }
    .excerpt { color: var(--color-muted); }
    .read-more { display: inline-block; margin-top: .5rem; }
    .post { background: #fff; }
    .post-header { margin-bottom: 1.5rem; }
    .post-title { font-size: 1.75rem; margin: 0 0 .5rem 0; }
    .post-content { font-size: 1rem; }
    .post-content img { max-width: 100%; border-radius: 4px; }
    .post-content pre { background: #1f2937; color: #f3f4f6; padding: 1rem; border-radius: 6px; overflow-x: auto; font-family: var(--font-mono); }
    .post-content code { background: #f3f4f6; padding: 0 .25rem; border-radius: 3px; font-family: var(--font-mono); }
    .post-content pre code { background: transparent; padding: 0; }
    .post-content blockquote { border-left: 4px solid var(--color-primary); padding: 0 1rem; color: var(--color-muted); margin: 1rem 0; }
    .post-content table { border-collapse: collapse; width: 100%; }
    .post-content th, .post-content td { border: 1px solid var(--color-border); padding: .5rem; }
    .post-content h1, .post-content h2, .post-content h3 { margin-top: 1.5rem; }
    .post-content ul, .post-content ol { padding-left: 1.5rem; }
    .pagination { display: flex; justify-content: space-between; align-items: center; margin-top: 2rem; }
    .pagination .page-info { color: var(--color-muted); }
    .archives section.archive-year { margin-bottom: 1.5rem; }
    .archives ul { list-style: none; padding: 0; }
    .archives li { display: flex; gap: 1rem; padding: .25rem 0; }
    .archives time { color: var(--color-muted); min-width: 6em; }
    .tag-cloud { display: flex; flex-wrap: wrap; gap: .5rem; }
    .tag-cloud .tag { padding: .25rem .5rem; background: var(--color-card); border: 1px solid var(--color-border); border-radius: 4px; }
    .tag-cloud .count { color: var(--color-muted); font-size: .85em; }
    .album-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 1rem; }
    .album-card { padding: 1rem; border: 1px solid var(--color-border); border-radius: 8px; }
    .media-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 1rem; }
    .media-item { margin: 0; }
    .media-thumb { width: 100%; height: 200px; object-fit: cover; border-radius: 6px; cursor: zoom-in; }
    .media-item figcaption { font-size: .8rem; color: var(--color-muted); padding: .25rem 0; }
    .lightbox { position: fixed; inset: 0; background: rgba(0,0,0,0.9); display: flex; align-items: center; justify-content: center; flex-direction: column; z-index: 9999; }
    .lightbox img { max-width: 90%; max-height: 80vh; }
    .lightbox-exif { color: #fff; padding: .5rem; font-size: .9rem; }
    .lightbox-close { position: absolute; top: 1rem; right: 1rem; color: #fff; font-size: 2rem; cursor: pointer; }
    .site-footer { border-top: 1px solid var(--color-border); padding: 1.5rem 0; color: var(--color-muted); font-size: .9rem; text-align: center; }
    .not-found { text-align: center; padding: 4rem 0; }
    .not-found h1 { font-size: 4rem; margin: 0; }
    """

    public static let jsLightbox = """
    (function() {
      const lb = document.getElementById('lightbox');
      if (!lb) return;
      const img = document.getElementById('lightbox-img');
      const exifEl = document.getElementById('lightbox-exif');
      document.querySelectorAll('.media-thumb').forEach(function(t) {
        t.addEventListener('click', function() {
          img.src = t.dataset.full;
          exifEl.textContent = t.dataset.exif || '';
          lb.style.display = 'flex';
        });
      });
      lb.addEventListener('click', function(e) {
        if (e.target === lb || e.target.classList.contains('lightbox-close')) {
          lb.style.display = 'none';
        }
      });
      document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') lb.style.display = 'none';
      });
    })();
    """
}
