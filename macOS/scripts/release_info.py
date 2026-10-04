#!/usr/bin/env python3
"""Bind an installer to the runtime sources and the app which was packaged."""
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def source_sha256(root):
    digest = hashlib.sha256()
    for directory in ['Sources', 'Resources', 'scripts']:
        folder = Path(root) / directory
        if not folder.is_dir():
            raise ValueError(f'Missing source directory: {directory}')
        for path in sorted(folder.rglob('*')):
            if path.name == '.DS_Store' or '__pycache__' in path.parts:
                continue
            if path.is_symlink():
                raise ValueError(f'Symlink in runtime sources: {path}')
            if path.is_file():
                digest.update(path.relative_to(root).as_posix().encode() + b'\0')
                digest.update(bytes.fromhex(sha256(path)))
    return digest.hexdigest()


def application_sha256(app):
    app = Path(app)
    digest = hashlib.sha256()
    for path in sorted(app.rglob('*')):
        if path.name == '.DS_Store':
            continue
        if path.is_symlink():
            raise ValueError('Unexpected symlink in application bundle.')
        if path.is_file():
            digest.update(path.relative_to(app).as_posix().encode() + b'\0')
            digest.update(bytes.fromhex(sha256(path)))
    return digest.hexdigest()


def validate(root, installer_filename, version, build):
    root = Path(root)
    folder = root / 'App'
    info = json.loads((folder / 'installer-info.json').read_text())
    expected = {'schema': 1, 'version': version, 'build': build,
                'installer': installer_filename, 'architectures': ['arm64', 'x86_64']}
    if any(info.get(key) != value for key, value in expected.items()):
        raise ValueError('Данные установщика не соответствуют версии, сборке или архитектурам. Пересоберите экспорт.')
    if info.get('sourceSHA256') != source_sha256(root):
        raise ValueError('Исходники изменились после сборки установщика. Пересоберите экспорт.')
    if info.get('installerSHA256') != sha256(folder / installer_filename):
        raise ValueError('Установщик изменился после проверки. Пересоберите экспорт.')
    app = folder / 'CursorWasher.app'
    with (app / 'Contents/Info.plist').open('rb') as stream:
        plist = plistlib.load(stream)
    if plist.get('CFBundleShortVersionString') != version or plist.get('CFBundleVersion') != build:
        raise ValueError('Версия приложения не соответствует установщику.')
    if info.get('executableSHA256') != sha256(app / 'Contents/MacOS/CursorWasher'):
        raise ValueError('Приложение изменилось после упаковки. Пересоберите экспорт.')
    if info.get('applicationSHA256') != application_sha256(app):
        raise ValueError('Содержимое приложения изменилось после упаковки. Пересоберите экспорт.')
    return info


def create(root, installer, version, build, installer_filename=None):
    root, installer = Path(root), Path(installer)
    app = root / 'Build/CursorWasher.app'
    executable = app / 'Contents/MacOS/CursorWasher'
    with (app / 'Contents/Info.plist').open('rb') as stream:
        plist = plistlib.load(stream)
    if plist['CFBundleShortVersionString'] != version or plist['CFBundleVersion'] != build:
        raise ValueError('Application version changed while packaging.')
    architectures = sorted(subprocess.check_output(['xcrun', 'lipo', '-archs', str(executable)], text=True).split())
    if architectures != ['arm64', 'x86_64']:
        raise ValueError('The installer requires both supported architectures.')
    info = {'schema': 1, 'version': version, 'build': build, 'installer': installer_filename or installer.name,
            'architectures': architectures, 'sourceSHA256': source_sha256(root),
            'installerSHA256': sha256(installer), 'executableSHA256': sha256(executable),
            'applicationSHA256': application_sha256(app),
            'toolchain': subprocess.check_output(['xcrun', 'swiftc', '--version'], text=True).strip()}
    (installer.parent / 'installer-info.json').write_text(json.dumps(info, indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    try:
        create(*sys.argv[1:])
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
