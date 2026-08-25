#!/usr/bin/env python3
import subprocess
import json
import time

prompt = "POV driver view approaching modern city multi-lane roundabout intersection, Russian traffic signs 4.3 and 2.4, clean asphalt with lane markings, sunny daylight, photorealistic automotive photography, 16:9"

js_code = f"""(function() {{
    var el = document.querySelector('[contenteditable]');
    if (!el) return 'NO_EL';
    
    el.focus();
    // Simulate real text entry
    document.execCommand('selectAll', false, null);
    document.execCommand('insertText', false, {json.dumps(prompt)});
    
    // Trigger React / synthetic input events
    el.dispatchEvent(new Event('input', {{ bubbles: true }}));
    el.dispatchEvent(new Event('change', {{ bubbles: true }}));
    
    // Find the submit button icon (arrow_forward)
    var allButtons = Array.from(document.querySelectorAll('button'));
    var submit = allButtons.find(b => b.querySelector('svg, span, i') && (b.innerText.includes('arrow_forward') || b.innerHTML.includes('arrow_forward')));
    if (!submit) {{
        submit = allButtons.find(b => b.getAttribute('aria-label') === 'Generate' || b.getAttribute('aria-label') === 'Create' || b.innerText.includes('Create'));
    }}
    
    if (submit) {{
        // Dispatch pointerdown, pointerup, click
        submit.dispatchEvent(new PointerEvent('pointerdown', {{ bubbles: true }}));
        submit.dispatchEvent(new MouseEvent('mousedown', {{ bubbles: true }}));
        submit.dispatchEvent(new PointerEvent('pointerup', {{ bubbles: true }}));
        submit.dispatchEvent(new MouseEvent('mouseup', {{ bubbles: true }}));
        submit.click();
        return 'TRIGGERED_SUBMIT';
    }}
    
    return 'SUBMIT_BTN_NOT_FOUND';
}})()"""

script = f'''tell application "Google Chrome"
    set t to active tab of front window
    execute t javascript {json.dumps(js_code)}
end tell'''

res = subprocess.check_output(['osascript', '-e', script]).decode('utf-8')
print("DOM Submit result:", res.strip())
