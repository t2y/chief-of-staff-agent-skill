# このリポジトリを開発するエージェントへ

このリポジトリは、herdr 上で CSA（Chief of Staff Agent）と Worker を動かすキットを、Agent Skills の形式の skill として配布する。
利用者向けの説明は `README.md` にある。
このファイルには、開発と保守で守る決まりを書く。

## 構成

| パス | 中身 |
|---|---|
| `skills/csa/` | 配布物。CLI（`scripts/csa`）、CSA の手順（`SKILL.md`）、CSA の作業ディレクトリに置くテンプレート（`assets/`） |
| `skills/csa-worker/` | 配布物。Worker の手順（`SKILL.md`）と plan の雛形（`references/`） |
| `test/` | bats のテストと、テスト用の偽の herdr と claude（`fake-bin/`） |
| `mise.toml` | 開発用のツール（shellcheck、bats）とタスク |
| `docs/diagrams/` | archify で作った構成図。元データ（`*.archify.json`）、HTML、README 用のプレビュー画像（`*.png`） |

`npx skills` が利用者に配るのは `skills/<name>/` の中身だけである。
このファイルや `test/` は利用者には届かない。

`skills/csa/assets/AGENTS.md` は CSA に渡すテンプレートであり、このファイルとは別物である。
`csa init` と `csa up` が、利用者の `CSA_HOME` にコピーして上書きする。

## 確認方法

変更したら、次の 2 つを通してからコミットする。

```bash
mise run lint   # shellcheck
mise run test   # bats
```

CI では同じ 2 つを Linux と macOS で実行する。
手元の clone をそのまま入れて試すときは、一時ディレクトリを HOME にして `npx skills add <clone のパス> -g -a claude-code codex --skill '*' -y` を実行する。
実際の HOME で試すと、利用者として入れている skill を上書きしてしまう。

## skill の決まり

- frontmatter には、Agent Skills の仕様にあるキー（`name`、`description`、`license`、`compatibility`、`metadata`、`allowed-tools`）だけを書く。
  Claude Code 独自のキー（`disable-model-invocation` など）を使うと、ほかのエージェントで無視されるか、パッケージ化のときにエラーになる。
- `name` はディレクトリ名と一致させ、`description` は 1024 文字以内にする。
- 2 つの skill の `metadata.version` は同じ値にそろえる。
- csa-worker は利用者単位で入るので、`description` は「csa の Worker として指名されたときだけ使う」という狭い条件のまま保つ。
  条件を広げると、普段の作業でモデルが勝手に読み込むおそれがある。

これらはテストの最後の項目で確かめている。

## リリース

バージョンを上げるときは、2 つの `SKILL.md` の `metadata.version`、`CHANGELOG.md`、git のタグ（`vX.Y.Z`）を一緒に更新する。
利用者の `csa up` と `csa doctor` は、`main` にある `skills/csa/SKILL.md` の `metadata.version` を見て新しいバージョンを知らせる。
そのため、`main` に入れた時点で利用者に通知が出る。

## herdr への依存

csa は herdr CLI が返す JSON の形に依存している。
使っているのは、`workspace create` と `tab create` の ID、`agent get` の `.result.agent.agent_status`、`agent get` の終了コード（存在しなければ 1）である。

herdr の新しいバージョンに対応するときは、次の順に進める。

1. `herdr api schema --json` で、上の形が変わっていないかを確かめる。
2. 変わっていれば、`scripts/csa` と偽の herdr（`test/fake-bin/herdr`）の出力を合わせて直す。
3. `scripts/csa` の `HERDR_TESTED_VERSION` と、`README.md` に書いた確認済みのバージョンを更新する。

偽の herdr の出力は、本物の形に合わせておく。
形がずれると、テストが通っても本物の herdr では動かない。

## 移植性

対象は Linux と macOS 12.3 以降である。
macOS の `/usr/bin/env bash` は bash 3.2 なので、`scripts/csa` は bash 3.2 で動く書き方にする。

- `mapfile`、`readarray`、連想配列、`${var,,}` は使わない。
- `sed -i` と `sort -V` は使わない（GNU と BSD で挙動が違う）。バージョンの比較は `version_gt` を使う。
- `set -u` のもとで空の配列を `"${arr[@]}"` で展開すると、bash 3.2 ではエラーになる。要素数を確かめてから展開する。

## 構成図

`docs/diagrams/*.archify.json` は、各要素の根拠として `skills/` の行番号を引用し、`meta.repository.revision` でコミットを固定している。
引用しているファイル（`scripts/csa`、2 つの `SKILL.md`、`assets/AGENTS.md`）を変えて構成や行がずれたら、次の手順で図を作り直す。

1. 変更をコミットし、`meta.repository.revision` をそのコミットに、`sources` の行番号を新しい位置に合わせる。
2. archify skill の `finalize` で HTML を作り直す。

   ```bash
   node <archify skill のディレクトリ>/bin/archify.mjs finalize architecture docs/diagrams/architecture.archify.json docs/diagrams/architecture.html --repo-root . --quality showcase --out-dir <一時ディレクトリ>
   node <archify skill のディレクトリ>/bin/archify.mjs finalize workflow docs/diagrams/task-workflow.archify.json docs/diagrams/task-workflow.html --repo-root . --quality showcase --out-dir <一時ディレクトリ>
   ```

3. `visual-check` の 2048x1320 の light のスクリーンショットから図の部分を切り出し、`*.png` を差し替える。

`*.delivery.json` は手元の絶対パスを含む受領記録なので、コミットしない（`.gitignore` で除外している）。

## 文章

skill の本文、テンプレート、README は日本語で書く。
CSA と Worker は skill の本文をそのまま指示として読むので、手順は曖昧さが残らないように具体的に書く。
