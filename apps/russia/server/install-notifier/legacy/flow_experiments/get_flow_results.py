#!/usr/bin/env python3
"""Inspect active Chrome tab for generation status and download links."""

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
    js = """(function() {
        var imgs = Array.from(document.querySelectorAll('img')).map(function(img) {
            return {
                src: img.src,
                w: img.naturalWidth || img.width,
                h: img.naturalHeight || img.height,
                alt: img.alt
            };
        }).filter(function(i) { return i.w > 300 || i.src.includes('googleusercontent.com') || i.src.startsWith('blob:'); });
        
        return JSON.stringify({
            count: imgs.length,
            items: imgs.slice(0, 15)
        });
    })()"""
    print(run_chrome_js(js))
