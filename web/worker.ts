interface Environment {
    ASSETS: Fetcher;
}

export default {
    async fetch(request: Request, environment: Environment): Promise<Response> {
        const url = new URL(request.url);
        const prefix = "/tools/track-viewer";

        if (url.pathname === prefix) {
            url.pathname = `${prefix}/`;
            return Response.redirect(url.toString(), 308);
        }

        if (url.pathname === "/" || url.pathname === "/index.html") {
            const originURL = new URL(url.pathname + url.search, "https://appsbyonzy.pages.dev");
            const originResponse = await fetch(originURL);
            const marker = "</div></article></div></div></div></section>\n</main>";
            const card = `</div></article><article id="baregps-track-viewer"><h3 class="app-title"><img class="app-icon" src="tools/track-viewer/track-viewer.svg" width="64" height="64" alt="" aria-hidden="true"><span>BareGPS Track Viewer</span></h3><p>Import and explore GPX collections on one map. Compare distance and ascent, focus individual tracks and export the collection as GeoJSON.</p><p class="tool-subtitle">Web · GPX files stay on your device</p><div class="region-actions"><div class="preview-action"><a href="tools/track-viewer/" target="_blank" rel="noopener">Open Track Viewer <span aria-hidden="true">↗</span></a></div></div></article></div></div></div></section>\n</main>`;
            const html = (await originResponse.text())
                .replace("assets/app-icons/route-maker.png", "tools/track-viewer/route-maker.svg")
                .replace(marker, card);
            const headers = new Headers(originResponse.headers);
            headers.delete("content-length");
            headers.set("content-type", "text/html; charset=utf-8");
            headers.set("cache-control", "no-store");
            return new Response(html, {
                status: originResponse.status,
                headers
            });
        }

        if (!url.pathname.startsWith(prefix)) {
            const originURL = new URL(url.pathname + url.search, "https://appsbyonzy.pages.dev");
            return fetch(new Request(originURL, request));
        }

        url.pathname = url.pathname.slice(prefix.length) || "/";
        if (url.pathname === "/" || url.pathname === "/index.html") {
            url.searchParams.set("asset-version", "20261120-truncated-grid-headers");
        }
        const assetResponse = await environment.ASSETS.fetch(new Request(url, request));
        if (url.pathname !== "/" && url.pathname !== "/index.html") {
            return assetResponse;
        }

        const headers = new Headers(assetResponse.headers);
        headers.set("cache-control", "no-store");
        return new Response(assetResponse.body, {
            status: assetResponse.status,
            headers
        });
    }
};
