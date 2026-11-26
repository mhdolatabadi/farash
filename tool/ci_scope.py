"""Conservative PR routing; main and manual runs always exercise every gate."""
import os
import pathlib
import subprocess


def scope(paths, event):
    if event != 'pull_request' or not paths:
        return True, True
    app = visual = False
    for path in paths:
        # Only well-understood, unrelated paths may omit the client checks.
        if (path.startswith(('docs/', 'server/', '.skill/', '.impeccable/'))
                or path in ('README.md', 'AGENTS.md', 'PRODUCT.md', 'DESIGN.md',
                            'LICENSE', '.gitignore')):
            continue
        if path.startswith('deploy/') and path != 'deploy/Dockerfile.web':
            continue
        app = True
        # Widget-only tests still get the full suite and both real builds.
        if not path.startswith('test/'):
            visual = True
    return app, visual


def main():
    event = os.environ['EVENT_NAME']
    paths = []
    if event == 'pull_request':
        paths = subprocess.check_output([
            'git', 'diff', '--no-renames', '--name-only', '-z',
            f"{os.environ['BASE_SHA']}...{os.environ['HEAD_SHA']}",
        ]).decode().split('\0')
        paths = [path for path in paths if path]
    app, visual = scope(paths, event)
    result = f'app={str(app).lower()}\nvisual={str(visual).lower()}\n'
    with pathlib.Path(os.environ['GITHUB_OUTPUT']).open('a') as output:
        output.write(result)
    print(result, end='')


if __name__ == '__main__':
    main()
