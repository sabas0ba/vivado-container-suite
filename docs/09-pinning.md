# 09 ピン留め

方針は、バージョン番号ではなく内容ハッシュで固定することである。タグ、ブランチ、
スナップショットを持たないミラーは、いずれも後から内容が変化しうる。

## 対象

| 対象 | 固定方法 | ロックファイル |
|---|---|---|
| ベースイメージ | レジストリダイジェスト | `config/images.lock` |
| apt パッケージ | Ubuntu アーカイブスナップショット + 明示バージョン | `docker/apt-snapshot.lock`, `docker/packages.lock` |
| Vivado インストーラ | SHA256 | `config/vivado-versions.lock` |
| 開発ツール (shellcheck, hadolint) | SHA256 | `scripts/tools.lock` |
| bats とヘルパ | git commit ID | `scripts/tools.lock` |
| GitHub Actions | commit SHA | `.github/workflows/*.yml` |

```sh
scripts/verify-pinning.sh     # 固定状況を検査する (CI と vvd doctor が実行する)
```

## apt スナップショットによる固定

トップレベルのパッケージバージョンのみを固定しても、推移的な依存は固定されない。
`libx11-6=2:1.8.7-1build1` を指定しても、それが依存する `libxcb1` のバージョンは
その時点のアーカイブの内容に依存する。

そのため <https://snapshot.ubuntu.com> を使用する。これはある時刻の
`archive.ubuntu.com` をバイト単位で再現する不変のビューであり、これを固定すると
依存の全閉包が固定される。

```
# docker/apt-snapshot.lock
APT_SNAPSHOT=20260801T000000Z
```

`docker/packages.lock` に記録したバージョンは、その上に重ねた二重の固定である。
スナップショットを更新した際の変更内容を、レビュー可能な差分として提示することを
目的とする。

各 `.deb` の完全性は apt 自身が担保する。署名された `InRelease` → `Packages` →
各パッケージの SHA256 という連鎖が検証される。`packages.lock` に記録した sha256 は
監査用である。

### 唯一の例外: CA ブートストラップ

`snapshot.ubuntu.com` は HTTPS 専用であり、`ubuntu:24.04` はルート証明書を持たない。
最初の TLS 接続に必要な証明書束のみを、ピン留め前のアーカイブから取得する
`ca-bootstrap` ステージで生成する。この束は `/opt/vvd/pin/ca-bootstrap.crt` に配置し、
使用した同一レイヤ内で削除する。最終イメージには何も残らない。

パッケージの完全性はこの証明書に依存しない。apt の GPG 連鎖はバイト列の取得経路と
無関係に検証されるため、この証明書は転送路に関わるものにとどまる。
`scripts/verify-pinning.sh` はこの 1 箇所のみを例外として許可し、それ以外の
`apt-get install` と、ブートストラップ束の削除漏れを検出する。

### 更新する

```sh
scripts/lock-apt.sh                            # 現在のスナップショットで再解決
scripts/lock-apt.sh --snapshot 20260901T000000Z  # スナップショットを進める
scripts/lock-apt.sh --check                    # 古くなっていれば失敗
```

パッケージを追加する場合は、`docker/packages.list` に名前を追記して再ロックする。
`packages.list` に存在して `packages.lock` に存在しないパッケージは
`verify-pinning.sh` が検出する。

## イメージダイジェスト

```sh
scripts/lock-images.sh            # config/images.list のタグをダイジェストに解決
scripts/lock-images.sh --check    # ドリフト検査
```

`docker/Dockerfile` の `ARG BASE_IMAGE` の既定値と `config/images.lock` の `base`
エントリが一致するかも検査する。`docker build` を直接実行した場合と `vvd build` を
実行した場合とで、異なるベースイメージが使用されることを防ぐためである。

## Vivado インストーラ

AMD はインストーラをログイン必須で配布しており、本リポジトリはこれを一切
ダウンロードしない。利用者が自身で取得し、SHA256 を記録する。

```sh
sha256sum FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1030_1755.tar
```

```
# config/vivado-versions.lock
2025.2|FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1030_1755.tar|<sha256>
```

照合は 2 か所で行う。ビルド開始前にホスト側で `vvd build` が、イメージ内で
`docker/install-vivado.sh` が、それぞれ照合する。`vvd` を経由せず `docker build` を
直接実行した場合でも、未検証のインストーラは使用できない。

## 開発ツール

`scripts/fetch-tools.sh` が `scripts/tools.lock` に従って `.tools/` へ取得する。
ダウンロードしたファイルは sha256 で、git チェックアウトは commit ID で検証する。
ネットワークから取得した内容をシェルへ直接パイプするコードは、リポジトリ内に存在
しない。これも `verify-pinning.sh` が検査する。

git の commit ID は内容アドレスであるため、リリース tarball より強固な固定となる。
tarball のバイト列はフォージ側で再生成されうる。

## GitHub Actions

`uses:` はすべて 40 桁の commit SHA。バージョンは行末コメントで残す。

```yaml
- uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6.0.3
```

`verify-pinning.sh` が `.github/workflows/` 全体を走査し、SHA でない参照が存在する
場合は失敗させる。

## 固定していないもの

- **Vivado 本体の内容** — AMD の配布物であり、固定できるのはインストーラの SHA256
  までである
- **ホスト側の Vivado インストール** (`mount` モード) — 定義上ホストに属する。
  完全に固定する場合は `image` モードを使用する
- **ランナーのベース OS** — GitHub Actions の `ubuntu-24.04` イメージ。コンテナの
  内容には影響しない
- **CA ブートストラップ束** — 前述のとおり、最終イメージに残らない転送路の構成要素
  である

## 検査を回す

```sh
scripts/verify-pinning.sh     # 固定状況を検査する
make lock-check               # ロックファイルが最新かを検査する
vvd doctor                    # 上記を含む環境全体を検査する
```
