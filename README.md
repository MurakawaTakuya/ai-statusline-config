# AI Statusline Config

Codex CLI と Claude Code の下部バー設定だけを同期するための個人用リポジトリです。

認証情報、APIキー、セッション履歴、その他の Codex / Claude 設定は含みません。

## 保存しているもの

### Claude Code

- `claude/statusline.sh`: メインの3行ステータスライン
- `claude/subagent-statusline.sh`: サブエージェント行
- `claude/settings-snippet.json`: `settings.json` に追加する2項目だけ

メイン表示は概ね次の構成です。

```text
Sonnet 5 (medium) FAST | 5h █████████░ 99% left 4h16m | week ...
Context ░░░░░░░░░░ 5% used · 52.8k/1M | cache 61% warm · 46m left
~/Documents/programming/LangTalk | main | wt:feature-x | clean
```

値が提供されない項目は自動的に省略されます。

### Codex CLI

- `codex/statusline-snippet.toml`: `~/.codex/config.toml` の `[tui]` 下部バー設定だけ

Codex は任意スクリプトではなく、定義済みの項目を指定順に表示します。

## 必要なもの

- macOS
- `git`
- `gh`
- `python3`
- `jq`（Claude Code のステータスラインで使用）
- Codex CLI / Claude Code

Homebrew を使う場合、`jq` は次のコマンドで導入できます。

```bash
brew install jq
```

## 新しいPCへのインストール

最初に GitHub CLI へログインします。

```bash
gh auth login
```

リポジトリをクローンして、インストーラーを実行します。

```bash
mkdir -p ~/Documents/programming
cd ~/Documents/programming
gh repo clone MurakawaTakuya/ai-statusline-config
cd ai-statusline-config
./install.sh all
```

インストール後、Codex CLI と Claude Code を再起動してください。

## 個別にインストールする

Claude Code だけ：

```bash
./install.sh claude
```

Codex CLI だけ：

```bash
./install.sh codex
```

両方：

```bash
./install.sh all
```

## インストーラーの動作

`install.sh` は設定ファイル全体を置き換えません。

- Claude Codeでは、`statusLine` と `subagentStatusLine` の2項目だけを `~/.claude/settings.json` へマージします。
- Codexでは、`status_line` と `status_line_use_colors` の2項目だけを `~/.codex/config.toml` の `[tui]` セクションへマージします。
- 変更対象が既に存在する場合は、同じディレクトリに日時付きバックアップを作ります。

バックアップ例：

```text
~/.claude/settings.json.bak.20260830-120000
~/.codex/config.toml.bak.20260830-120000
```

## 別のホームディレクトリで試す

実際の設定を変更せず試したい場合は、`STATUSLINE_TARGET_HOME` を指定できます。

```bash
STATUSLINE_TARGET_HOME=/tmp/statusline-test-home ./install.sh all
```

## 設定を更新する

Claude Code の表示ロジックを変更する場合は、次のファイルを編集します。

```text
claude/statusline.sh
claude/subagent-statusline.sh
```

Codexの表示順を変更する場合は、次のファイルを編集します。

```text
codex/statusline-snippet.toml
```

変更後は構文確認を行い、コミットしてpushします。

```bash
bash -n claude/statusline.sh
bash -n claude/subagent-statusline.sh
python3 -c 'import json; json.load(open("claude/settings-snippet.json"))'
python3 -c 'import tomllib; tomllib.load(open("codex/statusline-snippet.toml", "rb"))'
git add .
git commit -m "Update statusline config"
git push
```

## セキュリティ

次のものはこのリポジトリに追加しないでください。

- `~/.codex/auth.json`
- Claude Code / Codex の認証トークン
- APIキー
- `.env` ファイル
- セッション履歴やログ
- `settings.json` や `config.toml` の無関係な全設定

このリポジトリはprivateですが、秘密情報を保存しない方針です。
