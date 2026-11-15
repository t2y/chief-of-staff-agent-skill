# Changelog

## 0.1.0

- csa-kit を Agent Skills の形式の 2 つの skill（`csa` と `csa-worker`）として再構成した。
- `csa init`、`csa doctor`、`csa version` を追加した。`csa-up` は `csa up` に統合した。
- Worker が着手前に規模を見積もり、基準に当てはまる課題では plan を書いて人間の承認を待つようにした。承認を伝える `csa approve` を追加した。
- CSA の決まりごとを `AGENTS.md` に移し、Claude Code 以外のエージェントでも同じ決まりで動くようにした。
- `csa status` が herdr の状態を読むキーを `.result.agent.agent_status` に直した。
- `csa spawn` は、Worker が起動直後の確認（フォルダの信頼など）で止まっても記録を残し、承認後の再実行で brief を 1 回だけ送るようにした。
- `csa peek` は、スクロールバックが空のとき（Codex など）に見えている画面を読むようにした。
- README に、Codex で確認なしに進めるための設定と、フォルダの信頼の確認の扱いを書いた。
