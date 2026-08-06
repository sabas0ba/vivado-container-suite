# vivado-container-suite

AMD Vivado の開発環境をコンテナに閉じ込め、**すべての操作を CLI から**行うためのツールキット。

```sh
vvd build            # コンテナイメージを構築
vvd sim              # 論理シミュレーション (xsim)
vvd flow             # 合成 → 配置配線 → ビットストリーム
vvd program          # JTAG 書き込み
vvd tcl              # Tcl コンソール
vvd gui              # Vivado IDE (X11 / XWayland / Xvfb)
vvd doctor           # 環境診断
vvd selftest         # 可用性テスト
```

コマンド名は `vvd`（Vivado の子音）。EDA 領域で `vcs` は Synopsys VCS
(Verilog Compiler Simulator) を指すため、避けている。

## 設計方針

| 方針 | 実装 |
|---|---|
| Vivado 本体はイメージに焼かない (既定) | ホストのインストール先を read-only bind mount。イメージは約 1.5 GB |
| ライセンスはイメージに入れない | 起動時に環境変数 (浮動) か read-only mount (ノードロック) で注入。`.lic` を含むイメージはビルドが失敗する |
| すべて SHA pin | ベースイメージはダイジェスト、apt は Ubuntu snapshot + バージョン、開発ツールは sha256 / commit、GitHub Actions は commit SHA |
| 権限は最小限 | JTAG は既定でホストの `hw_server` に TCP 接続。USB パススルーは該当デバイスノードのみ。`--privileged` は使わない |
| CI で検証できる | Vivado なしでも、entrypoint・権限降格・共有ライブラリ・ヘッドレス X を実機テストする |

## 導入

サブモジュールとして取り込む場合:

```sh
git submodule add https://github.com/sabas0ba/vivado-container-suite.git tools/vvd
ln -s tools/vvd/bin/vvd vvd        # あるいは PATH に通す
```

単体で clone する場合:

```sh
git clone https://github.com/sabas0ba/vivado-container-suite.git
export PATH="$PWD/vivado-container-suite/bin:$PATH"
```

プロジェクト直下に `vvd.conf` を置けば準備完了。詳細は
[docs/01-getting-started.md](docs/01-getting-started.md)。

```conf
VVD_PART=xc7a35ticsg324-1L
VVD_TOP=blinky
VVD_SOURCES=rtl/*.v
VVD_CONSTRAINTS=constr/*.xdc
VVD_SIM_TOP=tb_blinky
VVD_SIM_SOURCES=sim/*.v
```

## ドキュメント

| | |
|---|---|
| [01 はじめに](docs/01-getting-started.md) | 導入から最初のビットストリームまで |
| [02 設定](docs/02-configuration.md) | `vvd.conf` の全キー |
| [03 イメージ構築](docs/03-image-build.md) | mount モードと image モード |
| [04 ライセンス](docs/04-licensing.md) | 注入方式と選び方 |
| [05 フロー](docs/05-flows.md) | 合成・実装・シミュレーション |
| [06 GUI と Tcl](docs/06-gui-and-tcl.md) | X11 / XWayland / Xvfb、Tcl コンソール |
| [07 JTAG](docs/07-jtag.md) | 3 つの転送方式と udev ルール |
| [08 CI](docs/08-ci.md) | 可用性テストの組み込み方 |
| [09 ピン留め](docs/09-pinning.md) | 何をどう固定しているか |
| [10 トラブルシューティング](docs/10-troubleshooting.md) | 症状から原因へ |

Claude Code 向けのスキル定義を
[`.claude/skills/vivado-container-suite/SKILL.md`](.claude/skills/vivado-container-suite/SKILL.md)
に同梱している。

## 動作要件

- Linux x86_64 (Vivado が x86_64 専用のため)
- podman か docker
- Vivado 2025.2 (既定。`--vivado` で切り替え可能)
- ライセンス。無償の WebPACK 相当ライセンスでもサンプル設計は通る

## 開発

```sh
make tools      # ピン留めされた開発ツールを .tools/ に取得
make check      # lint + ピン留め検証 + 単体テスト
make image      # ベースイメージを構築
make selftest   # コンテナ内可用性テスト
```

## ライセンス

MIT。Vivado 本体およびそのライセンスは本リポジトリには含まれない。
