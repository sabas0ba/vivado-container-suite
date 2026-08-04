# ドキュメント

| 章 | 内容 |
|---|---|
| [01 はじめに](01-getting-started.md) | 導入、最初のシミュレーションとビットストリーム |
| [02 設定](02-configuration.md) | `vcs.conf` の全キーと優先順位 |
| [03 イメージ構築](03-image-build.md) | mount モード / image モード、`vcs build` |
| [04 ライセンス](04-licensing.md) | 4 つの注入方式と使い分け |
| [05 フロー](05-flows.md) | 合成・実装・ビットストリーム・シミュレーション |
| [06 GUI と Tcl](06-gui-and-tcl.md) | X11 / XWayland / Xvfb、Tcl コンソールとスクリプト |
| [07 JTAG](07-jtag.md) | host / usb / remote、udev ルール |
| [08 CI](08-ci.md) | 可用性テストと GitHub Actions |
| [09 ピン留め](09-pinning.md) | SHA pinning の対象と更新手順 |
| [10 トラブルシューティング](10-troubleshooting.md) | 症状別の原因と対処 |

## 全体像

```
ホスト                                     コンテナ
─────────────────────────────────────────  ─────────────────────────────
プロジェクト                     ──rw──▶   /work
$VCS_XILINX_ROOT (Vivado)        ──ro──▶   /opt/Xilinx        ※mount モード
$VCS_CACHE_DIR                   ──rw──▶   /home/vivado       ($HOME)
<suite>/tcl                      ──ro──▶   /opt/vcs/tcl
<suite>/container                ──ro──▶   /opt/vcs/lib
ライセンスファイル               ──ro──▶   /opt/vcs/license   ※file/dir 方式
X ソケット                       ──ro──▶   /tmp/.X11-unix     ※x11 方式
JTAG デバイスノード              ──dev──▶  /dev/bus/usb/...   ※usb 方式

XILINXD_LICENSE_FILE, DISPLAY, VCS_* は環境変数として注入
```

`vcs` は「ホスト側で検証してからコンテナを起動する」設計になっている。存在しない
Vivado バージョン、読めないライセンス、プロジェクト外のファイル参照などは、
コンテナを起動する前にホスト側で失敗する。何が実行されるかは `--dry-run` で確認できる。

```sh
vcs --dry-run flow      # 組み立てられたコンテナコマンドを表示するだけ
vcs info --cmd          # 同上 + 解決済み設定
```
