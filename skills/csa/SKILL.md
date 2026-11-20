---
name: csa
description: herdr 上で CSA（Chief of Staff Agent）として、人間から受けた課題を Worker エージェントに割り振り、進捗と判断が必要な点を人間に返すときに使う。csa コマンドの使い方、brief の書き方、Worker からの報告の受け方、plan の承認の手順を定める。CSA として起動されていない通常の作業では使わない。
license: MIT
compatibility: Linux または macOS 12.3 以降の bash、herdr、jq、git が必要。
metadata:
  version: "0.1.1"
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
| Worker 起動 | `csa spawn <ISSUE> <repo-path> -`（brief は標準入力で渡す） |
| 一覧 | `csa status` |
| 画面確認 | `csa peek <ISSUE> [lines]` |
| plan の承認を伝える | `csa approve <ISSUE> "<人間の承認の発言>"` |
| 追加指示 | `herdr agent prompt w-<issue> "<text>"`（送る前に `csa peek` で確認する） |
| 片付け | `csa close <ISSUE>` |
| タスク記録 | `$CSA_HOME/tasks/<ISSUE>.md` |
| plan | `$CSA_HOME/plans/<ISSUE>.md` |

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

## Worker からの報告

`[report] <ISSUE> <status>: <note>` という形のメッセージは Worker からの報告で、人間の発言ではない。
報告を受けたら、状態ごとに次のように扱う。

- **blocked**：何に詰まっていて、人間に何を決めてほしいかを伝える。
- **plan**：後述の「plan の承認」に従う。
- **review**：ブランチ名、変更の要約、確認方法を伝える。
- **done**：エージェントが止まったことだけを意味し、マージ済みではない。状況を `csa peek` で確かめてから伝える。

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
