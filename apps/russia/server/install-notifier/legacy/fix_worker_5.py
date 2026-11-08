def main():
    filepath = 'worker.js'
    with open(filepath, 'r') as f:
        code = f.read()

    # The issue is esbuild choking on some combination of escapes. Let's just use regular strings.
    code = code.replace("`/api/admin/threads/\\${id}`", "'/api/admin/threads/' + id")
    code = code.replace("`/api/admin/threads/\\${id}/publish`", "'/api/admin/threads/' + id + '/publish'")
    code = code.replace("`text-\\${id}`", "'text-' + id")
    code = code.replace("`img-\\${id}`", "'img-' + id")

    # Wait, earlier I also injected \`<button ... >\` in the map.
    # \\${p.status !== 'published' ? \\`<button class="btn-action" style="padding:4px 10px;font-size:12px;" onclick="approvePost('\\${p.id}')">Одобрить</button>\\` : ''}
    # It's inside a template string itself. Let's replace the inner backticks with single quotes, and use regular quotes for HTML attributes.
    # Actually, if I just replace \\`<button ... >\\` with '<button ... >' it should work.
    
    code = code.replace("\\`<button class=\"btn-action\" style=\"padding:4px 10px;font-size:12px;\" onclick=\"approvePost('\\${p.id}')\">Одобрить</button>\\`", 
                        "'<button class=\"btn-action\" style=\"padding:4px 10px;font-size:12px;\" onclick=\"approvePost(\\'' + p.id + '\\')\">Одобрить</button>'")
    
    code = code.replace("\\`<button class=\"btn-action\" style=\"padding:4px 10px;font-size:12px;border-color:#38bdf8;\" onclick=\"publishPostNow('\\${p.id}')\">Запостить сейчас</button>\\`",
                        "'<button class=\"btn-action\" style=\"padding:4px 10px;font-size:12px;border-color:#38bdf8;\" onclick=\"publishPostNow(\\'' + p.id + '\\')\">Запостить сейчас</button>'")
                        
    code = code.replace("\\`<div style=\"color:#fb7185; font-size:12px; margin-top:8px;\">Ошибка: \\${p.error}</div>\\`",
                        "'<div style=\"color:#fb7185; font-size:12px; margin-top:8px;\">Ошибка: ' + p.error + '</div>'")

    with open(filepath, 'w') as f:
        f.write(code)

if __name__ == '__main__':
    main()
