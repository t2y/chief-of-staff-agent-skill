#!/usr/bin/env bats
# csa の CLI を、偽の herdr と一時ディレクトリの HOME で確かめる

setup() {
  REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  CSA="$REPO_ROOT/skills/csa/scripts/csa"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CSA_HOME="$HOME/.csa"
  export CSA_BIN_DIR="$HOME/.local/bin"
  export FAKE_HERDR_DIR="$BATS_TEST_TMPDIR/herdr"
  export CSA_UPDATE_CHECK=0
  export PATH="$REPO_ROOT/test/fake-bin:$CSA_BIN_DIR:$PATH"
  mkdir -p "$HOME"
}

# csa を実行する。CSA_BASH で bash を指定できる(CI の macOS では /bin/bash 3.2 で csa を確かめる)
csa_run() { "${CSA_BASH:-bash}" "$CSA" "$@"; }

# 課題を 1 件 spawn した状態を作る
spawn_issue() {
  csa_run init >/dev/null 2>&1
  local repo="$BATS_TEST_TMPDIR/repo"
  git init -q "$repo"
  git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  echo "brief of $1" | csa_run spawn "$1" "$repo" -
}

# 基本的なコマンドだけを置いた PATH を作る(省くツールを引数で指定する)
restricted_path() {
  local dir="$BATS_TEST_TMPDIR/restricted" t p
  mkdir -p "$dir"
  for t in bash env awk sed cat mkdir dirname basename readlink ln cp mv rm date mktemp tr grep head jq git; do
    [[ " $* " == *" $t "* ]] && continue
    p=$(command -v "$t") && ln -sf "$p" "$dir/$t"
  done
  [[ " $* " == *" herdr "* ]] || ln -sf "$REPO_ROOT/test/fake-bin/herdr" "$dir/herdr"
  ln -sf "$REPO_ROOT/test/fake-bin/claude" "$dir/claude"
  echo "$dir"
}

@test "init: 必須ツールが欠けていれば、すべて列挙して何も作らずに失敗する" {
  local rpath
  rpath=$(restricted_path jq git)
  run env PATH="$rpath" "${CSA_BASH:-bash}" "$CSA" init
  [ "$status" -eq 1 ]
  [[ "$output" == *"- jq"* ]]
  [[ "$output" == *"- git"* ]]
  [ ! -e "$CSA_HOME" ]
  [ ! -e "$CSA_BIN_DIR/csa" ]
}

@test "init: herdr のバージョンが違えば警告するが、処理は続ける" {
  FAKE_HERDR_VERSION=9.9.9 run csa_run init
  [ "$status" -eq 0 ]
  [[ "$output" == *"herdr 9.9.9 は未確認のバージョン"* ]]
  [ -d "$CSA_HOME/tasks" ]
}

@test "init: テンプレートを上書きし、local ファイルには触れず、2 回目で差分が出ない" {
  csa_run init
  echo "my rule" >"$CSA_HOME/CLAUDE.local.md"
  echo "edited" >"$CSA_HOME/AGENTS.md"
  csa_run init
  cmp "$CSA_HOME/AGENTS.md" "$REPO_ROOT/skills/csa/assets/AGENTS.md"
  cmp "$CSA_HOME/.claude/settings.json" "$REPO_ROOT/skills/csa/assets/claude-settings.json"
  [ "$(cat "$CSA_HOME/CLAUDE.local.md")" = "my rule" ]
  [ "$(readlink -f "$CSA_BIN_DIR/csa")" = "$(readlink -f "$CSA")" ]
  local before after
  before=$(cd "$CSA_HOME" && find . -type f -exec cksum {} + | sort)
  csa_run init
  after=$(cd "$CSA_HOME" && find . -type f -exec cksum {} + | sort)
  [ "$before" = "$after" ]
}

@test "init: 別の場所を指す csa があれば上書きせずに失敗する" {
  mkdir -p "$CSA_BIN_DIR"
  touch "$BATS_TEST_TMPDIR/other-csa"
  ln -s "$BATS_TEST_TMPDIR/other-csa" "$CSA_BIN_DIR/csa"
  run csa_run init
  [ "$status" -eq 1 ]
  [[ "$output" == *"すでに別の場所"* ]]
  [ "$(readlink "$CSA_BIN_DIR/csa")" = "$BATS_TEST_TMPDIR/other-csa" ]
}

