#!/usr/bin/env python3
import subprocess
import json
import time

prompt = "POV driver view approaching modern city multi-lane roundabout intersection, Russian traffic signs 4.3 and 2.4, clean asphalt with lane markings, sunny daylight, photorealistic automotive photography, 16:9"

js_code = """(function() {
    var el = document.querySelector('[contenteditable]');
    if (el) {
        el.focus();
        return 'FOCUSED';
    }
    return 'NOT_FOUND';
})()"""

script = f'''tell application "Google Chrome"
    set t to active tab of front window
    execute t javascript {json.dumps(js_code)}
end tell'''

res = subprocess.check_output(['osascript', '-e', script]).decode('utf-8')
print("Focus result:", res.strip())

pb_proc = subprocess.Popen(['pbcopy'], stdin=subprocess.PIPE)
pb_proc.communicate(prompt.encode('utf-8'))

time.sleep(0.5)

paste_script = '''tell application "System Events"
    tell process "Google Chrome"
        set frontmost to true
        keystroke "v" using command down
        delay 0.8
        key code 36
    end tell
end tell'''
subprocess.call(['osascript', '-e', paste_script])
print("Pasted and hit enter.")
