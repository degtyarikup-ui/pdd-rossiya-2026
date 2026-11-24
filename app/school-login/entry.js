// This entry lets school SSO ship independently of the current public app build.
(() => {
  const script = document.currentScript;
  const query = new URLSearchParams(location.search);
  const valid = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
  let school = valid(query.get('school_login')) && valid(query.get('school_state'));
  if (!school && location.hash.startsWith('#pdd-oauth=')) {
    try {
      const pending = JSON.parse(sessionStorage.getItem('pdd_web_oauth_pending'));
      school = valid(pending?.school_login) && valid(pending?.school_state);
    } catch { /* A normal app visit does not need browser storage. */ }
  }
  const bootstrap = document.createElement('script');
  bootstrap.async = true;
  bootstrap.src = school ? script.dataset.school : script.dataset.app;
  document.head.appendChild(bootstrap);
})();
