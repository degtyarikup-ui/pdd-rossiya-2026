import test from 'node:test';
import assert from 'node:assert/strict';
import { verifyIdentity } from './user_auth.js';

const webClient = '513938972930-a7sh1di6odgf77ijltu31lvpuhijcis1.apps.googleusercontent.com';
const originalFetch = globalThis.fetch;
test('web access tokens preserve the Google account with an Android allowlist', async () => {
  try {
    for (const aud of [webClient, 'android-client']) {
      globalThis.fetch = async url => Response.json(String(url).includes('tokeninfo')
        ? { aud, sub: '123', expires_in: 3600, email: 'test@example.com', email_verified: 'true' }
        : { sub: '123', name: 'Test', email_verified: true });
      const user = await verifyIdentity({ provider: 'google', credential: 'test-access-token' },
        { GOOGLE_ANDROID_CLIENT_IDS: 'android-client' });
      assert.equal(user.id, 'google_123');
      assert.equal(user.email, 'test@example.com');
    }
    globalThis.fetch = async () => Response.json({ aud: 'foreign-client', sub: '123', expires_in: 3600 });
    await assert.rejects(verifyIdentity({ provider: 'google', credential: 'test-access-token' },
      { GOOGLE_ANDROID_CLIENT_IDS: 'android-client' }), /wrong client/);
    globalThis.fetch = async url => Response.json(String(url).includes('tokeninfo')
      ? { aud: webClient, sub: '123', expires_in: 0 } : { sub: '123' });
    await assert.rejects(verifyIdentity({ provider: 'google', credential: 'test-access-token' }, {}), /invalid credential/);
    globalThis.fetch = async url => Response.json(String(url).includes('tokeninfo')
      ? { aud: webClient, sub: '123', expires_in: 3600 } : { sub: 'other' });
    await assert.rejects(verifyIdentity({ provider: 'google', credential: 'test-access-token' }, {}), /invalid credential/);
  } finally { globalThis.fetch = originalFetch; }
});
