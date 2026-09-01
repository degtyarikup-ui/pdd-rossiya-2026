#!/usr/bin/env python3
import subprocess
import json
import time

def run_chrome_js(js_code: str):
    script = f'''tell application "Google Chrome"
    set t to active tab of front window
    execute t javascript {json.dumps(js_code)}
end tell'''
    return subprocess.check_output(['osascript', '-e', script]).decode('utf-8')

if __name__ == '__main__':
    time.sleep(2)
    js = """(function() {
        var textareas = Array.from(document.querySelectorAll('textarea, input, [contenteditable]')).map(function(el) {
            return {
                tag: el.tagName,
                placeholder: el.getAttribute('placeholder') || '',
                id: el.id,
                className: el.className
            };
        });
        var buttons = Array.from(document.querySelectorAll('button')).map(function(b) {
            return b.innerText.trim();
        }).filter(Boolean);
        return JSON.stringify({url: location.href, inputs: textareas, buttons: buttons.slice(0, 35)});
    })()"""
    print(run_chrome_js(js))
