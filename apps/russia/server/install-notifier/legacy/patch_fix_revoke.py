import os
import json
import re

worker_path = '/Users/sergei/Documents/pdd/server/install-notifier/worker.js'
with open(worker_path, 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Update backend revoke-premium endpoint to explicitly set premiumExpiresAt = null
old_revoke = """    if (url.pathname === '/api/admin/users/revoke-premium' && request.method === 'POST') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'bad json' }, 400); }
      const { userId } = body || {};
      if (!userId || !env.INSTALLS) return jsonResponse({ error: 'missing userId' }, 400);

      const raw = await env.INSTALLS.get('user:' + userId);
      if (!raw) return jsonResponse({ error: 'user not found' }, 404);
      const user = JSON.parse(raw);

      user.isPremium = false;
      user.premiumSource = null;
      await env.INSTALLS.put('user:' + userId, JSON.stringify(user));
      return jsonResponse({ ok: true, user });
    }"""

new_revoke = """    if (url.pathname === '/api/admin/users/revoke-premium' && request.method === 'POST') {
      if (!verifyAdminAuth(request, env)) return jsonResponse({ error: 'unauthorized' }, 401);
      let body;
      try { body = await request.json(); } catch (_) { return jsonResponse({ error: 'bad json' }, 400); }
      const { userId } = body || {};
      if (!userId || !env.INSTALLS) return jsonResponse({ error: 'missing userId' }, 400);

      const raw = await env.INSTALLS.get('user:' + userId);
      if (!raw) return jsonResponse({ error: 'user not found' }, 404);
      const user = JSON.parse(raw);

      user.isPremium = false;
      user.premiumSource = null;
      user.premiumExpiresAt = null;
      await env.INSTALLS.put('user:' + userId, JSON.stringify(user));
      return jsonResponse({ ok: true, user });
    }"""

if old_revoke in code:
    code = code.replace(old_revoke, new_revoke, 1)
    print('Updated backend revoke-premium to clear premiumExpiresAt!')
else:
    # Try regex match
    code = re.sub(
        r'user\.isPremium = false;\s*user\.premiumSource = null;',
        'user.isPremium = false;\n      user.premiumSource = null;\n      user.premiumExpiresAt = null;',
        code
    )
    print('Updated backend revoke-premium via regex!')

# 2. Extract ADMIN_CLIENT_JS and fix expiresText logic
pos_js_decl = code.find('const ADMIN_CLIENT_JS = ')
pos_render_decl = code.find('function renderAdminPage()')

if pos_js_decl != -1 and pos_render_decl != -1:
    js_json_literal = code[pos_js_decl + len('const ADMIN_CLIENT_JS = '):pos_render_decl].strip()
    if js_json_literal.endswith(';'):
        js_json_literal = js_json_literal[:-1].strip()

    js_str = json.loads(js_json_literal)

    # Replace expiresText logic in JS
    old_exp_logic = """      let expiresText = '-';
      if (isLifetime) {
        expiresText = '<span style="color:#2BC280;font-weight:700;">Бессрочно</span>';
      } else if (u.premiumExpiresAt) {
        expiresText = formatEventTime(u.premiumExpiresAt);
      }"""

    new_exp_logic = """      let expiresText = '-';
      if (activePrem) {
        if (isLifetime) {
          expiresText = '<span style="color:#2BC280;font-weight:700;">Бессрочно</span>';
        } else if (u.premiumExpiresAt) {
          expiresText = formatEventTime(u.premiumExpiresAt);
        }
      }"""

    if old_exp_logic in js_str:
        js_str = js_str.replace(old_exp_logic, new_exp_logic, 1)
        print('Updated expiresText logic in JS!')

    code = (
        code[:pos_js_decl]
        + 'const ADMIN_CLIENT_JS = ' + json.dumps(js_str) + ';\n'
        + code[pos_render_decl:]
    )

with open(worker_path, 'w', encoding='utf-8') as f:
    f.write(code)

print('Successfully saved worker.js with revoke fix!')
