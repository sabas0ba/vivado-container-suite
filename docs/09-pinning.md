# 09 ピン留め

方針: **バージョン番号ではなく内容ハッシュで固定する。** タグもブランチも
スナップショットのないミラーも、後から中身が変わりうる。

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
scripts/verify-pinning.sh     # すべて固定されているか検査 (CI と vvd doctor が実行)
```

## apt スナップショットが要点

トップレベルのパッケージバージョンだけを固定しても、**推移的な依存は固定されない**。
`libx11-6=2:1.8.7-1build1` を指定しても、それが引く `libxcb1` のバージョンは
その時のアーカイブ次第になる。

そこで <https://snapshot.ubuntu.com> を使う。ある時刻の `archive.ubuntu.com` を
バイト単位で再現する不変ビューで、これを固定すると**依存の全閉包が固定される**。

```
# docker/apt-snapshot.lock
APT_SNAPSHOT=20260801T000000Z
```

`docker/packages.lock` のバージョンは、その上での二重の固定であり、
スナップショットを更新したときに何が変わったかを**レビュー可能な差分**として
見せるためにある。

各 `.deb` の完全性は apt 自身が担保する: 署名された `InRelease` → `Packages` →
各パッケージの SHA256、という連鎖が検証される。`packages.lock` に記録している
sha256 は監査用。

### 唯一の例外: CA ブートストラップ

`snapshot.ubuntu.com` は HTTPS 専用で、`ubuntu:24.04` はルート証明書を持たない。
最初の TLS 接続を張るための証明書束だけは、ピン留め前のアーカイブから取得する
`ca-bootstrap` ステージで作る。この束は `/opt/vvd/pin/ca-bootstrap.crt` に置かれ、
**それを使った同じレイヤ内で削除される**。最終イメージに残るものは何もない。

パッケージの完全性はこれに依存しない。apt の GPG 連鎖はバイト列の届き方と無関係に
検証されるので、この証明書は転送路の話でしかない。
`scripts/verify-pinning.sh` はこの 1 箇所だけを例外として許可し、
それ以外の `apt-get install` と、ブートストラップ束の削除漏れを検出する。

### 更新する

```sh
scripts/lock-apt.sh                            # 現在のスナップショットで再解決
scripts/lock-apt.sh --snapshot 20260901T000000Z  # スナップショットを進める
scripts/lock-apt.sh --check                    # 古くなっていれば失敗
```

パッケージを増やすときは `docker/packages.list` に名前だけ足して再ロックする。
`packages.list` にあって `packages.lock` に無いパッケージは
`verify-pinning.sh` が検出する。

## イメージダイジェスト

```sh
scripts/lock-images.sh            # config/images.list のタグをダイジェストに解決
scripts/lock-images.sh --check    # ドリフト検査
```

`docker/Dockerfile` の `ARG BASE_IMAGE` の既定値と `config/images.lock` の
`base` エントリが一致しているかも検査される。素の `docker build` と
`vvd build` が別のベースを使う、という事故を防ぐため。

## Vivado インストーラ

AMD はインストーラをログイン必須で配布しており、本リポジトリは
**一切ダウンロードしない**。利用者が取得し、SHA256 を記録する。

```sh
sha256sum FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1030_1755.tar
```

```
# config/vivado-versions.lock
2025.2|FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1030_1755.tar|<sha256>
```

照合は 2 か所で行う。`vvd build` がホスト側で (ビルドを始める前に)、
`docker/install-vivado.sh` がイメージ内で。`vvd` 以外から `docker build` を
叩いた場合でも、未検証のインストーラは通らない。

## 開発ツール

`scripts/fetch-tools.sh` が `scripts/tools.lock` に従って `.tools/` に取得する。
ダウンロードは sha256 で、git チェックアウトは commit ID で検証する。
**ネットワークからシェルへ直接パイプするコードはリポジトリ内に存在しない**
(これも `verify-pinning.sh` が検査している)。

git の commit ID は内容アドレスなので、リリース tarball より強い固定になる
(tarball のバイト列はフォージ側で再生成されうる)。

## GitHub Actions

`uses:` はすべて 40 桁の commit SHA。バージョンは行末コメントで残す。

```yaml
- uses: actions/checkout@df4cb1c069e1874edd31b4311f1884172cec0e10 # v6.0.3
```

`verify-pinning.sh` が `.github/workflows/` 全体を走査し、SHA でない参照が
あれば失敗させる。

## 固定していないもの

- **Vivado 本体の中身** — AMD の配布物であり、インストーラの SHA256 で
  固定できる範囲まで
- **ホスト側の Vivado インストール** (`mount` モード) — 定義上ホストの持ち物。
  完全に固定したければ `image` モードを使う
- **ランナーのベース OS** — GitHub Actions の `ubuntu-24.04` イメージ。
  コンテナの中身には影響しない
- **CA ブートストラップ束** — 上記のとおり、最終イメージに残らない転送路の材料

## 検査を回す

```sh
scripts/verify-pinning.sh     # 固定されているか
make lock-check               # ロックファイルが最新か
vvd doctor                    # 上記を含む環境全体
```
