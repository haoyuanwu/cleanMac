#!/usr/bin/env python3
"""上传已经本地校验的安装包，核对摘要后公开 Release。"""
import hashlib
import json
import pathlib
import subprocess
import sys


def gh(*args):
    return subprocess.run(['gh', *args], check=True, text=True, capture_output=True).stdout


def release(repo, tag):
    result = subprocess.run(['gh', 'api', f'repos/{repo}/releases/tags/{tag}'], text=True, capture_output=True)
    if result.returncode:
        if 'HTTP 404' in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout)


def verify(info, tag, notes, package):
    if not info:
        raise RuntimeError('无法读取 Release。')
    if info['tag_name'] != tag or info.get('body', '').strip() != notes.read_text().strip():
        raise RuntimeError('Release 标签或说明与本地文件不一致，拒绝修改。')
    asset = next((a for a in info['assets'] if a['name'] == package.name), None)
    digest = 'sha256:' + hashlib.sha256(package.read_bytes()).hexdigest()
    if not asset or asset['state'] != 'uploaded' or asset['size'] != package.stat().st_size or asset.get('digest') != digest:
        raise RuntimeError('Release 安装包未完整上传或 SHA-256 与本机文件不一致。')
    return asset


def upload(repo, tag, notes, package):
    if package.name != 'cleanMac-arm64.dmg' or not package.is_file() or not package.stat().st_size:
        raise RuntimeError('缺少有效的 arm64 安装包。')
    info = release(repo, tag)
    if info is None:
        gh('release', 'create', tag, '--repo', repo, '--draft', '--verify-tag', '--title', 'cleanMac ' + tag.removeprefix('v'), '--notes-file', str(notes))
        info = release(repo, tag)
    if info is None:
        raise RuntimeError('无法读取新建的 Release 草稿。')
    if info['tag_name'] != tag or info.get('body', '').strip() != notes.read_text().strip():
        raise RuntimeError('已有 Release 说明或标签不一致，拒绝覆盖。')
    if info['draft']:
        gh('release', 'upload', tag, str(package), '--clobber', '--repo', repo)
        verify(release(repo, tag), tag, notes, package)
        gh('release', 'edit', tag, '--draft=false', '--repo', repo)
    # 已公开版本仅核对，不替换现有附件。
    info = release(repo, tag)
    asset = verify(info, tag, notes, package)
    if info['draft']:
        raise RuntimeError('Release 仍为草稿。')
    print('发布完成：' + info['html_url'], flush=True)
    print(asset['browser_download_url'], flush=True)
    print(asset['digest'], flush=True)


if __name__ == '__main__':
    try:
        repo, tag, notes, package = sys.argv[1:]
        upload(repo, tag, pathlib.Path(notes), pathlib.Path(package))
    except (RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
