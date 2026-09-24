# vm-apple-container-dev

Apple `container machine` 上で動かす、OCI イメージベースの小さな永続 Linux 開発 VM です。

このリポジトリでは `container machine` を一時的なアプリケーションコンテナではなく、軽量 VM として扱います。

## セキュリティのデフォルト

- macOS のホームディレクトリ共有は `--home-mount none` で無効化します。
- SSH は公開鍵認証のみ許可します。
- SSH のパスワード認証と keyboard-interactive 認証は無効化します。
- root の SSH ログインは無効化します。
- Mac 側の SSH 秘密鍵を VM にコピーしません。
- 初回ビルド時に `~/.ssh/id_*.pub` と `pubkeys/*.pub` を `/etc/skel/.ssh/authorized_keys` としてイメージへ組み込みます。秘密鍵は含めません。
- SSH host private key は OCI イメージへ組み込まず、machine の初回起動時に machine ごとに生成します。
- guest filesystem は永続化されます。そのため Codex などのツールで作成した credential は、machine を削除するまで VM 内に保持できます。

`container machine rm` を実行すると、この永続 machine state も削除されます。

## 必要なもの

- Apple `container` をサポートする Apple silicon Mac
- インストールおよび初期化済みの Apple `container`
- ローカルの `container` 環境で必要な場合は Rosetta 2
- `~/.ssh/id_*.pub` または `pubkeys/*.pub` に公開鍵が合計1つ以上

スクリプトは `--home-mount none` とローカル DNS service を含む、現在の Apple `container machine` CLI を前提としています。

## クイックスタート

```sh
git clone https://github.com/r-agatsuma/vm-apple-container-dev.git
cd vm-apple-container-dev

./scripts/init
./scripts/ssh
```

初回の `./scripts/init` は次を行います。

1. 必要であれば Apple `container` service を起動します。
2. 必要であればローカルの `.machine` DNS domain を作成します。この処理では `sudo` を使用します。
3. `~/.ssh/id_*.pub` と `pubkeys/*.pub` の空でない行を重複排除して一時的な build input にまとめ、`/etc/skel/.ssh/authorized_keys` としてイメージへ組み込みます。Apple container machine は初回起動時に `/etc/skel` を新しい Linux user の home へコピーします。
4. Dockerfile から `local/devvm:latest` をビルドします。
5. `devvm` という名前で、2 CPU / 2 GiB RAM、host home sharing 無効の永続 machine を作成します。
6. `sshd` が起動しており、公開鍵認証のみの設定になっていることを確認します。

`init` は初期構築専用です。同名の machine が存在するとビルドや置換をせず失敗し、`./scripts/up` を案内します。

通常の起動には `./scripts/up` を使います。既存 machine の `homeMount=none` を検証して起動し、SSH を確認します。ビルドや machine 作成は行いません。machine が存在しない場合は失敗し、`./scripts/init` を案内します。

Dockerfile または公開鍵を変更した場合は、明示的に再構築してください。既存 machine への鍵の同期や自動再構築は行いません。この操作では machine 内に保存された state が破棄されます。

```sh
./scripts/destroy
./scripts/init
```

公開鍵は `~/.ssh/id_*.pub` とリポジトリ内の `pubkeys/*.pub` の両方から収集します。片方は空でも構いませんが、合計1つ以上の空でない公開鍵が必要です。`pubkeys/` は公開鍵専用です。秘密鍵を置かないでください。`.gitkeep` など `.pub` 以外のファイルは読み込みません。一時 build input `.authorized_keys` はビルド後（失敗時も）に削除します。

起動後は次のコマンドで接続できます。

```sh
ssh "$USER@devvm.machine"
```

または、単に次を実行します。

```sh
./scripts/ssh
```

`init` と `up` は SSH コマンドと次のような OpenSSH config を表示します。

```sshconfig
Host devvm.machine
    HostName devvm.machine
    User <macOS user name>
```

表示は `DEVVM_NAME`、`DEVVM_DNS_DOMAIN`、`DEVVM_SSH_USER` を反映します。必要なら手動で `~/.ssh/config` に追加してください。スクリプトはこのファイルを変更せず、使用する秘密鍵を決められないため `IdentityFile` も出力しません。

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
- iro (`github.com/r-agatsuma/iro/cmd/iro@latest`)
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

- `iro-builder`: Go で最新版の iro をビルドします。実行ファイルだけを `/usr/local/bin/iro` にコピーし、`iro version` で動作確認します。Go toolchain は最終イメージに持ち込みません。
- `devvm-base`: systemd、SSH、Codex CLI、iro、共通の開発ツールを含む共通ベースです。通常はここを変更する必要はありません。
- `dev`: 実際に build される最終 stage です。Python、Go、Rust、DB client、プロジェクト固有 CLI など、必要な開発ツールはこの stage に追加してください。

Dockerfile の末尾にある `FROM devvm-base AS dev` 以降を自由に編集できます。例えば Python を追加する場合:

```dockerfile
FROM devvm-base AS dev

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 python3-venv \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

Dockerfile を変更した場合は、既存 machine を `./scripts/destroy` で削除してから `./scripts/init` で作り直してください。

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
./scripts/init
```

`DEVVM_IMAGE`、`DEVVM_CPUS`、`DEVVM_MEMORY` は `init` での構築時に使用します。以降の操作でも同じ `DEVVM_NAME` と接続設定を指定してください。`up` は既存 machine のリソース設定を変更しません。

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
