// EBTL landing page JS
// Replace APP_LINK_PLACEHOLDER below when the final app link is ready.
const APP_LINK = "APP_LINK_PLACEHOLDER";

document.querySelectorAll(".app-link").forEach((link) => {
  link.setAttribute("href", APP_LINK);
});

// Smooth-scroll fallback for older browsers.
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
