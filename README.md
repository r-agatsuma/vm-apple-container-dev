# apple-devvm

Apple `container machine` 上で動かす、OCI イメージベースの小さな永続 Linux 開発 VM です。

このリポジトリでは `container machine` を一時的なアプリケーションコンテナではなく、軽量 VM として扱います。

## セキュリティのデフォルト

- macOS のホームディレクトリ共有は `--home-mount none` で無効化します。
- SSH は公開鍵認証のみ許可します。
- SSH のパスワード認証と keyboard-interactive 認証は無効化します。
- root の SSH ログインは無効化します。
- Mac 側の SSH 秘密鍵を VM にコピーしません。
- 初回ビルド時に `~/.ssh/id_*.pub` を `/etc/skel/.ssh/authorized_keys` としてイメージへ組み込みます。秘密鍵は含めません。
- SSH host private key は OCI イメージへ組み込まず、machine の初回起動時に machine ごとに生成します。
- guest filesystem は永続化されます。そのため Codex などのツールで作成した credential は、machine を削除するまで VM 内に保持できます。

`container machine rm` を実行すると、この永続 machine state も削除されます。

## 必要なもの

- Apple `container` をサポートする Apple silicon Mac
- インストールおよび初期化済みの Apple `container`
- ローカルの `container` 環境で必要な場合は Rosetta 2
- `~/.ssh/id_*.pub` に一致する公開鍵が1つ以上

スクリプトは `--home-mount none` とローカル DNS service を含む、現在の Apple `container machine` CLI を前提としています。

## クイックスタート

```sh
git clone https://github.com/r-agatsuma/apple-devvm.git
cd apple-devvm

./scripts/up
./scripts/ssh
```

初回の `./scripts/up` は次を行います。

1. 必要であれば Apple `container` service を起動します。
2. 必要であればローカルの `.machine` DNS domain を作成します。この処理では `sudo` を使用します。
3. `~/.ssh/id_*.pub` を一時的な build input にまとめ、`/etc/skel/.ssh/authorized_keys` としてイメージへ組み込みます。Apple container machine は初回起動時に `/etc/skel` を新しい Linux user の home へコピーします。
4. Dockerfile から `local/devvm:latest` をビルドします。
5. `devvm` という名前で、2 CPU / 2 GiB RAM、host home sharing 無効の永続 machine を作成します。
6. `sshd` が起動しており、公開鍵認証のみの設定になっていることを確認します。

2回目以降の `./scripts/up` は既存の永続 machine を再利用し、root filesystem の再ビルドや置換は行いません。Dockerfile または使用する公開鍵を変更した場合は、`./scripts/destroy` のあとに `./scripts/up` を実行して machine を作り直してください。この操作では machine 内に保存された state が破棄されます。

デフォルトの公開鍵選択は意図的に単純で、`~/.ssh/id_*.pub` を使用します。別の公開鍵を使いたい場合は、`scripts/up` 内のこの glob を変更してください。

起動後は次のコマンドで接続できます。

```sh
ssh "$USER@devvm.machine"
```

または、単に次を実行します。

```sh
./scripts/ssh
```

## 初回の開発開始

この VM ではソースコードを macOS から mount せず、VM 内に clone または作成する運用を基本とします。

既存の GitHub repository で作業する場合は、初回に VM 内で GitHub CLI へログインしてから clone してください。

```sh
gh auth login

mkdir -p ~/src
cd ~/src
gh repo clone owner/repository
cd repository

codex
```

`gh auth login` の認証情報は persistent machine filesystem に保存されるため、通常は machine ごとに一度実行すれば十分です。

まだ repository がなく、新しいプロジェクトをゼロから始める場合も `~/src` を作業場所にします。`~/src` で Codex を起動し、最初の指示で「新規プロジェクトであること」「プロジェクト名のディレクトリを作成し、その中で実装を開始すること」を明示してください。GitHub に公開・push する予定がある場合は、あらかじめ `gh auth login` も実行しておきます。

```sh
mkdir -p ~/src
cd ~/src
codex
```

例えば Codex には、次のように依頼します。

```text
新規プロジェクトとして <project-name> ディレクトリを作成し、その中を作業ディレクトリとして開発を開始してください。必要であれば Git repository も初期化してください。
```

## 開発ツール

ベースイメージには Codex CLI を利用するための共通ツールを含めています。

- Node.js 22 / npm
- Codex CLI (`@openai/codex`)
- Git / Git LFS / GitHub CLI (`gh`)
- `jq`, `ripgrep`, `fd`, `fzf`
- `build-essential`, `bubblewrap`
- `curl`, `wget`, `less`, `unzip`, `zip`

Codex CLI は image build 時に npm から最新版をグローバルインストールします。初回は VM 内で `codex` を起動してログインしてください。ログイン情報は persistent machine filesystem に保持されます。

```sh
./scripts/ssh
codex
```

## 開発環境のカスタマイズ

Dockerfile は multi-stage 構成です。

- `devvm-base`: systemd、SSH、Codex CLI、共通の開発ツールを含む共通ベースです。通常はここを変更する必要はありません。
- `dev`: 実際に build される最終 stage です。Python、Go、Rust、DB client、プロジェクト固有 CLI など、必要な開発ツールはこの stage に追加してください。

Dockerfile の末尾にある `FROM devvm-base AS dev` 以降を自由に編集できます。例えば Python を追加する場合:

```dockerfile
FROM devvm-base AS dev

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

Dockerfile を変更した場合は、既存 machine を `./scripts/destroy` で削除してから `./scripts/up` で作り直してください。

## ライフサイクル

```sh
./scripts/status
./scripts/stop
./scripts/up
./scripts/destroy
```

`stop` は VM filesystem を保持したまま machine を停止します。`destroy` は確認後に machine とその永続 state を削除します。OCI image と共有の `.machine` DNS domain は削除しません。

## 設定

少数の machine 設定は環境変数で上書きできます。

```sh
DEVVM_NAME=mydev \
DEVVM_CPUS=4 \
DEVVM_MEMORY=4G \
./scripts/up
```

利用可能な環境変数:

- `DEVVM_NAME` — デフォルト: `devvm`
- `DEVVM_IMAGE` — デフォルト: `local/devvm:latest`
- `DEVVM_CPUS` — デフォルト: `2`
- `DEVVM_MEMORY` — デフォルト: `2G`
- `DEVVM_DNS_DOMAIN` — デフォルト: `machine`
- `DEVVM_SSH_USER` — デフォルト: 現在の macOS user name

同名の machine がすでに存在する場合、`container machine inspect` が `homeMount: none` を返さなければ `./scripts/up` は処理を拒否します。

## State の分離

OCI image には、packages、systemd、OpenSSH 設定、共通ツールなど、再現可能な開発環境の state を含めます。

machine filesystem には、clone した repository、shell history、cache、tool login など、user 固有の永続 state を保持します。

macOS の home directory は machine に mount しません。
