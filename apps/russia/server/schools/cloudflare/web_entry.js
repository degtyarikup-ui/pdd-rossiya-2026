// This entry lets school SSO ship independently of the current public app build.
(() => {
  const script = document.currentScript;
  const query = new URLSearchParams(location.search);
  const valid = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
  const group = value => typeof value === 'string' && /^(?:my|[23456789A-HJ-NP-Z]{10}|[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}:[A-Za-z0-9_-]{43})$/.test(value);
  let school = group(query.get('school_group')) || valid(query.get('school_login')) && valid(query.get('school_state'));
  if (!school && location.hash.startsWith('#pdd-oauth=')) {
    try {
      const pending = JSON.parse(sessionStorage.getItem('pdd_web_oauth_pending'));
      school = group(pending?.school_group) || valid(pending?.school_login) && valid(pending?.school_state);
    } catch { /* A normal app visit does not need browser storage. */ }
  }
  // Keep the student profile available when a pupil continues to lessons in this tab.
  try {
    if (group(query.get('school_group'))) sessionStorage.setItem('pdd_school_tab', '1');
    if (!location.search && !location.hash && sessionStorage.getItem('pdd_school_tab') === '1') school = true;
  } catch { /* Invitations still work when browser storage is unavailable. */ }
  const bootstrap = document.createElement('script');
  bootstrap.async = true;
  bootstrap.src = school ? script.dataset.school : script.dataset.app;
  document.head.appendChild(bootstrap);
})();
