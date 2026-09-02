---
title: 01 はじめに
description: vivado-container-suite の導入から最初のシミュレーションとbitstream生成まで
---

# 01 はじめに

## 前提

- Linux x86_64
- podman (推奨) または docker
- Vivado 2025.2 がホストにインストール済み — 既定の `mount` モードの場合
- ライセンス (浮動 / ノードロックいずれか)

ホストに Vivado をインストールしない場合は、
[03 イメージ構築](03-image-build.md) の `image` モードを参照する。

## 1. 取り込む

サブモジュールとして取り込む場合 (推奨。バージョンが commit で固定される):

```sh
git submodule add https://github.com/sabas0ba/vivado-container-suite.git tools/vvd
git config --local submodule.recurse true
ln -s tools/vvd/bin/vvd vvd
```

単体で clone する場合:

```sh
git clone https://github.com/sabas0ba/vivado-container-suite.git ~/src/vvd
export PATH="$HOME/src/vvd/bin:$PATH"       # ~/.bashrc などに追記
```

## 2. イメージを構築する

```sh
vvd build
```

Ubuntu 24.04 の固定スナップショットから、Vivado の実行に必要な共有ライブラリ一式を
含むイメージを構築する。サイズは約 1.5 GB、初回の所要時間は 2〜5 分である。Vivado
本体は含まれず、実行時にホストから read-only で mount される。

## 3. 環境を確認する

```sh
vvd doctor
```

ホスト、コンテナエンジン、イメージ、Vivado の所在、ライセンス、ディスプレイ、JTAG、
ピン留めを一括で検査する。`FAIL` の項目には対処方法が併記される。

```sh
vvd doctor --deep      # コンテナを起動し、内部の状態も検査する
```

## 4. プロジェクトを設定する

プロジェクトのルートに `vvd.conf` を配置する。`vvd` はカレントディレクトリから
親を遡って `vvd.conf` を探索するため、サブディレクトリからでも実行できる。

```conf
VVD_PART=xc7a35ticsg324-1L
VVD_TOP=blinky
VVD_SOURCES=rtl/*.v
VVD_CONSTRAINTS=constr/*.xdc

VVD_SIM_TOP=tb_blinky
VVD_SIM_SOURCES=sim/*.v
```

ライセンスサーバのアドレスや Vivado のインストール先といったマシン固有の値は、
`vvd.local.conf` (`.gitignore` 済み) または環境変数で指定する。

```conf
# vvd.local.conf
VVD_LICENSE=2100@license.example.com
VVD_XILINX_ROOT=/opt/Xilinx
```

全キーの一覧は [02 設定](02-configuration.md) にある。

## 5. 動かす

```sh
vvd sim          # シミュレーション。ライセンス不要のため最初の確認に適する
vvd synth        # 合成
vvd impl         # 配置配線 (必要に応じて合成も実行する)
vvd bitstream    # ビットストリーム生成
vvd flow         # 上記 3 段階を 1 回の Vivado 起動で実行
vvd program      # JTAG 書き込み
```

生成物は `build/` 以下に出力される。

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
vvd shell                  # Vivado を PATH に追加した bash
```

## サンプル

同梱の `examples/blinky` はそのまま実行できる。

```sh
vvd -C examples/blinky sim
vvd -C examples/blinky flow
```

## 次に読む

- 設定を調整する → [02 設定](02-configuration.md)
- ライセンスでエラーになる → [04 ライセンス](04-licensing.md)
- デバイスに書き込む → [07 JTAG](07-jtag.md)
- CI に組み込む → [08 CI](08-ci.md)
