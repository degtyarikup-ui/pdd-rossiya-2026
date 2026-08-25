#!/usr/bin/env python3
"""Automate prompt submission and image download in Google Flow UI via Chrome."""

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
    # Test filling prompt into the contenteditable div or input and clicking Create
    test_prompt = "POV driver view approaching modern city multi-lane roundabout intersection, Russian traffic signs 4.3 and 2.4, clean asphalt with lane markings, sunny daylight, photorealistic automotive photography, 16:9"
    
    js = f"""(function() {{{{
        var promptText = {json.dumps(test_prompt)};
        
        // Find contenteditable or input for prompt
        var inputEl = document.querySelector('[contenteditable="true"]') || document.querySelector('textarea:not(.g-recaptcha-response)');
        if (!inputEl) {{{{
            var allInputs = Array.from(document.querySelectorAll('input, div[contenteditable]'));
            inputEl = allInputs.find(el => el.getAttribute('contenteditable') === 'true' || el.tagName === 'TEXTAREA');
        }}}}
        
        if (inputEl) {{{{
            inputEl.focus();
            if (inputEl.tagName === 'TEXTAREA' || inputEl.tagName === 'INPUT') {{{{
                inputEl.value = promptText;
                inputEl.dispatchEvent(new Event('input', {{ bubbles: true }}));
                inputEl.dispatchEvent(new Event('change', {{ bubbles: true }}));
            }}}} else {{{{
                inputEl.innerText = promptText;
                inputEl.dispatchEvent(new InputEvent('input', {{ bubbles: true, data: promptText }}));
            }}}}
            
            // Find and click Create / Submit button
            var btns = Array.from(document.querySelectorAll('button'));
            var submitBtn = btns.find(b => b.innerText && (b.innerText.includes('Create') || b.innerText.includes('arrow_forward')));
            
            return JSON.stringify({{
                foundInput: true,
                inputTag: inputEl.tagName,
                submitBtnFound: !!submitBtn,
                submitBtnText: submitBtn ? submitBtn.innerText : ''
            }});
        }}}}
        return JSON.stringify({{ foundInput: false }});
    }}}})()"""
    print(run_chrome_js(js))
