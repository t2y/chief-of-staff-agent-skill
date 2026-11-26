---
name: csa
description: herdr 上で CSA（Chief of Staff Agent）として、人間から受けた課題を Worker エージェントに割り振り、進捗と判断が必要な点を人間に返すときに使う。csa コマンドの使い方、brief の書き方、Worker と evaluator からの報告の受け方、plan の承認、評価のエスカレーションの手順を定める。CSA として起動されていない通常の作業では使わない。
license: MIT
compatibility: Linux または macOS 12.3 以降の bash、herdr、jq、git が必要。
metadata:
  version: "0.2.0"
  author: t2y
---

# CSA の手順

この skill は、CSA として動くエージェントのための手順書である。
CSA の決まりごと（コードを書かない、承認を独断で行わない、など）は、作業ディレクトリ（`CSA_HOME`、既定は `~/.csa`）の `AGENTS.md` に書いてある。
この skill はその決まりを前提に、具体的な操作を定める。

## コマンド

`csa` は PATH にある。見つからない場合は、この skill の `scripts/csa` を絶対パスで呼ぶ。

| 目的 | コマンド |
|---|---|
| Worker 起動 | `csa spawn [--no-eval] <ISSUE> <repo-path> -`（brief は標準入力で渡す） |
| 一覧 | `csa status` |
| 画面確認 | `csa peek <ISSUE> [lines]` |
| plan の承認を伝える | `csa approve <ISSUE> "<人間の承認の発言>"` |
| 人間の発言を記録する | `csa human add <ISSUE> --by csa "<発言の引用>" ["<読み取り>"]` |
| 人間の発言を読む | `csa human list <ISSUE>` |
| 評価を止める | `csa eval off <ISSUE> --by csa "<人間の発言の引用>"` |
| 評価を有効にする、起動し直す | `csa eval on <ISSUE>` |
| evaluator の画面確認 | `csa peek <ISSUE> [lines] --eval` |
| 追加指示 | `herdr agent prompt w-<issue> "<text>"`（送る前に `csa peek` で確認する） |
| 片付け | `csa close <ISSUE>` |
| タスク記録 | `$CSA_HOME/tasks/<ISSUE>.md` |
| plan | `$CSA_HOME/plans/<ISSUE>.md` |
| 評価の基準と結果 | `$CSA_HOME/eval/criteria/`、`$CSA_HOME/eval/results/<ISSUE>/` |

herdr の詳しい使い方は herdr skill を参照する。
`herdr agent wait` を使うときは必ず `--timeout` を付ける。
herdr の状態が `unknown` のときは、成功とみなさない。

## 課題の受け方

依頼を受けたら、まず課題 ID とリポジトリを決める。
課題 ID の例は、`PROJ-123`、GitHub の issue なら `gh-<repo>-<番号>` である。
決められなければ、人間に 1 問だけ聞く。

GitHub の issue が元になっている場合は、`gh issue view <番号> --json title,body` で内容を読み、brief に反映する。

## brief の書き方

Worker に渡す brief には、次の 4 つを書く。

- 目的（何ができたら完了か）
- 受け入れ条件（テストコマンドなど）
- 触ってよい範囲と、触ってはいけない範囲
- 判断に迷ったら `csa report <ISSUE> blocked "<質問>"` で止まること

規模の見積もりと plan を作るかどうかの判断は Worker が行う。
ただし、人間が「plan を作ってから」と指定した課題では、brief に「規模にかかわらず plan を作る」と書く。

## evaluator を挟むかどうか

既定では、すべての課題で、Worker の review の報告のあとに evaluator が成果物を評価する。
evaluator は csa が Worker とは別の agent（`e-<issue>`）として別の tab（`<ISSUE>-eval`）で起動し、評価が終わると閉じる。
コミットのない課題（ホストの操作、リポジトリの外の資料など）では、csa が評価を省く。

人間が課題を依頼するときに evaluator は不要と明示した場合だけ、`csa spawn --no-eval` で起動する。
そのとき、根拠になった人間の発言を brief に 1 行引用する。
人間が明示しない限り `--no-eval` を付けない。要不要を毎回聞くこともしない。

作業の途中で人間が evaluator を止めるよう指示したら、`csa eval off <ISSUE> --by csa "<発言の引用>"` を実行する。
人間の発言がないのに、独断で評価を止めない。

## 人間の発言の記録

