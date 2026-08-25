def main():
    filepath = 'worker.js'
    with open(filepath, 'r') as f:
        code = f.read()

    code = code.replace("\\/api\\/admin\\/threads\\/\\${id}", "/api/admin/threads/\\${id}")
    code = code.replace("\\/api\\/admin\\/threads\\/\\${id}\\/publish", "/api/admin/threads/\\${id}/publish")

    with open(filepath, 'w') as f:
        f.write(code)

if __name__ == '__main__':
    main()
