import re

def main():
    filepath = 'worker.js'
    with open(filepath, 'r') as f:
        code = f.read()

    # Find and fix the other unescaped JS template strings
    code = code.replace("window.approvePost = async (id) => {", "// FIXED WINDOWS FUNCS\\nwindow.approvePost = async (id) => {")
    code = code.replace("await fetch(`/api/admin/threads/${id}`", "await fetch(`\\/api\\/admin\\/threads\\/\\${id}`")
    code = code.replace("await fetch(`/api/admin/threads/${id}/publish`", "await fetch(`\\/api\\/admin\\/threads\\/\\${id}\\/publish`")
    
    code = code.replace("document.getElementById(`text-${id}`).value", "document.getElementById(`text-\\${id}`).value")
    code = code.replace("document.getElementById(`img-${id}`).value", "document.getElementById(`img-\\${id}`).value")

    with open(filepath, 'w') as f:
        f.write(code)

if __name__ == '__main__':
    main()
