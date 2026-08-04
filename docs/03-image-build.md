# 03 イメージ構築

## モード

| | `mount` (既定) | `image` |
|---|---|---|
| Vivado の所在 | ホスト。read-only bind mount | イメージ内 |
| イメージサイズ | 約 1.5 GB | 30〜100 GB 超 |
| ビルド時間 | 2〜5 分 | 1〜3 時間 |
| インストーラ | 不要 | 必要 (AMD からログインして取得) |
| 向く場面 | 開発機、Vivado が既に入っている CI | 完全に自己完結させたい配布・再現環境 |

3 つめのモード `none` は「このコンテナに Vivado は無い」ことを明示する。
`mount` と同じイメージを使い、Vivado のマウントも存在確認も行わない。
Vivado の入っていない CI ランナーでコンテナ自体を検証するためのもの
([08 CI](08-ci.md))。

バージョン切り替えはどちらのモードでも `--vivado` / `VCS_VIVADO_VERSION` で行う。
`mount` モードでは、指定バージョンがホストに無ければコンテナ起動前にエラーになり、
存在するバージョンの一覧が表示される。

## mount モード

```sh
vcs build
```

`docker/Dockerfile` の `base` ステージだけを作る。中身は:

- ダイジェスト固定された `ubuntu:24.04`
- Ubuntu アーカイブスナップショットから、`docker/packages.lock` に列挙された
  90 パッケージ (Qt/XCB、GL/EGL、NSS、fontconfig、libusb、tclsh ほか)
- `libtinfo.so.5` 等への互換シンボリックリンク (Vivado の Tcl が要求する)
- 権限降格を行う entrypoint
- ロケール、`/work`、`/opt/Xilinx` マウントポイント

実行時に `$VCS_XILINX_ROOT` が `/opt/Xilinx` に read-only で mount され、
entrypoint が `settings64.sh` を読み込む。

## image モード

インストーラは AMD のサイトからログインして各自で取得する
(本リポジトリは一切ダウンロードしない)。取得したら SHA256 を記録する:

```sh
sha256sum FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1030_1755.tar
```

`config/vivado-versions.lock` に 1 行足す:

```
2025.2|FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1030_1755.tar|<sha256>
```

ビルドする:

```sh
vcs build --installer ~/Downloads/FPGAs_AdaptiveSoCs_Unified_SDI_2025.2_1030_1755.tar
```

`vcs build` はビルド開始前にホスト側で SHA256 を照合し、
`docker/install-vivado.sh` がイメージ内でもう一度照合する。記録が無い、
あるいは一致しないインストーラではビルドが始まらない。

インストーラ本体は名前付きビルドコンテキスト (`--build-context installer=...`)
としてマウントされるので、数十 GB のファイルがビルドコンテキストとして
コピーされることはない。BuildKit が必要 (docker 23+ / podman 4.4+)。

以降は Vivado がイメージに入っているので:

```conf
VCS_VIVADO_MODE=image
```

### インストールされる構成

`xsetup -b ConfigGen` で生成した設定を使い、Documentation Navigator・
デスクトップ統合・ショートカットを無効化する。デバイスファミリを絞りたい場合は
生成された `install_config.txt` の `Modules=` 行を編集する
(`docker/install-vivado.sh` 内)。

## TLS 検査プロキシ配下でのビルド

`snapshot.ubuntu.com` は HTTPS 専用で、`ubuntu:24.04` はルート証明書を持たない。
そのため Dockerfile には `ca-bootstrap` ステージがあり、最初の TLS 接続に使う
証明書束だけをそこで作って `/opt/vcs/pin/ca-bootstrap.crt` に置き、
**それを使った同じレイヤ内で削除する**。標準の証明書ディレクトリには一切触れず、
最終イメージの信頼ストアはピン留めされた `ca-certificates` パッケージだけが作る。

パッケージの完全性がこの証明書に依存することはない。apt は署名済み
`InRelease` → `Packages` → 各 `.deb` の SHA256 という連鎖を、
バイト列がどう届いたかとは無関係に検証する。

TLS を検査するプロキシの内側でビルドする場合は、その CA を渡す:

```sh
vcs build --ca-cert /etc/ssl/certs/corporate-proxy.crt
```

この証明書もビルド中だけ信頼され、イメージの実行時信頼ストアには入らない。

## `vcs build` のオプション

```
--installer TARBALL  image モードでビルド (上記)
--ca-cert FILE       ビルド中だけ信頼する追加 CA 証明書
--tag REF            出力イメージ参照
--no-cache           レイヤキャッシュを無視
--progress MODE      auto | plain | tty
```

## 事前ビルド済みイメージの取得

```sh
vcs pull                                  # config/images.lock の prebuilt を取得
vcs pull registry.example.com/vcs@sha256:...
```

ダイジェスト固定されていない参照は拒否される。タグを引いてしまうと
ロックファイルの意味が無くなるため。

## イメージに入らないもの

- ライセンスファイル。`.lic` を含むイメージはビルド時に失敗する
  (`docker/Dockerfile` の最終チェック)。CI でも改めて検査している
- プロジェクトのソース。実行時に `/work` へ mount される
- `tcl/` と `container/` のスクリプト。実行時に read-only で mount されるので、
  イメージを作り直さずに編集・デバッグできる

## 再現性

同じ commit からビルドすれば、同じベースイメージ・同じ apt スナップショット・
同じパッケージバージョンが使われる。何がどう固定されているかは
[09 ピン留め](09-pinning.md)。

```sh
scripts/verify-pinning.sh     # すべて固定されているか検査
make lock-check               # ロックファイルが最新か検査
```
