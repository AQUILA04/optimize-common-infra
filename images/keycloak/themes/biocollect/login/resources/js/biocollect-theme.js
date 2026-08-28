// BioCollect Keycloak login polish — dark palette, landing grid, single-column hero.
document.documentElement.classList.add("pf-v5-theme-dark");

(function () {
  if (!document.body.classList.contains("login-pf")) return;

  if (!document.querySelector(".biocollect-bg-grid")) {
    const grid = document.createElement("div");
    grid.className = "biocollect-bg-grid";
    grid.setAttribute("aria-hidden", "true");
    document.body.prepend(grid);
  }

  document.querySelectorAll(".pf-v5-c-brand, #kc-header").forEach((node) => {
    node.setAttribute("hidden", "hidden");
  });

  const main = document.querySelector(".pf-v5-c-login__main");
  if (!main || main.querySelector(".biocollect-hero")) return;

  const isFrench = (document.documentElement.lang || "fr").toLowerCase().startsWith("fr");
  const tagline = isFrench ? "Collecter, vérifier, décider." : "Collect, verify, decide.";
  const subtitle = isFrench
    ? "Identité terrain, sans compromis."
    : "Field identity, without compromise.";
  const resourcesPath = document.querySelector('link[href*="/login/resources/"]')?.href.replace(/\/css\/.*$/, "") ?? "";

  const hero = document.createElement("div");
  hero.className = "biocollect-hero";
  hero.setAttribute("aria-hidden", "true");
  hero.innerHTML = `
    <div class="biocollect-mark">
      <img src="${resourcesPath}/img/logo.svg" alt="" width="36" height="36" />
    </div>
    <span class="biocollect-slogan-pill">${tagline}</span>
    <p class="biocollect-hero-title">BioCollect</p>
    <p class="biocollect-hero-sub">${subtitle}</p>
  `;
  main.prepend(hero);
})();
