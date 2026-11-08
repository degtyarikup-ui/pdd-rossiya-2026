import { applyEntitlements } from './entitlements.js';

// Public ranking metadata: never include account IDs, email or credentials.
export function gameProfile(user, now = Date.now()) {
  const profile = user ? applyEntitlements({ ...user }, now) : null;
  const photo = profile?.avatarUrl;
  return {
    isPremium: profile?.isPremium === true,
    avatarUrl: !profile?.useDefaultAvatar && typeof photo === 'string' && /^https:\/\//i.test(photo) ? photo : null,
  };
}
