<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="robots" content="noindex,nofollow" />
  <meta http-equiv="refresh" content="0;url=https://biocollect.optimizesolux.com/" />
  <title>BioCollect</title>
  <#-- Pas de ${url.resourcesPath} ici : la page d'accueil Keycloak ne fournit pas l'objet url (erreur 500). Styles et logo sont donc intégrés. -->
  <style>
    :root {
      --bio-bg: #020617;
      --bio-text: #f8fafc;
      --bio-muted: #94a3b8;
      --bio-accent: #3b82f6;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      padding: 1.5rem;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: var(--bio-text);
      background:
        radial-gradient(circle at 12% 10%, rgba(37, 99, 235, 0.38), transparent 34%),
        radial-gradient(circle at 88% 16%, rgba(16, 185, 129, 0.16), transparent 30%),
        var(--bio-bg);
    }
    .bio-welcome { width: min(100%, 24rem); text-align: center; }
    .bio-welcome svg { display: block; margin: 0 auto 1rem; }
    .bio-welcome h1 { margin: 0 0 0.5rem; font-size: 1.75rem; letter-spacing: -0.03em; }
    .bio-welcome p { margin: 0 0 1.25rem; color: var(--bio-muted); line-height: 1.6; }
    .bio-welcome a {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      min-height: 2.75rem;
      padding: 0 1rem;
      border-radius: 0.625rem;
      background: var(--bio-accent);
      color: #fff;
      font-weight: 600;
      text-decoration: none;
    }
    .bio-welcome a:hover { background: #2563eb; }
  </style>
</head>
<body>
  <main class="bio-welcome">
    <svg xmlns="http://www.w3.org/2000/svg" width="56" height="56" viewBox="0 0 64 64" fill="none" aria-hidden="true">
      <rect width="64" height="64" rx="16" fill="#3B82F6"/>
      <path d="M32 14c-2.2 8.5-6.5 14.2-13 17 6.5 2.8 10.8 8.5 13 17 2.2-8.5 6.5-14.2 13-17-6.5-2.8-10.8-8.5-13-17z" fill="#fff" opacity=".95"/>
      <circle cx="32" cy="31" r="5" fill="#fff"/>
    </svg>
    <h1>BioCollect</h1>
    <p>Redirection vers la plateforme…</p>
    <a href="https://biocollect.optimizesolux.com/">Continuer</a>
  </main>
  <script>
    window.location.replace("https://biocollect.optimizesolux.com/");
  </script>
</body>
</html>
