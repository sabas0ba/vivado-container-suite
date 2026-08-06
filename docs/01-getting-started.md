# 01 はじめに

## 前提

- Linux x86_64
- podman (推奨) または docker
- Vivado 2025.2 がホストにインストール済み — 既定の `mount` モードの場合
- ライセンス (浮動 / ノードロックいずれか)

Vivado をホストに入れたくない場合は
[03 イメージ構築](03-image-build.md) の `image` モードを参照。

コマンド名の `vvd` は Vivado の子音から。EDA 領域で `vcs` は Synopsys VCS
(Verilog Compiler Simulator) の名前なので使っていない。

## 1. 取り込む

サブモジュール (推奨。バージョンが commit で固定される):

```sh
git submodule add https://github.com/sabas0ba/vivado-container-suite.git tools/vvd
git config --local submodule.recurse true
ln -s tools/vvd/bin/vvd vvd
```

単体 clone:

```sh
git clone https://github.com/sabas0ba/vivado-container-suite.git ~/src/vvd
export PATH="$HOME/src/vvd/bin:$PATH"       # ~/.bashrc などに追記
```

## 2. イメージを構築する

```sh
vvd build
```

Ubuntu 24.04 の固定スナップショットから、Vivado の実行に必要な共有ライブラリ一式を
入れたイメージを作る。約 1.5 GB、初回で 2〜5 分。Vivado 本体は含まれない
(実行時にホストから read-only で mount される)。

## 3. 環境を確認する

```sh
vvd doctor
```

ホスト、コンテナエンジン、イメージ、Vivado の所在、ライセンス、ディスプレイ、JTAG、
ピン留めをまとめて検査する。`FAIL` があれば、そこに対処法が出る。

```sh
vvd doctor --deep      # コンテナを実際に起動して中身も検査する
```

## 4. プロジェクトを設定する

プロジェクトのルートに `vvd.conf` を置く。`vvd` はカレントディレクトリから親を
遡って `vvd.conf` を探すので、サブディレクトリからでも動く。

```conf
VVD_PART=xc7a35ticsg324-1L
VVD_TOP=blinky
VVD_SOURCES=rtl/*.v
VVD_CONSTRAINTS=constr/*.xdc

VVD_SIM_TOP=tb_blinky
VVD_SIM_SOURCES=sim/*.v
```

ライセンスサーバのアドレスや Vivado のインストール先といった**マシン固有の値**は
`vvd.local.conf` (`.gitignore` 済み) か環境変数に置く。

```conf
# vvd.local.conf
VVD_LICENSE=2100@license.example.com
VVD_XILINX_ROOT=/opt/Xilinx
```

全キーは [02 設定](02-configuration.md)。

## 5. 動かす

```sh
vvd sim          # シミュレーション。ライセンス不要なので最初の確認に向く
vvd synth        # 合成
vvd impl         # 配置配線 (必要なら合成も走る)
vvd bitstream    # ビットストリーム生成
vvd flow         # 上記 3 つを 1 回の Vivado 起動でまとめて
vvd program      # JTAG 書き込み
```

生成物は `build/` の下に出る。

```
build/
├── post_synth.dcp        合成後チェックポイント
├── post_route.dcp        配置配線後チェックポイント
├── blinky.bit            ビットストリーム
├── reports/              利用率・タイミング・DRC・電力
├── logs/                 Vivado のログ
└── sim/                  波形 (.wdb) と xsim の作業ディレクトリ
```

## 6. 対話的に使う

```sh
vvd tcl                    # Vivado Tcl コンソール
vvd gui                    # Vivado IDE
vvd gui build/post_route.dcp   # チェックポイントを開く
vvd shell                  # Vivado が PATH に載った bash
```

## サンプル

同梱の `examples/blinky` がそのまま動く。

```sh
vvd -C examples/blinky sim
vvd -C examples/blinky flow
```

## 次に読む

- 設定を詰める → [02 設定](02-configuration.md)
- ライセンスが通らない → [04 ライセンス](04-licensing.md)
- 書き込みたい → [07 JTAG](07-jtag.md)
- CI に載せたい → [08 CI](08-ci.md)
