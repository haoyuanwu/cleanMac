#!/bin/bash
# 由 publish_release.sh <版本> --replace-assets 调用，更新既有 Release。
# 使用独立构建标签追溯重打包源码，保留原始版本标签。
set -euo pipefail
APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(git -C "$APP_ROOT" rev-parse --show-toplevel)"
cd "$REPO_ROOT"
VERSION="${1:?请传入版本号}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
TAG="v$VERSION"
NOTES="$REPO_ROOT/docs/releases/$TAG.md"
PROJECT="$APP_ROOT/cleanMac.xcodeproj/project.pbxproj"
[[ "$(git branch --show-current)" = main ]] || { echo '错误：请从 main 更新安装包'; exit 1; }
git diff --cached --quiet || { echo '错误：暂存区存在其他改动'; exit 1; }
REPOSITORY="$(python3 - "$(git remote get-url origin)" <<'PYREPO'
import re,sys
match=re.fullmatch(r'(?:https://(?:[^/@]+@)?github\.com/|git@github\.com:)([^/]+/[^/]+?)(?:\.git)?/?',sys.argv[1])
if not match: raise SystemExit('错误：origin 必须是 GitHub 仓库')
print(match.group(1))
PYREPO
)"
BUILD="$(python3 - "$PROJECT" "$VERSION" "$NOTES" <<'PYVERSION'
from pathlib import Path
import re,sys
text=Path(sys.argv[1]).read_text()
versions=set(re.findall(r'MARKETING_VERSION = ([^;]+);',text))
builds=set(re.findall(r'CURRENT_PROJECT_VERSION = (\d+);',text))
if versions!={sys.argv[2]} or len(builds)!=1: raise SystemExit('错误：版本或构建号不一致')
notes=Path(sys.argv[3]).read_text()
numbers=[int(n) for n in re.findall(r'^(\d+)\.\s+\S',notes,re.M)]
if not numbers or numbers!=list(range(1,len(numbers)+1)): raise SystemExit('错误：说明需连续编号')
build=next(iter(builds))
if f'build/v{sys.argv[2]}-{build}' not in notes: raise SystemExit('错误：说明缺少对应构建标签')
print(build)
PYVERSION
)"
BUILD_TAG="build/$TAG-$BUILD"
PUSH_URL="git@github.com:$REPOSITORY.git"
REMOTE_MAIN="$(git ls-remote "$PUSH_URL" refs/heads/main | awk '{print $1}')"
[[ -n "$REMOTE_MAIN" ]] || exit 1
git cat-file -e "$REMOTE_MAIN^{commit}" 2>/dev/null || git fetch "$PUSH_URL" main
git merge-base --is-ancestor "$REMOTE_MAIN" HEAD || { echo '错误：需先同步远程 main'; exit 1; }
[[ -z "$(git ls-remote "$PUSH_URL" "refs/tags/$BUILD_TAG")" ]] || { echo '错误：构建标签已存在'; exit 1; }
! git rev-parse --verify "refs/tags/$BUILD_TAG" >/dev/null 2>&1 || { echo '错误：本地构建标签已存在'; exit 1; }
gh api "repos/$REPOSITORY/releases/tags/$TAG" > /tmp/cleanmac-replacement-release.json
python3 - /tmp/cleanmac-replacement-release.json "$TAG" <<'PYRELEASE'
import json,sys
r=json.load(open(sys.argv[1]))
if r['draft'] or r['tag_name']!=sys.argv[2]: raise SystemExit('错误：必须是已发布的对应版本')
PYRELEASE
git diff --check
bash -n "$APP_ROOT/Scripts/replace_release_assets.sh" "$APP_ROOT/Scripts/make_dmg.sh"
echo '==> 运行回归测试并构建、校验双架构安装包'
"$APP_ROOT/Scripts/test_p0.sh"
BUILD_ARCH=all "$APP_ROOT/Scripts/make_dmg.sh"
git add -- "$APP_ROOT/cleanMac" "$APP_ROOT/Design" "$APP_ROOT/Scripts" "$APP_ROOT/cleanMacTests" "$PROJECT" "$REPO_ROOT/README.md"
git add -f -- "$NOTES"
git diff --cached --check
git commit -m "更新 $TAG 安装包：延迟启动扫描并减少窗口焦点干扰（构建 ${BUILD}）"
git tag -a "$BUILD_TAG" -m "cleanMac $VERSION 构建 $BUILD：既有版本安装包更新"
git push --atomic "$PUSH_URL" HEAD:refs/heads/main "refs/tags/$BUILD_TAG:refs/tags/$BUILD_TAG"
echo '==> 替换当前 Release 的两个安装包并同步说明'
gh release upload "$TAG" "$APP_ROOT/build/cleanMac-arm64.dmg" "$APP_ROOT/build/cleanMac-x86_64.dmg" --clobber --repo "$REPOSITORY"
gh release edit "$TAG" --notes-file "$NOTES" --repo "$REPOSITORY"
gh api "repos/$REPOSITORY/releases/tags/$TAG" > /tmp/cleanmac-replacement-release-verified.json
python3 - /tmp/cleanmac-replacement-release-verified.json "$NOTES" "$APP_ROOT/build" <<'PYVERIFY'
import json,sys,hashlib
from pathlib import Path
r=json.load(open(sys.argv[1]))
if r['body'].strip()!=Path(sys.argv[2]).read_text().strip(): raise SystemExit('错误：线上说明不一致')
assets={a['name']:a for a in r['assets']}
for name in ['cleanMac-arm64.dmg','cleanMac-x86_64.dmg']:
 a=assets[name]; p=Path(sys.argv[3])/name
 if a['state']!='uploaded' or a['size']!=p.stat().st_size: raise SystemExit('错误：附件未上传完成')
 digest='sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
 if a.get('digest')!=digest: raise SystemExit('错误：附件校验值不一致')
 print(name, a['browser_download_url'], digest, flush=True)
print('更新完成：'+r['html_url'],flush=True)
PYVERIFY
