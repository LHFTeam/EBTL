// EBTL landing page interactions.
// Replace APP_LINK_PLACEHOLDER once the App Store / Google Play URL is ready.
const APP_LINK = "APP_LINK_PLACEHOLDER";
const root = document.documentElement;

window.addEventListener("load", () => {
  document.body.classList.add("is-ready");
});

document.querySelectorAll(".app-link").forEach((link) => {
  link.setAttribute("href", APP_LINK);
});

document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
  anchor.addEventListener("click", (event) => {
    const targetId = anchor.getAttribute("href");
    if (!targetId || targetId === "#") return;

    const target = document.querySelector(targetId);
    if (!target) return;

    event.preventDefault();
    target.scrollIntoView({ behavior: "smooth", block: "start" });
  });
});

const updateScrollProgress = () => {
  const hero = document.querySelector(".hero");
  if (!hero) return;

  const progress = Math.min(1, Math.max(0, window.scrollY / Math.max(1, hero.offsetHeight)));
  root.style.setProperty("--scroll-progress", progress.toFixed(4));
};

updateScrollProgress();
window.addEventListener("scroll", updateScrollProgress, { passive: true });
window.addEventListener("resize", updateScrollProgress);

const revealObserver = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add("is-visible");
      revealObserver.unobserve(entry.target);
    }
  });
}, {
  threshold: 0.18,
  rootMargin: "0px 0px -8% 0px"
});

document.querySelectorAll(".reveal-on-scroll").forEach((element) => {
  revealObserver.observe(element);
});
