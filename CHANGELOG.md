# Changelog

## Unreleased

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
