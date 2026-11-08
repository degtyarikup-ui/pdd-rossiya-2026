#!/usr/bin/env python3
import subprocess
import json

script = '''tell application "Google Chrome"
    set t to active tab of front window
    execute t javascript "JSON.stringify({
        url: location.href,
        hasGeneratingSpinner: !!document.querySelector('[role=\\"progressbar\\"], .spinner, svg.animate-spin'),
        canvasElementsCount: document.querySelectorAll('*').length,
        visibleText: document.body.innerText.slice(0, 500)
    })"
end tell'''
res = subprocess.check_output(['osascript', '-e', script]).decode('utf-8')
print(res)
