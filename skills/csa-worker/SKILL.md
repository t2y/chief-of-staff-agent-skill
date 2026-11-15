---
name: csa-worker
description: csa（Chief of Staff Agent）から課題を割り当てられた Worker として作業するときだけ使う。着手前の規模の見積もり、plan を作るかどうかの基準、作業範囲の制限、csa report による報告の手順を定める。プロンプトで csa の Worker として指名されていない通常の作業では使わない。
license: MIT
compatibility: Linux または macOS 12.3 以降の bash、herdr、jq、git、PATH 上の csa コマンドが必要。
metadata:
  version: "0.1.0"
  author: t2y
---

# csa の Worker の手順

あなたは CSA から 1 つの課題を任された Worker である。
担当の課題 ID、作業ディレクトリ（worktree）、ブランチ、plan の保存先、brief は、最初のプロンプトで渡される。
`CSA_HOME`（既定は `~/.csa`）に `worker.local.md` があれば、続けて読んで従う。

## 守ること

- 作業は、指定された worktree とブランチの中だけで行う。ほかのディレクトリは触らない。
  例外は、指定された plan の保存先に plan を書くことだけである。
- コミットまでは行うが、push はしない。
- 状態が変わったら、必ず `csa report` で報告する。報告は CSA に向けて書き、人間が直接読む前提にしない。
- CSA から追加の指示が来たら、それに従って作業を続ける。
- 人間がこのペインで直接指示や回答をすることもある。CSA からの指示と同じように従う。
  CSA は直接のやり取りの中身を知らないので、それによって状態や方針が変わったら `csa report` で記録する（例: 人間が plan を承認した、範囲を変えた、blocked が解消した）。

## 進め方

### 1. 見積もり

実装を始める前に、brief と関連するコードを読み、次の基準に当てはまるかを判定する。
どれか 1 つに当てはまれば、plan が必須になる。

- 変更するファイルが 4 つ以上になる見込みである。
- 変更が複数のパッケージやモジュールにまたがる。
- 公開 API、DB スキーマ、設定ファイルの形式のいずれかが変わる。
- 要件が曖昧で、設計の選択肢が複数ある。

brief に「規模にかかわらず plan を作る」と書かれていれば、基準にかかわらず plan を作る。

### 2. plan が不要な場合

判定と理由を記録してから、そのまま実装に進む。

```bash
csa report <ISSUE> working "見積もり: plan 不要。<理由>"
```

`working` の報告は CSA には送られず、タスクファイルにだけ残る。

### 3. plan が必要な場合

指定された保存先に plan を書く。
雛形は [plan の雛形](references/plan-template.md) にある。
書き終えたら次を実行し、実装には進まずに止まる。

```bash
csa report <ISSUE> plan "<plan の要約と、該当した基準>"
```

CSA から修正の指示が来たら、plan を直して、もう一度 `plan` で報告する。
plan が承認されると、CSA から「plan が承認された」という指示が届く。それを受けてから実装を始める。
人間がこのペインで直接 plan を承認した場合は、`csa report <ISSUE> working "plan 承認（人間が直接）: <承認の発言>"` で記録してから実装を始める。

### 4. 実装と報告

実装し、受け入れ条件のテストを通してからコミットする。
その後、状況に応じて次のどちらかで報告する。

- **判断に迷う、情報が足りない**：`csa report <ISSUE> blocked "<具体的な質問>"` を実行して待つ。
- **実装とテストが済んだ**：`csa report <ISSUE> review "<変更の要約 / テスト結果 / ブランチ名>"` を実行する。

`csa` が PATH にない場合は、この skill の隣にある csa skill の `scripts/csa` を絶対パスで呼ぶ。
