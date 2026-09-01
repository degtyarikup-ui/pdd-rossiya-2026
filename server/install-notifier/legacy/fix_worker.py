import re

def main():
    filepath = 'worker.js'
    with open(filepath, 'r') as f:
        code = f.read()

    # Find the problematic block and escape backticks and $ properly
    # In python script, we injected:
    # return `
    #   <div class="card" ... >
    #     ... ${p.id} ...
    #   </div>
    # `;
    
    # Let's just fix it specifically:
    old_code = """return `
        <div class="card" style="padding:16px; border-left: 4px solid ${statusColor};">
          <div style="display:flex; justify-content:space-between; margin-bottom:12px;">
            <div style="font-weight:700; color:#cbd5e1;">📅 ${p.scheduledDate} <span style="margin-left:12px; font-size:12px; font-weight:600; padding:2px 8px; border-radius:6px; background:${statusColor}22; color:${statusColor}">${statusText}</span></div>
            <div style="display:flex; gap:8px;">
              ${p.status !== 'published' ? `<button class="btn-action" style="padding:4px 10px;font-size:12px;" onclick="approvePost('${p.id}')">Одобрить</button>` : ''}
              ${p.status !== 'published' ? `<button class="btn-action" style="padding:4px 10px;font-size:12px;border-color:#38bdf8;" onclick="publishPostNow('${p.id}')">Запостить сейчас</button>` : ''}
              <button class="btn-action" style="padding:4px 10px;font-size:12px;border-color:#fb7185;color:#fb7185;" onclick="deletePost('${p.id}')">Удалить</button>
            </div>
          </div>
          <textarea id="text-${p.id}" style="width:100%;background:#0b0f19;border:1px solid var(--card-border);color:#fff;padding:12px;border-radius:8px;font-size:14px;resize:vertical;min-height:80px;margin-bottom:10px;">${p.text || ''}</textarea>
          <input type="text" id="img-${p.id}" value="${p.imageUrl || ''}" placeholder="URL картинки (опционально)" style="width:100%;background:#0b0f19;border:1px solid var(--card-border);color:#fff;padding:10px;border-radius:8px;font-size:13px;margin-bottom:10px;">
          <button class="btn-action" style="padding:6px 12px;font-size:12px;" onclick="savePost('${p.id}')">💾 Сохранить изменения</button>
          ${p.error ? `<div style="color:#fb7185; font-size:12px; margin-top:8px;">Ошибка: ${p.error}</div>` : ''}
        </div>
      `;"""
      
    new_code = """return \\`
        <div class="card" style="padding:16px; border-left: 4px solid \\${statusColor};">
          <div style="display:flex; justify-content:space-between; margin-bottom:12px;">
            <div style="font-weight:700; color:#cbd5e1;">📅 \\${p.scheduledDate} <span style="margin-left:12px; font-size:12px; font-weight:600; padding:2px 8px; border-radius:6px; background:\\${statusColor}22; color:\\${statusColor}">\\${statusText}</span></div>
            <div style="display:flex; gap:8px;">
              \\${p.status !== 'published' ? \\`<button class="btn-action" style="padding:4px 10px;font-size:12px;" onclick="approvePost('\\${p.id}')">Одобрить</button>\\` : ''}
              \\${p.status !== 'published' ? \\`<button class="btn-action" style="padding:4px 10px;font-size:12px;border-color:#38bdf8;" onclick="publishPostNow('\\${p.id}')">Запостить сейчас</button>\\` : ''}
              <button class="btn-action" style="padding:4px 10px;font-size:12px;border-color:#fb7185;color:#fb7185;" onclick="deletePost('\\${p.id}')">Удалить</button>
            </div>
          </div>
          <textarea id="text-\\${p.id}" style="width:100%;background:#0b0f19;border:1px solid var(--card-border);color:#fff;padding:12px;border-radius:8px;font-size:14px;resize:vertical;min-height:80px;margin-bottom:10px;">\\${p.text || ''}</textarea>
          <input type="text" id="img-\\${p.id}" value="\\${p.imageUrl || ''}" placeholder="URL картинки (опционально)" style="width:100%;background:#0b0f19;border:1px solid var(--card-border);color:#fff;padding:10px;border-radius:8px;font-size:13px;margin-bottom:10px;">
          <button class="btn-action" style="padding:6px 12px;font-size:12px;" onclick="savePost('\\${p.id}')">💾 Сохранить изменения</button>
          \\${p.error ? \\`<div style="color:#fb7185; font-size:12px; margin-top:8px;">Ошибка: \\${p.error}</div>\\` : ''}
        </div>
      \\`;"""

    code = code.replace(old_code, new_code)
    
    with open(filepath, 'w') as f:
        f.write(code)

if __name__ == '__main__':
    main()