@test "init: リンク切れの csa は張り直す" {
  mkdir -p "$CSA_BIN_DIR"
  ln -s "$BATS_TEST_TMPDIR/gone/csa" "$CSA_BIN_DIR/csa"
  run csa_run init
  [ "$status" -eq 0 ]
  [ "$(readlink -f "$CSA_BIN_DIR/csa")" = "$(readlink -f "$CSA")" ]
}

@test "init: Claude Code の settings.json に Worker 用の allow がなければ推奨を表示する" {
  run csa_run init
  [[ "$output" == *'"Bash(csa report:*)"'* ]]
  [[ "$output" == *'"Edit(~/.csa/plans/**)"'* ]]
  mkdir -p "$HOME/.claude"
  echo '{"permissions":{"allow":["Bash(csa report:*)","Edit(~/.csa/plans/**)","Write(~/.csa/plans/**)"]}}' >"$HOME/.claude/settings.json"
  run csa_run init
  [[ "$output" != *"推奨します"* ]]
}

@test "spawn: 同じ課題で 2 回呼んでも Worker を二重に起動しない" {
  spawn_issue PROJ-1
  run spawn_issue PROJ-1
  [ "$status" -eq 0 ]
  [[ "$output" == *"already running: w-proj-1"* ]]
  [ "$(grep -c '^agent start w-proj-1' "$FAKE_HERDR_DIR/calls.log")" -eq 1 ]
  [ "$(grep -c '^=== w-proj-1' "$FAKE_HERDR_DIR/prompts.log")" -eq 1 ]
}

@test "spawn: 起動直後に止まったら記録を残し、承認後の再実行で brief を 1 回だけ送る" {
  mkdir -p "$FAKE_HERDR_DIR"
  touch "$FAKE_HERDR_DIR/start-blocks"
  run spawn_issue PROJ-8
  [ "$status" -eq 1 ]
  grep -q '^status: blocked$' "$CSA_HOME/tasks/PROJ-8.md"
  grep -q '^prompted: no$' "$CSA_HOME/tasks/PROJ-8.md"
  [ ! -e "$FAKE_HERDR_DIR/prompts.log" ]
  # 人間が承認する前の再実行では送らない
  run spawn_issue PROJ-8
  [ "$status" -eq 1 ]
  [ ! -e "$FAKE_HERDR_DIR/prompts.log" ]
  # 承認後の再実行で送り、その次は何もしない
  rm "$FAKE_HERDR_DIR/blocked-w-proj-8"
  spawn_issue PROJ-8
  grep -q '^status: working$' "$CSA_HOME/tasks/PROJ-8.md"
  grep -q '^prompted: yes$' "$CSA_HOME/tasks/PROJ-8.md"
  run spawn_issue PROJ-8
  [[ "$output" == *"already running"* ]]
  [ "$(grep -c '^=== w-proj-8' "$FAKE_HERDR_DIR/prompts.log")" -eq 1 ]
  [ "$(grep -c '^agent start w-proj-8' "$FAKE_HERDR_DIR/calls.log")" -eq 1 ]
}

@test "spawn: プロンプトに csa-worker の SKILL.md の絶対パスと plan の保存先が含まれる" {
  spawn_issue PROJ-2
  grep -qF "$REPO_ROOT/skills/csa-worker/SKILL.md" "$FAKE_HERDR_DIR/prompts.log"
  grep -qF "$CSA_HOME/plans/PROJ-2.md" "$FAKE_HERDR_DIR/prompts.log"
  grep -qF "brief of PROJ-2" "$FAKE_HERDR_DIR/prompts.log"
}

@test "peek: スクロールバックが空なら見えている画面を読む" {
  spawn_issue PROJ-9
  run csa_run peek PROJ-9
  [[ "$output" == *"recent-unwrapped"* ]]
  FAKE_HERDR_ALT_SCREEN=1 run csa_run peek PROJ-9
  [[ "$output" == *"--source visible"* ]]
}

@test "report: タスクファイルの状態とログを更新し、working 以外は CSA に知らせる" {
  spawn_issue PROJ-3
  csa_run report PROJ-3 working "見積もり: plan 不要"
  ! grep -q '^=== csa' "$FAKE_HERDR_DIR/prompts.log"
  csa_run report PROJ-3 review "done on csa/PROJ-3"
  grep -q '^status: review$' "$CSA_HOME/tasks/PROJ-3.md"
  grep -q 'working: 見積もり: plan 不要' "$CSA_HOME/tasks/PROJ-3.md"
  grep -q '^\[report\] PROJ-3 review: done on csa/PROJ-3$' "$FAKE_HERDR_DIR/prompts.log"
}

