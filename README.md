# vivado-container-suite

AMD Vivado の開発環境をコンテナに閉じ込め、すべての操作を CLI から行うためのツールキット。

[公開ドキュメント](https://sabas0ba.github.io/vivado-container-suite/) / [ドキュメントのソース](docs/index.md)

```sh
vvd build            # コンテナイメージを構築
vvd sim              # 論理シミュレーション (xsim)
vvd flow             # 合成 → 配置配線 → ビットストリーム
vvd program          # JTAG 書き込み
vvd tcl              # Tcl コンソール
vvd gui              # Vivado IDE (X11 / XWayland / Xvfb / VNC)
vvd doctor           # 環境診断
vvd selftest         # 可用性テスト
```

## 設計方針

| 方針 | 実装 |
|---|---|
| Vivado 本体をイメージに含めない (既定) | ホストのインストール先を read-only bind mount する。イメージサイズは約 1.5 GB |
| ライセンスをイメージに含めない | 実行時に環境変数 (浮動) または read-only mount (ノードロック) で注入する。`.lic` を含むイメージはビルド時に失敗する |
| 依存をすべて内容ハッシュで固定 | ベースイメージはダイジェスト、apt は Ubuntu アーカイブスナップショットと明示バージョン、開発ツールは sha256 または commit ID、GitHub Actions は commit SHA |
| 権限を最小限に保つ | JTAG は既定でホストの `hw_server` へ TCP 接続する。USB パススルーは該当するデバイスノードのみを渡す。`--privileged` は使用しない |
| CI で検証可能 | Vivado 不在の環境でも、entrypoint・権限降格・共有ライブラリ・ヘッドレス X を実際に検証する |

## 動作要件

- Linux x86_64 (Vivado が x86_64 専用のため)
- podman または docker
- Vivado 2025.2 (既定値。`--vivado` で変更可能)
- ライセンス (無償の WebPACK 相当でもサンプル設計は動作する)

## 導入

サブモジュールとして取り込む場合:

```sh
git submodule add https://github.com/sabas0ba/vivado-container-suite.git tools/vvd
ln -s tools/vvd/bin/vvd vvd
```

単体で clone する場合:

```sh
git clone https://github.com/sabas0ba/vivado-container-suite.git
export PATH="$PWD/vivado-container-suite/bin:$PATH"
```

いずれの場合も、プロジェクトルートに `vvd.conf` を配置すれば使用できる。

```conf
VVD_PART=xc7a35ticsg324-1L
VVD_TOP=blinky
VVD_SOURCES=rtl/*.v
VVD_CONSTRAINTS=constr/*.xdc
VVD_SIM_TOP=tb_blinky
VVD_SIM_SOURCES=sim/*.v
```

手順の詳細は [docs/01-getting-started.md](docs/01-getting-started.md) を参照。

## ドキュメント

ブラウザで参照する場合は [GitHub Pages 版](https://sabas0ba.github.io/vivado-container-suite/) を使用する。

| | |
|---|---|
| [01 はじめに](docs/01-getting-started.md) | 導入から最初のビットストリームまで |
| [02 設定](docs/02-configuration.md) | `vvd.conf` の全キー |
| [03 イメージ構築](docs/03-image-build.md) | mount モードと image モード |
| [04 ライセンス](docs/04-licensing.md) | 注入方式と選択基準 |
| [05 フロー](docs/05-flows.md) | 合成・実装・シミュレーション |
| [06 GUI と Tcl](docs/06-gui-and-tcl.md) | X11 / XWayland / Xvfb / VNC、Tcl コンソール |
| [07 JTAG](docs/07-jtag.md) | 3 種類の転送方式と udev ルール |
| [08 CI](docs/08-ci.md) | 可用性テストの組み込み方 |
| [09 ピン留め](docs/09-pinning.md) | 固定の対象と方法 |
| [10 トラブルシューティング](docs/10-troubleshooting.md) | 症状別の原因と対処 |

Claude Code 向けのスキル定義を
[`.claude/skills/vivado-container-suite/SKILL.md`](.claude/skills/vivado-container-suite/SKILL.md)
に同梱する。

## 開発

```sh
make tools      # ピン留めされた開発ツールを .tools/ に取得
make check      # lint・ピン留め検証・単体テスト
make image      # ベースイメージを構築
make selftest   # コンテナ内可用性テスト
```

## ライセンス

MIT ライセンス。Vivado 本体およびそのライセンスは本リポジトリに含まない。
