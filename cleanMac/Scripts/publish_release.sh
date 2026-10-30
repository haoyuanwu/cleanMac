#!/bin/bash
# 一键发布：准备版本 → 双架构打包校验 → 中文提交 → 推送 → 等待 GitHub 发布。
# 用法：./Scripts/publish_release.sh 1.0.8
# 仅继续等待已推送的版本：./Scripts/publish_release.sh 1.0.8 --wait-only
set -euo pipefail

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(git -C "$APP_ROOT" rev-parse --show-toplevel)"
cd "$REPO_ROOT"
if [[ "${1:-}" = --help || "${1:-}" = -h ]]; then
  echo '用法：./Scripts/publish_release.sh <版本号> [--resume|--wait-only]'
  echo '先编写 docs/releases/v<版本号>.md，按 1、2、3 编号。'
  echo '可用 RELEASE_COMMIT_MESSAGE 覆盖默认中文提交信息。'
  exit 0
fi
VERSION="${1:?请传入版本号，例如 1.0.8}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo '错误：版本号必须为 x.y.z' >&2; exit 1; }
MODE="${2:-}"
[[ -z "$MODE" || "$MODE" = --wait-only || "$MODE" = --resume ]] || { echo '错误：未知选项' >&2; exit 1; }
TAG="v$VERSION"
NOTES="$REPO_ROOT/docs/releases/$TAG.md"
PROJECT="$APP_ROOT/cleanMac.xcodeproj/project.pbxproj"
COMMIT_MESSAGE="${RELEASE_COMMIT_MESSAGE:-发布 ${TAG}：更新功能与体验优化}"

REMOTE_URL="$(git remote get-url origin)"
REPOSITORY="$(python3 - "$REMOTE_URL" <<'PY'
import re,sys
match = re.fullmatch(r'(?:https://(?:[^/@]+@)?github\.com/|git@github\.com:)([^/]+/[^/]+?)(?:\.git)?/?',sys.argv[1])
if not match: raise SystemExit('错误：origin 必须是 GitHub 仓库')
print(match.group(1))
PY
)"
PUSH_URL="git@github.com:$REPOSITORY.git"

if [[ -z "$MODE" ]]; then
  [[ "$(git branch --show-current)" = main ]] || { echo '错误：请从 main 分支发布' >&2; exit 1; }
  git diff --cached --quiet || { echo '错误：暂存区存在其他改动，请先处理后再发布' >&2; exit 1; }
  python3 - "$NOTES" "$COMMIT_MESSAGE" <<'PY'
import pathlib,re,sys
notes=pathlib.Path(sys.argv[1])
if not notes.is_file(): raise SystemExit(f'错误：请先编写 {notes}')
content=notes.read_text()
numbers=[int(n) for n in re.findall(r'^(\d+)\.\s+\S',content,re.M)]
if not numbers or numbers != list(range(1,len(numbers)+1)):
    raise SystemExit('错误：更新说明必须使用从 1 开始的连续编号')
if not re.search(r'[\u4e00-\u9fff]',sys.argv[2]): raise SystemExit('错误：提交信息必须包含中文')
PY
  if git rev-parse --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "错误：本地标签 $TAG 已存在，继续等待请使用 --wait-only" >&2
    exit 1
  fi
  REMOTE_REFS="$(git ls-remote "$PUSH_URL" refs/heads/main "refs/tags/$TAG")"
  if [[ "$REMOTE_REFS" = *"refs/tags/$TAG"* ]]; then
    echo "错误：远程标签 $TAG 已存在，继续等待请使用 --wait-only" >&2
    exit 1
  fi
  REMOTE_MAIN="$(echo "$REMOTE_REFS" | awk '$2 == "refs/heads/main" {print $1}')"
  [[ -n "$REMOTE_MAIN" ]] || { echo '错误：无法确定远程 main' >&2; exit 1; }
  git cat-file -e "$REMOTE_MAIN^{commit}" 2>/dev/null || git fetch "$PUSH_URL" main
  git merge-base --is-ancestor "$REMOTE_MAIN" HEAD || { echo '错误：请先同步远程 main 的变更' >&2; exit 1; }
  echo "==> 准备 $TAG"
  python3 - "$PROJECT" "$VERSION" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); content=p.read_text(); version=sys.argv[2]
