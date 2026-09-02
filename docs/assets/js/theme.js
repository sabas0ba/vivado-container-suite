(() => {
  const root = document.documentElement;
  const toggle = document.querySelector(".theme-toggle");
  const media = window.matchMedia("(prefers-color-scheme: dark)");

  const storedTheme = () => {
    try {
      return localStorage.getItem("vvd-docs-theme");
    } catch (_) {
      return null;
    }
  };

  const applyTheme = (theme, persist) => {
    root.dataset.theme = theme;
    if (toggle) {
      toggle.textContent = theme === "dark" ? "Light" : "Dark";
      toggle.setAttribute(
        "aria-label",
        theme === "dark" ? "ライトテーマに切り替える" : "ダークテーマに切り替える",
      );
    }
    if (persist) {
      try {
        localStorage.setItem("vvd-docs-theme", theme);
      } catch (_) {}
    }
  };

  applyTheme(storedTheme() || (media.matches ? "dark" : "light"), false);

  toggle?.addEventListener("click", () => {
    applyTheme(root.dataset.theme === "dark" ? "light" : "dark", true);
  });

  media.addEventListener("change", (event) => {
    if (!storedTheme()) applyTheme(event.matches ? "dark" : "light", false);
  });
})();