@test "report plan: plan ファイルがなければ失敗し、あれば plan 行を書く" {
  spawn_issue PROJ-4
  run csa_run report PROJ-4 plan "要約"
  [ "$status" -eq 1 ]
  grep -q '^status: working$' "$CSA_HOME/tasks/PROJ-4.md"
  echo "# plan" >"$CSA_HOME/plans/PROJ-4.md"
  csa_run report PROJ-4 plan "要約"
  grep -q "^plan: $CSA_HOME/plans/PROJ-4.md$" "$CSA_HOME/tasks/PROJ-4.md"
  grep -q '^status: plan$' "$CSA_HOME/tasks/PROJ-4.md"
}

@test "approve: plan 状態のときだけ送り、2 回目は何も送らない" {
  spawn_issue PROJ-5
  run csa_run approve PROJ-5
  [ "$status" -eq 1 ]
  echo "# plan" >"$CSA_HOME/plans/PROJ-5.md"
  csa_run report PROJ-5 plan "要約"
  csa_run approve PROJ-5 "人間: OK です"
  grep -q '^status: working$' "$CSA_HOME/tasks/PROJ-5.md"
  grep -q 'approved: 人間: OK です' "$CSA_HOME/tasks/PROJ-5.md"
  run csa_run approve PROJ-5
  [ "$status" -eq 1 ]
  [ "$(grep -c 'plan(.*)が承認されました' "$FAKE_HERDR_DIR/prompts.log")" -eq 1 ]
}

@test "approve: 送信を確認できなければ状態を plan のまま残す" {
  spawn_issue PROJ-6
  echo "# plan" >"$CSA_HOME/plans/PROJ-6.md"
  csa_run report PROJ-6 plan "要約"
  FAKE_HERDR_PROMPT_FAIL=1 run csa_run approve PROJ-6
  [ "$status" -eq 1 ]
  grep -q '^status: plan$' "$CSA_HOME/tasks/PROJ-6.md"
}

@test "status: 課題の一覧と、plan 状態の課題の plan のパスを表示する" {
  spawn_issue PROJ-7
  echo "# plan" >"$CSA_HOME/plans/PROJ-7.md"
  csa_run report PROJ-7 plan "要約"
  run csa_run status
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROJ-7"*"w-proj-7"*"plan"*"idle"*"$CSA_HOME/plans/PROJ-7.md"* ]]
}

@test "doctor: 新しいバージョンがあれば知らせ、取得に失敗しても何も言わない" {
  command -v curl >/dev/null || skip "curl がない"
  csa_run init >/dev/null 2>&1
  local remote="$BATS_TEST_TMPDIR/remote-SKILL.md"
  sed 's/version: "[^"]*"/version: "99.0.0"/' "$REPO_ROOT/skills/csa/SKILL.md" >"$remote"
  CSA_UPDATE_CHECK=1 CSA_UPDATE_URL="file://$remote" run csa_run doctor
  [[ "$output" == *"新しいバージョン 99.0.0 があります"* ]]
  rm -f "$CSA_HOME/.update-check"
  CSA_UPDATE_CHECK=1 CSA_UPDATE_URL="file://$BATS_TEST_TMPDIR/missing" run csa_run doctor
  [[ "$output" != *"新しいバージョン"* ]]
}

@test "skills: frontmatter が Agent Skills の仕様に沿い、バージョンがそろっている" {
  local dir name desc keys versions
  for dir in "$REPO_ROOT"/skills/*/; do
    dir=${dir%/}
    name=$(awk 'NR>1 && /^---$/{exit} /^name:/{print $2}' "$dir/SKILL.md")
    [ "$name" = "$(basename "$dir")" ]
    desc=$(awk 'NR>1 && /^---$/{exit} /^description:/{sub(/^description: */,""); print}' "$dir/SKILL.md")
    [ -n "$desc" ]
    [ "$(printf '%s' "$desc" | wc -m)" -le 1024 ]
    keys=$(awk 'NR>1 && /^---$/{exit} NR>1 && /^[a-z-]+:/{sub(/:.*/,""); print}' "$dir/SKILL.md")
    for k in $keys; do
      [[ " name description license compatibility metadata allowed-tools " == *" $k "* ]]
    done
  done
  versions=$(awk '/^[[:space:]]+version:/{print $2}' "$REPO_ROOT"/skills/*/SKILL.md | sort -u | wc -l)
  [ "$versions" -eq 1 ]
}
