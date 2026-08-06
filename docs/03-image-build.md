# 03 イメージ構築

## モード

| | `mount` (既定) | `image` |
|---|---|---|
| Vivado の所在 | ホスト。read-only bind mount | イメージ内 |
| イメージサイズ | 約 1.5 GB | 30〜100 GB 超 |
| ビルド時間 | 2〜5 分 | 1〜3 時間 |
| インストーラ | 不要 | 必要 (AMD からログインして取得) |
| 適する用途 | 開発機、Vivado が導入済みの CI | 自己完結させたい配布・再現環境 |

3 つめのモード `none` は、このコンテナに Vivado が存在しないことを明示する。
`mount` と同じイメージを使用し、Vivado のマウントも存在確認も行わない。Vivado が
導入されていない CI ランナーでコンテナ自体を検証するためのモードである
([08 CI](08-ci.md))。

バージョンの切り替えは、いずれのモードでも `--vivado` / `VVD_VIVADO_VERSION` で
行う。`mount` モードでは、指定したバージョンがホストに存在しない場合、コンテナの
起動前にエラーとなり、存在するバージョンの一覧が表示される。

## mount モード

```sh
vvd build
```

`docker/Dockerfile` の `base` ステージのみを構築する。内容は次のとおり。

- ダイジェスト固定された `ubuntu:24.04`
- Ubuntu アーカイブスナップショットから、`docker/packages.lock` に列挙された
  90 パッケージ (Qt/XCB、GL/EGL、NSS、fontconfig、libusb、tclsh ほか)
- `libtinfo.so.5` 等への互換シンボリックリンク (Vivado の Tcl が要求するため)
- 権限降格を行う entrypoint
- ロケール、`/work`、`/opt/Xilinx` マウントポイント

実行時に `$VVD_XILINX_ROOT` が `/opt/Xilinx` に read-only で mount され、
entrypoint が `settings64.sh` を読み込む。

## image モード

インストーラは AMD のサイトからログインして各自で取得する。本リポジトリは
インストーラを一切ダウンロードしない。取得後、SHA256 を記録する。

```sh
sha256sum FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1030_1755.tar
```

`config/vivado-versions.lock` に 1 行追加する。

```
2025.2|FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1030_1755.tar|<sha256>
```

その上でビルドする。

```sh
vvd build --installer ~/Downloads/FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1030_1755.tar
```

`vvd build` はビルド開始前にホスト側で SHA256 を照合し、
`docker/install-vivado.sh` がイメージ内で再度照合する。記録が存在しない、または
一致しないインストーラではビルドが開始されない。

インストーラ本体は名前付きビルドコンテキスト (`--build-context installer=...`)
としてマウントされるため、数十 GB のファイルがビルドコンテキストとしてコピーされる
ことはない。BuildKit が必要である (docker 23 以降 / podman 4.4 以降)。

構築後は Vivado がイメージに含まれるため、次のように指定する。

```conf
VVD_VIVADO_MODE=image
```

### インストールされる構成

`xsetup -b ConfigGen` で生成した設定を使用し、Documentation Navigator、
デスクトップ統合、ショートカットを無効化する。デバイスファミリを限定する場合は、
生成された `install_config.txt` の `Modules=` 行を編集する
(`docker/install-vivado.sh` 内)。

## TLS 検査プロキシ配下でのビルド

`snapshot.ubuntu.com` は HTTPS 専用で、`ubuntu:24.04` はルート証明書を持たない。
そのため Dockerfile には `ca-bootstrap` ステージがあり、最初の TLS 接続に使用する
証明書束のみをここで生成して `/opt/vvd/pin/ca-bootstrap.crt` に配置し、それを使用した
同一レイヤ内で削除する。標準の証明書ディレクトリには変更を加えず、最終イメージの
信頼ストアはピン留めされた `ca-certificates` パッケージのみが構成する。

パッケージの完全性がこの証明書に依存することはない。apt は署名済みの
`InRelease` → `Packages` → 各 `.deb` の SHA256 という連鎖を、バイト列の取得経路とは
無関係に検証する。

TLS を検査するプロキシの内側でビルドする場合は、その CA を指定する。

```sh
vvd build --ca-cert /etc/ssl/certs/corporate-proxy.crt
```

この証明書もビルド中のみ信頼され、イメージの実行時信頼ストアには含まれない。

## `vvd build` のオプション

```
--installer TARBALL  image モードでビルド (上記)
--ca-cert FILE       ビルド中だけ信頼する追加 CA 証明書
--tag REF            出力イメージ参照
--no-cache           レイヤキャッシュを無視
--progress MODE      auto | plain | tty
```

## 事前ビルド済みイメージの取得

```sh
vvd pull                                  # config/images.lock の prebuilt を取得
vvd pull registry.example.com/vvd@sha256:...
```

ダイジェストで固定されていない参照は拒否される。可変なタグを取得すると
ロックファイルによる固定が無意味になるためである。

## イメージに入らないもの

- ライセンスファイル。`.lic` を含むイメージはビルド時に失敗する
  (`docker/Dockerfile` の最終チェック)。CI でも改めて検査する
- プロジェクトのソース。実行時に `/work` へ mount される
- `tcl/` と `container/` のスクリプト。実行時に read-only で mount されるため、
  イメージを再構築せずに編集およびデバッグできる

## 再現性

同一の commit からビルドすれば、同一のベースイメージ、apt スナップショット、
パッケージバージョンが使用される。固定の対象と方法は
[09 ピン留め](09-pinning.md) に記載する。

```sh
scripts/verify-pinning.sh     # すべて固定されているか検査
make lock-check               # ロックファイルが最新か検査
```
