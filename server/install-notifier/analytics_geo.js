// Country filtering defines the share denominator; searching only narrows rows.
export function selectGeoRows(input, options = {}) {
  const { country = 'all', query = '', sort = 'accounts', descending = true } = options;
  const size = Math.max(1, Math.min(50, Number(options.pageSize) || 8));
  const field = ['accounts', 'active7', 'premium', 'name'].includes(sort) ? sort : 'accounts';
  const countryRows = (input || []).filter(r => country === 'all' || r.country === country);
  const baseTotal = countryRows.reduce((sum, r) => sum + (Number(r.accounts) || 0), 0);
  const needle = String(query).trim().toLocaleLowerCase('ru');
  const rows = countryRows.filter(r => !needle || String(r.search || r.label || r.name).toLocaleLowerCase('ru').includes(needle));
  rows.sort((a, b) => {
    const names = String(a.label || a.name).localeCompare(String(b.label || b.name), 'ru');
    const diff = field === 'name' ? names : (Number(a[field]) || 0) - (Number(b[field]) || 0);
    return (descending ? -diff : diff) || names || String(a.country).localeCompare(String(b.country));
  });
  const pages = Math.max(1, Math.ceil(rows.length / size));
  const page = Math.max(0, Math.min(pages - 1, Math.floor(Number(options.page) || 0)));
  const start = page * size;
  return { rows: rows.slice(start, start + size), count: rows.length, baseTotal, page, pages, start, end: Math.min(start + size, rows.length) };
}
