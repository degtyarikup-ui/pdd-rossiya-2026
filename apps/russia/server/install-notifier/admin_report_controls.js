// Controls used by the Analytics and Economy reports in the admin shell.
export function reportRefreshButton(id, label) {
  return `<button type="button" class="btn-icon admin-refresh-button" id="${id}" title="${label}" aria-label="${label}" aria-busy="false">
    <svg aria-hidden="true" viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><polyline points="1 20 1 14 7 14"/><path d="M3.51 9a9 9 0 0 1 14.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0 0 20.49 15"/></svg>
  </button>`;
}

export function reportUpdatedLabel(at) {
  return new Date(at).toLocaleString('ru-RU', {
    timeZone: 'Europe/Moscow', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit',
  }) + ' МСК';
}
