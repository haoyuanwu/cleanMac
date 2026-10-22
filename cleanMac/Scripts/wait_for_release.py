#!/usr/bin/env python3
"""等待已推送版本发布，自动确认中文编号说明和两个上传附件。"""
import json
import pathlib
import subprocess
import sys
import time
import urllib.parse


def request(path):
    result = subprocess.run(
        ['curl', '--silent', '--show-error', '--location', '--max-time', '20',
         '--header', 'Accept: application/vnd.github+json',
         '--write-out', '\n%{http_code}', f'https://api.github.com/{path}'],
        capture_output=True, text=True,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or 'GitHub 请求失败')
    payload, status = result.stdout.rsplit('\n', 1)
    if status == '404':
        return None
    if status != '200':
        raise RuntimeError(f'GitHub HTTP {status}: {payload[:160]}')
    return json.loads(payload)


def main():
    repo, tag, commit, notes_path = sys.argv[1:]
    expected_notes = pathlib.Path(notes_path).read_text().strip()
    end = time.monotonic() + 1800
    last_progress = None
    while time.monotonic() < end:
        try:
            release = request(f'repos/{repo}/releases/tags/{urllib.parse.quote(tag)}')
            if release and not release['draft']:
                assets = {asset['name']: asset for asset in release['assets']}
                names = ['cleanMac-arm64.dmg', 'cleanMac-x86_64.dmg']
                complete = all(name in assets and assets[name]['state'] == 'uploaded'
                               and assets[name]['size'] > 0 for name in names)
                if complete:
                    if release.get('body', '').strip() != expected_notes:
                        raise SystemExit('错误：线上更新说明与版本说明文件不一致')
                    ref = request(f'repos/{repo}/commits/{urllib.parse.quote(tag)}')
                    if not ref or ref['sha'] != commit:
                        raise SystemExit('错误：线上标签未指向本次发布提交')
                    print(f'发布完成：{release["html_url"]}', flush=True)
                    for name in names:
                        print(f'{name}：{assets[name]["browser_download_url"]}', flush=True)
                        print(f'  大小 {assets[name]["size"]} 字节，校验值 {assets[name].get("digest", "未提供")}', flush=True)
                    return
            runs = request(f'repos/{repo}/actions/runs?head_sha={commit}&event=push&per_page=10')
            matching = [run for run in (runs or {}).get('workflow_runs', [])
                        if run['head_sha'] == commit and run['path'] == '.github/workflows/release.yml']
            if matching:
                run = max(matching, key=lambda r: r['id'])
                progress = (run['status'], run.get('conclusion'))
                if progress != last_progress:
                    print(f'GitHub 发布任务：{progress[0]} / {progress[1] or "执行中"} {run["html_url"]}', flush=True)
                    last_progress = progress
                if run['status'] == 'completed' and run.get('conclusion') != 'success':
                    raise SystemExit(f'错误：GitHub 发布失败，请查看 {run["html_url"]}')
                if run['status'] == 'completed' and run.get('conclusion') == 'success':
                    raise SystemExit('错误：工作流已完成，但发布附件不完整')
        except RuntimeError as error:
            print(f'请求暂未成功，将重试：{error}', flush=True)
        time.sleep(30)
    raise SystemExit('等待超时。可用 publish_release.sh <版本号> --wait-only 继续，无需重新构建或提交。')


if __name__ == '__main__':
    main()
