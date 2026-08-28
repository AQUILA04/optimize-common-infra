<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="utf-8" />
  <meta name="robots" content="noindex,nofollow" />
  <meta http-equiv="refresh" content="0;url=https://biocollect.optimizesolux.com/" />
  <title>BioCollect</title>
  <#if properties.styles?has_content>
    <#list properties.styles?split(' ') as style>
      <link rel="stylesheet" href="${url.resourcesPath}/${style}" />
    </#list>
  </#if>
</head>
<body>
  <main class="bio-welcome">
    <img src="${url.resourcesPath}/img/logo.svg" alt="" width="56" height="56" />
    <h1>BioCollect</h1>
    <p>Redirection vers la plateforme…</p>
    <a href="https://biocollect.optimizesolux.com/">Continuer</a>
  </main>
  <script>
    window.location.replace("https://biocollect.optimizesolux.com/");
  </script>
</body>
</html>
