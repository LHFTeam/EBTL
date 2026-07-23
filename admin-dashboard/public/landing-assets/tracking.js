// EBTL landing-page marketing/analytics tracking.
//
// Loads pixels only for the platforms configured on the server (via env vars,
// surfaced by GET /api/public-config), and only in production on a non-local
// host. Fires a PageView per platform and forwards key funnel events
// (app-download clicks, CTA clicks, scroll depth) to every active platform.
//
// No IDs are hardcoded here — set META_PIXEL_ID / TIKTOK_PIXEL_ID /
// SNAPCHAT_PIXEL_ID / GA4_MEASUREMENT_ID in the server environment.
(function () {
  var host = location.hostname;
  if (host === 'localhost' || host === '127.0.0.1' || host === '0.0.0.0' || host === '') {
    return; // never track local/dev
  }

  fetch('/api/public-config', { cache: 'no-store' })
    .then(function (response) { return response.json(); })
    .then(function (config) {
      if (!config || config.environment !== 'production') return;
      init(config.tracking || {});
    })
    .catch(function () { /* tracking is best-effort; never break the page */ });

  function init(t) {
    if (t.metaPixelId) initMeta(t.metaPixelId);
    if (t.tiktokPixelId) initTikTok(t.tiktokPixelId);
    if (t.snapchatPixelId) initSnap(t.snapchatPixelId);
    if (t.ga4MeasurementId) initGa4(t.ga4MeasurementId);
    wireEvents();
  }

  // --- Unified event forwarding to every active platform ---------------------
  function track(event, params) {
    params = params || {};
    try { if (window.fbq) window.fbq('trackCustom', event, params); } catch (e) {}
    try { if (window.ttq) window.ttq.track(event, params); } catch (e) {}
    try { if (window.snaptr) window.snaptr('track', event, params); } catch (e) {}
    try { if (window.gtag) window.gtag('event', event, params); } catch (e) {}
  }

  // --- Pixel initializers (official snippets, ID injected) --------------------
  function initMeta(id) {
    !function (f, b, e, v, n, t, s) {
      if (f.fbq) return; n = f.fbq = function () { n.callMethod ? n.callMethod.apply(n, arguments) : n.queue.push(arguments); };
      if (!f._fbq) f._fbq = n; n.push = n; n.loaded = !0; n.version = '2.0'; n.queue = [];
      t = b.createElement(e); t.async = !0; t.src = v; s = b.getElementsByTagName(e)[0]; s.parentNode.insertBefore(t, s);
    }(window, document, 'script', 'https://connect.facebook.net/en_US/fbevents.js');
    window.fbq('init', id);
    window.fbq('track', 'PageView');
  }

  function initTikTok(id) {
    !function (w, d, t) {
      w.TiktokAnalyticsObject = t; var ttq = w[t] = w[t] || [];
      ttq.methods = ['page', 'track', 'identify', 'instances', 'debug', 'on', 'off', 'once', 'ready', 'alias', 'group', 'enableCookie', 'disableCookie', 'holdConsent', 'revokeConsent', 'grantConsent'];
      ttq.setAndDefer = function (t, e) { t[e] = function () { t.push([e].concat(Array.prototype.slice.call(arguments, 0))); }; };
      for (var i = 0; i < ttq.methods.length; i++) ttq.setAndDefer(ttq, ttq.methods[i]);
      ttq.instance = function (t) { for (var e = ttq._i[t] || [], n = 0; n < ttq.methods.length; n++) ttq.setAndDefer(e, ttq.methods[n]); return e; };
      ttq.load = function (e, n) {
        var r = 'https://analytics.tiktok.com/i18n/pixel/events.js'; ttq._i = ttq._i || {}; ttq._i[e] = []; ttq._i[e]._u = r;
        ttq._t = ttq._t || {}; ttq._t[e] = +new Date(); ttq._o = ttq._o || {}; ttq._o[e] = n || {};
        var o = d.createElement('script'); o.type = 'text/javascript'; o.async = !0; o.src = r + '?sdkid=' + e + '&lib=' + t;
        var a = d.getElementsByTagName('script')[0]; a.parentNode.insertBefore(o, a);
      };
      ttq.load(id); ttq.page();
    }(window, document, 'ttq');
  }

  function initSnap(id) {
    (function (e, t, n) {
      if (e.snaptr) return; var a = e.snaptr = function () { a.handleRequest ? a.handleRequest.apply(a, arguments) : a.queue.push(arguments); };
      a.queue = []; var s = 'script'; var r = t.createElement(s); r.async = !0; r.src = n;
      var u = t.getElementsByTagName(s)[0]; u.parentNode.insertBefore(r, u);
    })(window, document, 'https://sc-static.net/scevent.min.js');
    window.snaptr('init', id);
    window.snaptr('track', 'PAGE_VIEW');
  }

  function initGa4(id) {
    var s = document.createElement('script');
    s.async = true;
    s.src = 'https://www.googletagmanager.com/gtag/js?id=' + encodeURIComponent(id);
    document.head.appendChild(s);
    window.dataLayer = window.dataLayer || [];
    window.gtag = function () { window.dataLayer.push(arguments); };
    window.gtag('js', new Date());
    window.gtag('config', id);
  }

  // --- Conversion events on the page -----------------------------------------
  function wireEvents() {
    // App download / store links.
    document.querySelectorAll('.app-link').forEach(function (link) {
      link.addEventListener('click', function () {
        track('AppDownloadClick', { location: 'landing' });
      });
    });

    // Primary/secondary calls to action.
    document.querySelectorAll('.primary-cta, .secondary-cta').forEach(function (cta) {
      cta.addEventListener('click', function () {
        track('CTAClick', { label: (cta.textContent || '').trim().slice(0, 60) });
      });
    });

    // Scroll depth milestones (fired once each).
    var milestones = [25, 50, 75, 100];
    var fired = {};
    var onScroll = function () {
      var doc = document.documentElement;
      var scrollable = doc.scrollHeight - window.innerHeight;
      if (scrollable <= 0) return;
      var percent = Math.min(100, Math.round((window.scrollY / scrollable) * 100));
      milestones.forEach(function (m) {
        if (percent >= m && !fired[m]) {
          fired[m] = true;
          track('ScrollDepth', { depth: m });
        }
      });
      if (fired[100]) window.removeEventListener('scroll', onScroll);
    };
    window.addEventListener('scroll', onScroll, { passive: true });
  }
})();
