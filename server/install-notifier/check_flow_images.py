#!/usr/bin/env python3
"""Check generated images in Google Flow canvas."""

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
    time.sleep(5)
    js = """(function() {
        var imgs = Array.from(document.querySelectorAll('img')).map(function(img) {
            return {
                src: img.src.slice(0, 100),
                width: img.naturalWidth || img.width,
                height: img.naturalHeight || img.height,
                alt: img.alt
            };
        }).filter(function(i) { return i.width > 200 || i.src.startsWith('blob:') || i.src.startsWith('data:'); });
        
        return JSON.stringify({
            count: imgs.length,
            images: imgs.slice(0, 10)
        });
    })()"""
    print(run_chrome_js(js))
