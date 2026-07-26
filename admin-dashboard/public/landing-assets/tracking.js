// EBTL public landing-page tracking.
//
// Google Tag Manager is the only vendor loader in this file. GTM owns the GA4,
// Meta Pixel, Microsoft Clarity, and future Snapchat tags. Keeping the loader
// in landing.html's asset graph (rather than the React SPA entry point) ensures
// employee login, dashboard, admin, and prep screens are never instrumented.
(function () {
  var host = location.hostname;
  var isLocal =
    host === 'localhost' ||
    host === '127.0.0.1' ||
    host === '0.0.0.0' ||
    host === '';

  if (isLocal) return;

  window.dataLayer = window.dataLayer || [];

  fetch('/api/public-config', { cache: 'no-store' })
    .then(function (response) {
      if (!response.ok) throw new Error('Public config unavailable');
      return response.json();
    })
    .then(function (config) {
      if (!config || config.environment !== 'production') return;

      var containerId = String(
        (config.tracking && config.tracking.gtmContainerId) || '',
      ).trim();

      if (!/^GTM-[A-Z0-9]+$/.test(containerId)) return;

      loadGtm(containerId);
      pushEvent('landing_page_ready', {
        page_type: 'marketing_landing',
      });
      wireEvents();
    })
    .catch(function () {
      // Tracking is best-effort and must never interfere with the landing page.
    });

  function pushEvent(eventName, parameters) {
    window.dataLayer.push(
      Object.assign(
        {
          event: eventName,
        },
        parameters || {},
      ),
    );
  }

  function loadGtm(containerId) {
    window.dataLayer.push({
      'gtm.start': new Date().getTime(),
      event: 'gtm.js',
    });

    var script = document.createElement('script');
    script.async = true;
    script.src =
      'https://www.googletagmanager.com/gtm.js?id=' +
      encodeURIComponent(containerId);
    document.head.appendChild(script);
  }

  function placementFor(element) {
    if (element.closest('.hero')) return 'hero';
    if (element.closest('#download-app')) return 'download_section';
    if (element.closest('.site-nav')) return 'navigation';
    return 'landing';
  }

  function linkDestination(link) {
    var href = String(link.getAttribute('href') || '');
    if (href.indexOf('play.google.com') !== -1) return 'google_play';
    if (href.indexOf('apps.apple.com') !== -1) return 'app_store';
    return 'app_link';
  }

  function wireEvents() {
    document.querySelectorAll('.app-link').forEach(function (link) {
      link.addEventListener('click', function () {
        pushEvent('app_download_click', {
          link_destination: linkDestination(link),
          placement: placementFor(link),
        });
      });
    });

    document
      .querySelectorAll('.primary-cta, .secondary-cta')
      .forEach(function (cta) {
        cta.addEventListener('click', function () {
          if (cta.classList.contains('app-link')) return;

          pushEvent('cta_click', {
            cta_label: (cta.textContent || '').trim().slice(0, 60),
            placement: placementFor(cta),
          });
        });
      });

    var milestones = [25, 50, 75, 100];
    var fired = {};
    var onScroll = function () {
      var doc = document.documentElement;
      var scrollable = doc.scrollHeight - window.innerHeight;
      if (scrollable <= 0) return;

      var percent = Math.min(
        100,
        Math.round((window.scrollY / scrollable) * 100),
      );

      milestones.forEach(function (milestone) {
        if (percent >= milestone && !fired[milestone]) {
          fired[milestone] = true;
          pushEvent('scroll_depth', {
            percent_scrolled: milestone,
          });
        }
      });

      if (fired[100]) window.removeEventListener('scroll', onScroll);
    };

    window.addEventListener('scroll', onScroll, { passive: true });
  }
})();
