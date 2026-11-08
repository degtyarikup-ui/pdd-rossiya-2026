#!/usr/bin/env python3
"""Submit prompt and click Create in Google Flow."""

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
    test_prompt = "POV driver view approaching modern city multi-lane roundabout intersection, Russian traffic signs 4.3 and 2.4, clean asphalt with lane markings, sunny daylight, photorealistic automotive photography, 16:9"
    
    js = f"""(function() {{{{
        var promptText = {json.dumps(test_prompt)};
        var inputEl = document.querySelector('[contenteditable="true"]');
        if (inputEl) {{{{
            inputEl.focus();
            inputEl.innerText = promptText;
            inputEl.dispatchEvent(new InputEvent('input', {{ bubbles: true, data: promptText }}));
            
            // Click the submit button (the arrow_forward or Create button at the prompt bar)
            var btns = Array.from(document.querySelectorAll('button'));
            var submitBtn = btns.find(b => b.innerText && b.innerText.includes('arrow_forward'));
            if (!submitBtn) {{{{
                submitBtn = btns.find(b => b.innerText && b.innerText.includes('Create'));
            }}}}
            if (submitBtn) {{{{
                submitBtn.click();
                return 'SUBMITTED';
            }}}}
            return 'BTN_NOT_FOUND';
        }}}}
        return 'INPUT_NOT_FOUND';
    }}}})()"""
    print(run_chrome_js(js))
