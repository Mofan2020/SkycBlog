import Foundation

public enum RSSBuilder {
    public static func build(config: SiteConfig, posts: [Page]) -> String {
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        var items = ""
        for p in posts.prefix(20) {
            let link = base + p.url
            let pub = DateUtil.iso.string(from: p.date)
            let desc = (p.excerpt ?? "").htmlEscaped
            items += """
            <item>
                <title>\(p.title.htmlEscaped)</title>
                <link>\(link)</link>
                <guid isPermaLink="true">\(link)</guid>
                <pubDate>\(pub)</pubDate>
                <description>\(desc)</description>
            </item>

            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
            <title>\(config.title.htmlEscaped)</title>
            <link>\(config.baseURL)</link>
            <description>\(config.description.htmlEscaped)</description>
            <language>\(config.language)</language>
            <lastBuildDate>\(DateUtil.iso.string(from: Date()))</lastBuildDate>
        \(items)</channel>
        </rss>
        """
    }
}

public enum SitemapBuilder {
    public static func build(config: SiteConfig, pages: [Page]) -> String {
        let base = config.baseURL.hasSuffix("/") ? String(config.baseURL.dropLast()) : config.baseURL
        var urls = ""
        for p in pages {
            let link = base + p.url
            urls += """
            <url>
                <loc>\(link)</loc>
                <lastmod>\(DateUtil.iso.string(from: p.date))</lastmod>
                <changefreq>weekly</changefreq>
            </url>
            """
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        \(urls)
        </urlset>
        """
    }
}

public enum SearchIndexBuilder {
    public static func build(pages: [Page]) -> [[String: Any]] {
        return pages.map { p in
            return [
                "title": p.title,
                "url": p.url,
                "excerpt": p.excerpt ?? "",
                "tags": p.tags,
                "date": DateUtil.iso.string(from: p.date),
            ]
        }
    }
}
