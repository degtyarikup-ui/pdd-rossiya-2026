import { test } from 'node:test';
import assert from 'node:assert/strict';
import { gameProfile } from './game_profile.js';

test('ranking derives premium from active server entitlements and omits private fields', () => {
  const now = Date.parse('2026-10-10T00:00:00Z');
  const user = { id: 'private', email: 'private@example.test', avatarUrl: 'https://example.test/avatar.jpg',
    entitlements: { appstore: { expiresAt: '2026-11-10T00:00:00Z' } } };
  assert.deepEqual(gameProfile(user, now), { isPremium: true, avatarUrl: user.avatarUrl });
  assert.deepEqual(gameProfile(user, Date.parse('2026-12-10T00:00:00Z')), { isPremium: false, avatarUrl: user.avatarUrl });
  assert.equal(user.isPremium, undefined, 'public metadata must not mutate stored users');
});
test('chosen cone and missing or unsafe provider pictures use the local avatar', () => {
  assert.deepEqual(gameProfile({ useDefaultAvatar: true, avatarUrl: 'https://example.test/a.jpg' }), { isPremium: false, avatarUrl: null });
  assert.deepEqual(gameProfile(null), { isPremium: false, avatarUrl: null });
  assert.equal(gameProfile({ avatarUrl: 'http://example.test/a.jpg' }).avatarUrl, null);
});
