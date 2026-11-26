# Changelog

## Unreleased

- ドキュメントやソースコードを調べるだけの課題（ファイルの編集、コミット、push を伴わない課題）は、人間が言わなくても CSA が `csa spawn --no-eval` で起動するようにした。CSA は、brief に根拠と「直す作業が必要になったら blocked で止まる」ことを書く。
- 調べる途中で直す作業が必要になったら、Worker は blocked で止まる。CSA は人間に範囲を広げるかを聞き、認められたら `csa eval on` で評価を有効にしてから Worker に直させる。

## 0.2.0

- Worker の review の報告のあとに、Worker とは別のエージェント（evaluator）が成果物を評価するようにした。evaluator は csa が別の tab で起動し、brief、plan、評価の基準、人間の発言の記録、差分だけを読む。Worker の会話は引き継がない。
- evaluator は、変更されたモジュールを差分より先に調べ、部分最適になっていないかを確かめる。指摘は不合格、助言、要相談に分け、統合性の指摘は原則として助言にする。
- 不合格なら Worker に差し戻す。同じ話題で 3 回不合格になったとき、evaluator が判断できないとき、同じ指摘が直されずに残ったとき、Worker が指摘に同意できないときは、止めて人間に判断を仰ぐ。
- 既定ですべての課題を評価する。人間が不要と明示した課題は `csa spawn --no-eval` と `csa eval off` で評価を止める。コミットのない課題では評価を省き、evaluator は評価できなければ棄権する。
- Worker は、push を許可された課題でも、評価に合格するまで push しない。
- 人間の発言を記録する `csa human add`、`csa human approve`、`csa human list` を足した。plan の直接の承認は `csa human approve` で記録する。
- 評価の基準と結果を `~/.csa/eval/`（`criteria/`、`context/`、`results/`）に置くようにした。既定の基準は `csa init` と `csa up` が上書きする。
- タスクファイルの行を書き換える処理が、ない行を足すようにした。値のバックスラッシュを解釈しないようにした。

## 0.1.1

- Worker と CSA の決まりを原則とし、人間の明示的な指示を優先するようにした。Worker は、人間か CSA が明示的に許可した行為（完了後の push など）を、許可された課題と範囲の中で行い、`csa report` に記録する。CSA は、人間が許可した例外だけを brief か追加の指示で Worker に伝える。

## 0.1.0

最初のリリース。

- CSA と Worker の手順を、Agent Skills の形式の 2 つの skill（`csa` と `csa-worker`）として提供する。`npx skills` で Claude Code や Codex などに入れられる。
- `csa` コマンドに、`init`、`up`、`doctor`、`version`、`spawn`、`status`、`report`、`approve`、`peek`、`close` を用意した。
- Worker は着手前に規模を見積もり、基準に当てはまる課題では plan を書いて人間の承認を待つ。承認は `csa approve` で Worker に伝える。
- CSA の決まりごとは `AGENTS.md` に置き、Claude Code 以外のエージェントでも同じ決まりで動く。
- Worker が起動直後の確認（フォルダの信頼など）で止まっても記録を残し、人間の承認後に `csa spawn` を再実行すると brief を 1 回だけ送る。
- 人間が Worker と直接やり取りした結果は、Worker が `csa report` で記録する。
- README に、Codex で確認なしに進めるための設定と、フォルダの信頼の確認の扱いを書いた。
