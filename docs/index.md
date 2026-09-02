---
title: 概要
description: vivado-container-suite の構成、用途、ドキュメント一覧
---

# vivado-container-suite

AMD Vivado の開発環境をコンテナに閉じ込め、合成、配置配線、シミュレーション、JTAG 書き込み、GUI を一貫して `vvd` CLI から実行するためのツールキットです。

## 最短で試す

```sh
git clone https://github.com/sabas0ba/vivado-container-suite.git
export PATH="$PWD/vivado-container-suite/bin:$PATH"
cd vivado-container-suite
vvd build
vvd -C examples/blinky doctor
vvd -C examples/blinky sim
```

実際の Vivado を使用するには、ホスト上のインストール先とライセンスを設定します。詳細は [01 はじめに](01-getting-started.md) を参照してください。

## 設計上の境界

| 対象 | 方針 |
|---|---|
| Vivado 本体 | 既定ではホストのインストール先を read-only mount する。必要な場合のみ installer から image へ組み込む |
| ライセンス | image には含めず、実行時に環境変数または read-only mount で渡す |
| 依存 | container image、apt package、開発ツール、GitHub Actions を digest または commit SHA で固定する |
| JTAG | 既定ではホストまたは remote の `hw_server` へ TCP 接続する。USB mode でも対象 device のみを渡す |
| CI | Vivado が無い runner でも、CLI、container、権限降格、共有 library、headless display を検証する |

## ドキュメント

| 章 | 内容 |
|---|---|
| [01 はじめに](01-getting-started.md) | 導入、最初のシミュレーションと bitstream |
| [02 設定](02-configuration.md) | `vvd.conf` の全 key と優先順位 |
| [03 イメージ構築](03-image-build.md) | mount mode / image mode、`vvd build` |
| [04 ライセンス](04-licensing.md) | 4 種類の注入方式と選択基準 |
| [05 フロー](05-flows.md) | 合成、実装、bitstream、シミュレーション |
| [06 GUI と Tcl](06-gui-and-tcl.md) | X11 / XWayland / Xvfb / VNC、Tcl console と script |
| [07 JTAG](07-jtag.md) | host / usb / remote、udev rule |
| [08 CI](08-ci.md) | 可用性 test と GitHub Actions |
| [09 ピン留め](09-pinning.md) | SHA pinning の対象と更新手順 |
| [10 トラブルシューティング](10-troubleshooting.md) | 症状別の原因と対処 |

## 全体像

```text
ホスト                                     コンテナ
─────────────────────────────────────────  ─────────────────────────────
プロジェクト                     ──rw──▶   /work
$VVD_XILINX_ROOT (Vivado)        ──ro──▶   /opt/Xilinx        ※mount mode
$VVD_CACHE_DIR                   ──rw──▶   /home/vivado       ($HOME)
<suite>/tcl                      ──ro──▶   /opt/vvd/tcl
<suite>/container                ──ro──▶   /opt/vvd/lib
ライセンスファイル               ──ro──▶   /opt/vvd/license   ※file/dir 方式
X socket                         ──ro──▶   /tmp/.X11-unix     ※x11 方式
JTAG device node                ──dev──▶  /dev/bus/usb/...   ※usb 方式

XILINXD_LICENSE_FILE、DISPLAY、VVD_* は環境変数として注入
```

`vvd` は host 側で設定と path を検証してから container を起動します。実行される container command は `vvd --dry-run <command>` または `vvd info --cmd` で事前に確認できます。
