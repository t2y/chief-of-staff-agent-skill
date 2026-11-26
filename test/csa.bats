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

# --no-eval で課題を 1 件 spawn した状態を作る
spawn_issue_no_eval() {
  csa_run init >/dev/null 2>&1
  local repo="$BATS_TEST_TMPDIR/repo"
  git init -q "$repo"
  git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  echo "brief of $1" | csa_run spawn --no-eval "$1" "$repo" -
}

worktree_of() { echo "$BATS_TEST_TMPDIR/repo/.csa-worktrees/$1"; }

# 課題の worktree にコミットを 1 つ足す
commit_in() {
  local wt; wt=$(worktree_of "$1")
  echo "${2:-change}" >>"$wt/file.txt"
  git -C "$wt" add file.txt
  git -C "$wt" -c user.name=t -c user.email=t@example.com commit -q -m "${2:-change}"
}

task_field() { awk -v k="$2:" '$0 == "---" { exit } $1 == k { $1 = ""; sub(/^ /, ""); print; exit }' "$CSA_HOME/tasks/$1.md"; }

# evaluator が結果を書いて報告したことにする
evaluate() { # evaluate ISSUE verdict [本文]
  local f; f=$(task_field "$1" eval_file)
  printf 'verdict: %s\n%s\n' "$2" "${3:-}" >"$f"
  csa_run report "$1" evaluated "$2"
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
  [[ "$output" == *'"Bash(csa human:*)"'* ]]
  [[ "$output" == *'"Write(~/.csa/eval/results/**)"'* ]]
  echo '{"permissions":{"allow":["Bash(csa report:*)","Bash(csa human:*)","Edit(~/.csa/plans/**)","Write(~/.csa/plans/**)","Edit(~/.csa/eval/results/**)","Write(~/.csa/eval/results/**)"]}}' >"$HOME/.claude/settings.json"
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
  # コミットがないので評価を省き、そのことを添えて送る
  grep -q '^\[report\] PROJ-3 review: done on csa/PROJ-3 / 評価: 省略(差分なし)$' "$FAKE_HERDR_DIR/prompts.log"
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

@test "eval: --no-eval の課題は evaluator を起動せずに CSA に送り、Worker に基準を渡さない" {
  spawn_issue_no_eval PROJ-20
  ! grep -qF "$CSA_HOME/eval/criteria/default.md" "$FAKE_HERDR_DIR/prompts.log"
  commit_in PROJ-20
  csa_run report PROJ-20 review "done"
  grep -q '^status: review$' "$CSA_HOME/tasks/PROJ-20.md"
  ! grep -q '^agent start e-proj-20' "$FAKE_HERDR_DIR/calls.log"
  grep -q '^\[report\] PROJ-20 review: done$' "$FAKE_HERDR_DIR/prompts.log"
}

@test "eval: 既定ではコミットのある課題の review で evaluator を別の tab で起動し、CSA には送らない" {
  spawn_issue PROJ-21
  grep -qF "$CSA_HOME/eval/criteria/default.md" "$FAKE_HERDR_DIR/prompts.log"
  commit_in PROJ-21
  run csa_run report PROJ-21 review "worker note"
  [ "$status" -eq 0 ]
  grep -q '^status: eval$' "$CSA_HOME/tasks/PROJ-21.md"
  grep -q '^tab create .*--label PROJ-21-eval' "$FAKE_HERDR_DIR/calls.log"
  grep -q '^agent start e-proj-21' "$FAKE_HERDR_DIR/calls.log"
  ! grep -q '^=== csa' "$FAKE_HERDR_DIR/prompts.log"
  [ "$(task_field PROJ-21 eval_round)" = 1 ]
  [ "$(task_field PROJ-21 eval_file)" = "$CSA_HOME/eval/results/PROJ-21/impl-1.md" ]
  # evaluator の prompt に、手順書と brief と人間の発言の読み方が含まれ、Worker の note は含まれない
  local p; p=$(awk '/^=== e-proj-21/{f=1;next} /^=== /{f=0} f' "$FAKE_HERDR_DIR/prompts.log")
  [[ "$p" == *"references/evaluator.md"* ]]
  [[ "$p" == *"brief of PROJ-21"* ]]
  [[ "$p" == *"csa human list PROJ-21"* ]]
  [[ "$p" != *"worker note"* ]]
}

@test "eval: コミットしていない変更があれば評価を始めずに失敗する" {
  spawn_issue PROJ-22
  commit_in PROJ-22
  echo dirty >>"$(worktree_of PROJ-22)/file.txt"
  run csa_run report PROJ-22 review "done"
  [ "$status" -eq 1 ]
  [[ "$output" == *"コミットしてから"* ]]
  grep -q '^status: working$' "$CSA_HOME/tasks/PROJ-22.md"
  ! grep -q '^agent start e-proj-22' "$FAKE_HERDR_DIR/calls.log"
}

@test "eval: 合格すると review になり、回数を 0 に戻し、CSA と Worker に送ってから tab を閉じる" {
  spawn_issue PROJ-23
  commit_in PROJ-23
  csa_run report PROJ-23 review "worker note"
  evaluate PROJ-23 pass $'\n## 助言\n\n### ほかの呼び出し元\n- x'
  grep -q '^status: review$' "$CSA_HOME/tasks/PROJ-23.md"
  [ "$(task_field PROJ-23 eval_round)" = 0 ]
  [ "$(task_field PROJ-23 eval_passed)" = "$(git -C "$(worktree_of PROJ-23)" rev-parse HEAD)" ]
  grep -q '^\[report\] PROJ-23 review: worker note / 評価: 合格(助言 1 件)' "$FAKE_HERDR_DIR/prompts.log"
  grep -q '評価に合格しました' "$FAKE_HERDR_DIR/prompts.log"
  # tab を閉じるのは、CSA への送信より後
  local sent closed
  sent=$(grep -n '^agent prompt csa' "$FAKE_HERDR_DIR/calls.log" | tail -1 | cut -d: -f1)
  closed=$(grep -n '^tab close' "$FAKE_HERDR_DIR/calls.log" | tail -1 | cut -d: -f1)
  ((closed > sent))
  # 合格した HEAD のままの review(push の報告など)は評価しない
  csa_run report PROJ-23 review "pushed"
  [ "$(grep -c '^agent start e-proj-23' "$FAKE_HERDR_DIR/calls.log")" -eq 1 ]
  grep -q '^\[report\] PROJ-23 review: pushed$' "$FAKE_HERDR_DIR/prompts.log"
}

@test "eval: 棄権すると review になり、回数を変えずに理由を CSA に送る" {
  spawn_issue PROJ-24
  commit_in PROJ-24
  csa_run report PROJ-24 review "note"
  evaluate PROJ-24 abstain "確かめる手段がない"
  grep -q '^status: review$' "$CSA_HOME/tasks/PROJ-24.md"
  [ "$(task_field PROJ-24 eval_round)" = 1 ]
  grep -q '評価: 棄権(確かめる手段がない)' "$FAKE_HERDR_DIR/prompts.log"
}

@test "eval: 不合格なら Worker に差し戻し、同じ話題で 3 回目の不合格でエスカレーションする" {
  spawn_issue PROJ-25
  local i
  for i in 1 2; do
    commit_in PROJ-25 "fix $i"
    csa_run report PROJ-25 review "note"
    evaluate PROJ-25 fail $'\n## 不合格\n\n### plan にない変更'
    grep -q '^status: working$' "$CSA_HOME/tasks/PROJ-25.md"
  done
  grep -q 'push はしないでください' "$FAKE_HERDR_DIR/prompts.log"
  grep -q '同意できない指摘があれば' "$FAKE_HERDR_DIR/prompts.log"
  ! grep -q '^=== csa' "$FAKE_HERDR_DIR/prompts.log"
  # 2 回目の prompt は前の回の評価を読む
  grep -qF "前の回の評価: $CSA_HOME/eval/results/PROJ-25/impl-1.md" "$FAKE_HERDR_DIR/prompts.log"
  commit_in PROJ-25 "fix 3"
  csa_run report PROJ-25 review "note"
  evaluate PROJ-25 fail $'\n## 不合格\n\n### plan にない変更'
  grep -q '^status: blocked$' "$CSA_HOME/tasks/PROJ-25.md"
  grep -q '^\[report\] PROJ-25 blocked: 評価で要相談(同じ話題で 3 回不合格).*論点: plan にない変更.*(a) Worker の案で進める' "$FAKE_HERDR_DIR/prompts.log"
  # 上限の後の review は評価を挟まない
  csa_run report PROJ-25 review "人間が (a) を選んだ"
  [ "$(grep -c '^agent start e-proj-25' "$FAKE_HERDR_DIR/calls.log")" -eq 3 ]
  grep -q '^status: review$' "$CSA_HOME/tasks/PROJ-25.md"
}

@test "eval: blocked から working に戻ると回数を 0 に戻し、次の review で再び評価する" {
  spawn_issue PROJ-26
  commit_in PROJ-26
  csa_run report PROJ-26 review "note"
  evaluate PROJ-26 escalate $'\n## 要相談\n\n### 解釈が分かれる'
  grep -q '^status: blocked$' "$CSA_HOME/tasks/PROJ-26.md"
  grep -q '評価で要相談(evaluator が判断できない).*論点: 解釈が分かれる' "$FAKE_HERDR_DIR/prompts.log"
  csa_run report PROJ-26 working "人間の判断を受けて再開"
  [ "$(task_field PROJ-26 eval_round)" = 0 ]
  commit_in PROJ-26 again
  csa_run report PROJ-26 review "note"
  grep -q '^status: eval$' "$CSA_HOME/tasks/PROJ-26.md"
  [ "$(task_field PROJ-26 eval_file)" = "$CSA_HOME/eval/results/PROJ-26/impl-2.md" ]
}

@test "eval: 評価中に HEAD が変われば無効にし、追跡されていないファイルが増えただけなら無効にしない" {
  spawn_issue PROJ-27
  commit_in PROJ-27
  csa_run report PROJ-27 review "note"
  touch "$(worktree_of PROJ-27)/coverage.out"
  evaluate PROJ-27 pass
  grep -q '^status: review$' "$CSA_HOME/tasks/PROJ-27.md"
  commit_in PROJ-27 more
  csa_run report PROJ-27 review "note"
  commit_in PROJ-27 during
  evaluate PROJ-27 pass
  grep -q '^status: blocked$' "$CSA_HOME/tasks/PROJ-27.md"
  grep -q '評価を無効にした' "$FAKE_HERDR_DIR/prompts.log"
}

@test "eval: 状態が eval でないときの evaluated は状態を変えない" {
  spawn_issue PROJ-28
  csa_run report PROJ-28 evaluated "late"
  grep -q '^status: working$' "$CSA_HOME/tasks/PROJ-28.md"
  grep -q '記録だけにした' "$CSA_HOME/tasks/PROJ-28.md"
}

@test "eval off: 人間の発言の引用が要り、評価中なら review にし、blocked ならそのままにする" {
  spawn_issue PROJ-29
  run csa_run eval off PROJ-29 --by csa
  [ "$status" -ne 0 ]
  commit_in PROJ-29
  csa_run report PROJ-29 review "note"
  csa_run eval off PROJ-29 --by csa "evaluator は不要です"
  grep -q '^status: review$' "$CSA_HOME/tasks/PROJ-29.md"
  grep -q '^eval: off$' "$CSA_HOME/tasks/PROJ-29.md"
  grep -q '評価: off(人間の指示)' "$FAKE_HERDR_DIR/prompts.log"
  run csa_run human list PROJ-29
  [[ "$output" == *"human(csa) eval-off: 「evaluator は不要です」"* ]]

  spawn_issue PROJ-30
  commit_in PROJ-30
  csa_run report PROJ-30 review "note"
  evaluate PROJ-30 escalate
  csa_run eval off PROJ-30 --by worker "ここからは直接議論しましょう"
  grep -q '^status: blocked$' "$CSA_HOME/tasks/PROJ-30.md"
  csa_run report PROJ-30 working "再開"
  commit_in PROJ-30 again
  csa_run report PROJ-30 review "note"
  grep -q '^status: review$' "$CSA_HOME/tasks/PROJ-30.md"
}

@test "eval on: 起動に失敗した evaluator を、回数に数えずに起動し直す" {
  spawn_issue PROJ-31
  commit_in PROJ-31
  touch "$FAKE_HERDR_DIR/start-blocks"
  csa_run report PROJ-31 review "note"
  grep -q '^status: blocked$' "$CSA_HOME/tasks/PROJ-31.md"
  grep -q 'evaluator を起動できなかった' "$FAKE_HERDR_DIR/prompts.log"
  csa_run eval on PROJ-31
  grep -q '^status: eval$' "$CSA_HOME/tasks/PROJ-31.md"
  [ "$(task_field PROJ-31 eval_round)" = 1 ]
}

@test "human: add と approve は決まった形で記録し、list は人間の発言だけを表示する" {
  spawn_issue PROJ-32
  run csa_run human add PROJ-32 --by worker ""
  [ "$status" -ne 0 ]
  run csa_run human add PROJ-32 --by someone "x"
  [ "$status" -ne 0 ]
  csa_run human add PROJ-32 --by worker "thu は触らない" "thu のホストは対象外と読んだ"
  grep -q '^status: working$' "$CSA_HOME/tasks/PROJ-32.md"
  ! grep -q '^=== csa' "$FAKE_HERDR_DIR/prompts.log"
  run csa_run human approve PROJ-32 "承認します"
  [ "$status" -ne 0 ]
  echo "# plan" >"$CSA_HOME/plans/PROJ-32.md"
  csa_run report PROJ-32 plan "worker の要約"
  csa_run human approve PROJ-32 "plan を承認します"
  grep -q '^status: working$' "$CSA_HOME/tasks/PROJ-32.md"
  run csa_run human list PROJ-32
  [[ "$output" == *"human(worker): 「thu は触らない」 / 読み取り: thu のホストは対象外と読んだ"* ]]
  [[ "$output" == *"human(worker) approve: 「plan を承認します」"* ]]
  [[ "$output" != *"worker の要約"* ]]
}

@test "eval: context の match: が remote に一致したファイルだけを evaluator に渡し、Worker には渡さない" {
  csa_run init >/dev/null 2>&1
  printf 'match: group/app/\n' >"$CSA_HOME/eval/context/app.md"
  printf 'match: other/\n' >"$CSA_HOME/eval/context/other.md"
  local repo="$BATS_TEST_TMPDIR/repo"
  git init -q "$repo"
  git -C "$repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
  git -C "$repo" remote add origin git@example.com:group/app/server.git
  echo "brief" | csa_run spawn PROJ-33 "$repo" -
  ! grep -qF "context/app.md" "$FAKE_HERDR_DIR/prompts.log"
  commit_in PROJ-33
  csa_run report PROJ-33 review "note"
  grep -qF "$CSA_HOME/eval/context/app.md" "$FAKE_HERDR_DIR/prompts.log"
  ! grep -qF "context/other.md" "$FAKE_HERDR_DIR/prompts.log"
}

@test "init: 既定の基準を上書きし、利用者の基準と結果には触れない" {
  csa_run init
  echo mine >"$CSA_HOME/eval/criteria/local.md"
  echo edited >"$CSA_HOME/eval/criteria/default.md"
  mkdir -p "$CSA_HOME/eval/results/X"; echo r >"$CSA_HOME/eval/results/X/impl-1.md"
  csa_run init
  cmp "$CSA_HOME/eval/criteria/default.md" "$REPO_ROOT/skills/csa/assets/eval-criteria.md"
  [ "$(cat "$CSA_HOME/eval/criteria/local.md")" = mine ]
  [ "$(cat "$CSA_HOME/eval/results/X/impl-1.md")" = r ]
  [ -d "$CSA_HOME/eval/criteria/repos" ]
}

@test "eval: eval の行がない古いタスクファイルは on として扱い、行を足して遷移する" {
  spawn_issue PROJ-34
  local t="$CSA_HOME/tasks/PROJ-34.md"
  grep -v -E '^(eval|eval_round|eval_file|eval_tab|eval_head|eval_passed|eval_note|base):' "$t" >"$t.tmp" && mv "$t.tmp" "$t"
  commit_in PROJ-34
  csa_run report PROJ-34 review "note"
  grep -q '^status: eval$' "$t"
  grep -q '^eval_round: 1$' "$t"
  # 足した行は --- より前にある
  [ "$(awk '/^---$/{print NR; exit}' "$t")" -gt "$(grep -n '^eval_round:' "$t" | cut -d: -f1)" ]
}

@test "status: 評価中の課題は evaluator の agent と eval のファイルを表示する" {
  spawn_issue PROJ-35
  commit_in PROJ-35
  csa_run report PROJ-35 review "note"
  run csa_run status
  [[ "$output" == *"PROJ-35"*"e-proj-35"*"eval"*"impl-1.md"* ]]
  run csa_run peek PROJ-35 --eval
  [[ "$output" == *"screen of e-proj-35"* ]]
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
