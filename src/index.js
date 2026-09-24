// The public site is static, but the edge worker owns redirects for URLs from
// the pre-WordPress site. Keep those URLs out of the asset namespace so search
// engines and old bookmarks land on the public home page.
const LEGACY_HOME_PATHS = new Set([
  '/index.html',
  '/about.html',
  '/feedback.html',
  '/rescue.html',
]);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (LEGACY_HOME_PATHS.has(url.pathname)) {
      return Response.redirect(`${url.origin}/`, 301);
    }

    return env.ASSETS.fetch(request);
  },
};
