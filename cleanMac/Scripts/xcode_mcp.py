#!/usr/bin/env python3
"""通过 Xcode 自带 mcpbridge 调用工具，不安装第三方依赖或修改全局配置。"""
import argparse
import json
import os
import select
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tool', help='Xcode 工具名；tools 列出工具名称')
    parser.add_argument('arguments', nargs='?', default='{}', help='JSON 参数')
    parser.add_argument('--timeout', type=float, default=180)
    args = parser.parse_args()
    arguments = json.loads(args.arguments)
    bridge = subprocess.Popen(['xcrun', 'mcpbridge'], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    pending = b''

    def send(message):
        bridge.stdin.write((json.dumps(message) + '\n').encode())
        bridge.stdin.flush()

    def request(identifier, method, params):
        nonlocal pending
        send(dict(jsonrpc='2.0', id=identifier, method=method, params=params))
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            while b'\n' in pending:
                line, pending = pending.split(b'\n', 1)
                if not line.strip():
                    continue
                reply = json.loads(line)
                if reply.get('id') == identifier:
                    if 'error' in reply:
                        raise RuntimeError(json.dumps(reply['error'], ensure_ascii=False))
                    return reply['result']
            if select.select([bridge.stdout], [], [], min(1, max(0, deadline-time.monotonic())))[0]:
                chunk = os.read(bridge.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError('Xcode MCP 连接已关闭')
                pending += chunk
        raise TimeoutError('等待 Xcode 工具响应超时')

    try:
        request(1, 'initialize', dict(protocolVersion='2024-11-05', capabilities={},
                                     clientInfo=dict(name='cleanMac-development', version='1.0')))
        send(dict(jsonrpc='2.0', method='notifications/initialized'))
        if args.tool == 'tools':
            result = request(2, 'tools/list', {})
            print('\n'.join(t['name'] for t in result['tools']))
        else:
            result = request(2, 'tools/call', dict(name=args.tool, arguments=arguments))
            print(json.dumps(result, ensure_ascii=False, indent=2))
            if result.get('isError'):
                raise SystemExit(1)
    finally:
        bridge.terminate()
        try:
            bridge.wait(timeout=3)
        except subprocess.TimeoutExpired:
            bridge.kill()
            bridge.wait()


if __name__ == '__main__':
    main()