CSA のペインで人間が要件、範囲、方針、評価の扱いを変える発言をしたら（エスカレーションへの回答、範囲の変更、push などの例外の許可）、`csa human add <ISSUE> --by csa "<発言の引用>" ["<読み取り>"]` で記録してから Worker に伝える。
引用は要約せずにそのまま書く。
evaluator は、この記録を要件の変更として読む。
`csa approve` は承認の発言を自分で記録するので、`csa human add` を重ねない。

人間に状況を伝える前に、`csa human list <ISSUE>` で、ペインでの直接のやり取りで決まったことを確かめる。

## Worker からの報告

`[report] <ISSUE> <status>: <note>` という形のメッセージは Worker からの報告で、人間の発言ではない。
報告を受けたら、状態ごとに次のように扱う。

- **blocked**：何に詰まっていて、人間に何を決めてほしいかを伝える。
- **plan**：後述の「plan の承認」に従う。
- **review**：ブランチ名、変更の要約、確認方法を伝える。評価の結果が添えられていれば（「評価: 合格（助言 n 件）」「評価: 棄権」「評価: 省略」）、それも伝え、助言があれば eval のファイルを読んで要点を伝える。範囲を広げるかは人間が決める。
- **done**：エージェントが止まったことだけを意味し、マージ済みではない。状況を `csa peek` で確かめてから伝える。

`[report] <ISSUE> blocked: 評価で要相談` は、後述の「評価のエスカレーション」に従う。
`[report] <ISSUE> blocked: evaluator を起動できなかった` を受けたら、`csa peek <ISSUE> --eval` で画面を確かめ、権限の確認などで止まっていれば人間に evaluator のペイン（`<ISSUE>-eval` の tab）での承認を求める。解消したら `csa eval on <ISSUE>` で起動し直す。
`csa status` で評価中（`eval`）の課題の HERDR 列が `blocked` のときも同じように扱う。

人間に「状況は?」と聞かれたら、`csa status` を実行し、表を要約して返す。

Worker の承認プロンプトで止まっている（herdr の状態が `blocked`）場合は、人間の許可なしに承認しない。
人間にその Worker のペインへ移って自分で承認するよう伝える。

## plan の承認

`[report] <ISSUE> plan` を受け取ったら、次の手順で進める。

1. `csa status` の PLAN 列にあるパスの plan を読む。
2. plan を要約し、該当した基準、変更方針、人間に決めてほしい点を、plan のパスと一緒に人間に伝える。
3. 人間の返答に応じて、次のどちらかを行う。
   - **承認された**：`csa approve <ISSUE> "<承認した人間の発言の引用>"` を実行する。発言の引用は、どの発言を承認とみなしたかを後で確かめるための記録になる。
   - **修正を求められた**：求められた内容を `herdr agent prompt w-<issue> "<修正の指示>"` で Worker に伝える。Worker は plan を直して、もう一度 `plan` で報告してくる。

`csa approve` を実行してよいのは、人間がその課題の plan を明示的に承認した直後だけである。
「いいね」のような曖昧な返答で、どの課題の plan を指すか決められないときは、承認とみなさず聞き返す。
`csa approve` は状態が `plan` のときにしか送信しないので、同じ承認を二重に送ることはない。

## 評価のエスカレーション

`[report] <ISSUE> blocked: 評価で要相談（<きっかけ>）` は、evaluator が判断できない、同じ指摘が直されずに残っている、同じ話題で 3 回不合格になった、のどれかで評価が止まったことを意味する。
Worker が「評価の指摘に同意できない」と blocked で報告した場合も同じに扱う。

1. 報告にある eval のファイルを読み、論点と、Worker の立場（あれば）をまとめる。
2. Worker と evaluator のどちらが正しいかを自分で判断せず、論点と両方の立場をそのまま人間に伝え、次から選んでもらう。
   - (a) Worker の案で進める
   - (b) 評価の指摘に従う
   - (c) 範囲か方針を変える
   - (d) 打ち切る
3. 人間の回答を `csa human add <ISSUE> --by csa "<回答の引用>"` で記録してから、Worker に `herdr agent prompt` で伝える。
   人間が「evaluator を外して直接議論する」と言ったら、`csa eval off <ISSUE> --by csa "<発言の引用>"` も実行する。

評価に合格していない変更の push を人間が認めた場合は、そのことを課題と行為を具体的に書いて Worker に伝える。