versions=re.findall(r'MARKETING_VERSION = ([^;]+);',content)
builds=re.findall(r'CURRENT_PROJECT_VERSION = (\d+);',content)
if not versions or len(set(versions))!=1 or not builds or len(set(builds))!=1:
    raise SystemExit('错误：项目中的版本号或构建号不一致')
if tuple(map(int,version.split('.'))) <= tuple(map(int,versions[0].split('.'))):
    raise SystemExit('错误：新版本必须高于当前版本')
build=int(builds[0])+1
content=re.sub(r'MARKETING_VERSION = [^;]+;',f'MARKETING_VERSION = {version};',content)
content=re.sub(r'CURRENT_PROJECT_VERSION = \d+;',f'CURRENT_PROJECT_VERSION = {build};',content)
p.write_text(content)
print(f'版本 {version}，构建号 {build}')
PY
  bash -n "$APP_ROOT/Scripts/make_dmg.sh" "$APP_ROOT/Scripts/publish_release.sh"
  git diff --check
  echo '==> 运行核心模型和文件系统回归测试'
  "$APP_ROOT/Scripts/test_p0.sh"
  echo '==> 构建并自动校验 Apple Silicon 和 Intel 安装包'
  BUILD_ARCH=all "$APP_ROOT/Scripts/make_dmg.sh"
  # 只暂存应用源码、设计资源、发布脚本、版本和说明；不包含 Xcode 用户状态及 build 产物。
  git add -- "$APP_ROOT/cleanMac" "$APP_ROOT/cleanMacTests" "$APP_ROOT/Design" "$PROJECT" "$APP_ROOT/Scripts" "$REPO_ROOT/README.md" "$REPO_ROOT/.github"
  git add -f -- "$NOTES"
  git diff --cached --check
  echo '==> 创建中文提交和版本标签'
  git commit -m "$COMMIT_MESSAGE"
fi
if [[ "$MODE" != --wait-only ]]; then
  if [[ "$MODE" = --resume ]]; then
    [[ "$(git branch --show-current)" = main ]] || { echo '错误：请从 main 分支继续发布' >&2; exit 1; }
    git diff --cached --quiet || { echo '错误：请先处理暂存区改动' >&2; exit 1; }
    git diff --quiet -- "$APP_ROOT/cleanMac" "$APP_ROOT/cleanMacTests" "$APP_ROOT/Design" "$PROJECT" "$APP_ROOT/Scripts" "$REPO_ROOT/README.md" "$REPO_ROOT/.github" "$NOTES" || {
      echo '错误：源码或发布文件发生变化，请先提交后再继续推送' >&2; exit 1;
    }
    git cat-file -e "HEAD:docs/releases/$TAG.md"
    python3 - "$PROJECT" "$VERSION" <<'PYVERSION'
from pathlib import Path
import re,sys
versions=re.findall(r'MARKETING_VERSION = ([^;]+);',Path(sys.argv[1]).read_text())
if not versions or set(versions) != {sys.argv[2]}: raise SystemExit('错误：当前项目版本不匹配')
PYVERSION
  fi
  if git rev-parse --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    [[ "$(git rev-list -n 1 "$TAG")" = "$(git rev-parse HEAD)" ]] || {
      echo '错误：现有标签指向其他提交，拒绝覆盖' >&2; exit 1;
    }
  else
    git tag -a "$TAG" -m "cleanMac ${VERSION}：详见 docs/releases/$TAG.md"
  fi
  echo '==> 原子推送代码与标签，触发 GitHub 双架构发布'
  git push --atomic "$PUSH_URL" HEAD:refs/heads/main "refs/tags/$TAG:refs/tags/$TAG"
fi
COMMIT="$(git rev-list -n 1 "$TAG")"
python3 "$APP_ROOT/Scripts/wait_for_release.py" "$REPOSITORY" "$TAG" "$COMMIT" "$NOTES"
