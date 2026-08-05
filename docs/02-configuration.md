# 02 設定

## 優先順位

下ほど強い。

1. `config/vcs.defaults.conf` (組み込み既定値)
2. `<project>/vcs.conf`
3. `<project>/vcs.local.conf` — マシン固有。`.gitignore` 済み
4. 環境変数 `VCS_*`
5. コマンドラインフラグ

## 書式

`KEY=VALUE` のみ。値のクォートは任意 (1 段だけ剥がされる)。
**シェルとして評価されない**ので `$(...)` や `` ` `` は書けない。
未知のキーや不正な行はエラーになる — 打ち間違いが黙って無視されることはない。

```conf
# コメント
VCS_TOP=blinky
VCS_SOURCES="rtl/*.v rtl/sub/*.v"
```

`vcs info --all` で解決後の全キーを確認できる。

## ツールチェーン

| キー | 既定 | 意味 |
|---|---|---|
| `VCS_VIVADO_VERSION` | `2025.2` | Vivado のバージョン。`--vivado` |
| `VCS_VIVADO_EDITION` | `Vivado` | インストール先の直下ディレクトリ名 |
| `VCS_XILINX_ROOT` | `/tools/Xilinx` | ホスト側インストールルート (mount モード) |
| `VCS_VIVADO_MODE` | `mount` | `mount` = ホストから bind、`image` = イメージに同梱、`none` = Vivado なし (CI のコンテナ検証用) |

## イメージと実行

| キー | 既定 | 意味 |
|---|---|---|
| `VCS_IMAGE_NAME` | `vivado-container-suite` | イメージ名 |
| `VCS_IMAGE_TAG` | 自動 | 既定は `<version>-base` (mount / none) / `<version>` (image) |
| `VCS_IMAGE` | 自動 | 完全な参照。`--image` で上書き |
| `VCS_ENGINE` | `auto` | `auto` \| `docker` \| `podman`。`--engine` |
| `VCS_PLATFORM` | `linux/amd64` | Vivado は x86_64 専用 |
| `VCS_CA_CERT` | なし | ビルド時だけ信頼する追加 CA 証明書。TLS 検査プロキシ配下で必要。`vcs build --ca-cert` |
| `VCS_USER_MODE` | `match` | `match` = ホストの uid/gid に合わせる、`root` = 降格しない |
| `VCS_CACHE_DIR` | `$XDG_CACHE_HOME/vivado-container-suite` | コンテナの `$HOME`。IP キャッシュ等が残る |
| `VCS_JOBS` | `nproc` | 並列度 |
| `VCS_MEMORY` / `VCS_CPUS` | なし | エンジンのリソース制限 |
| `VCS_NETWORK` | なし | `--network` に渡す値 |
| `VCS_TMPFS_SIZE` | なし | `/tmp` を tmpfs にする (実装が速くなる。要メモリ) |
| `VCS_EXTRA_MOUNTS` | なし | `host:container[:ro\|rw]` を空白区切りで |
| `VCS_EXTRA_ENV` | なし | `KEY=VALUE` か、ホストから引き継ぐ変数名 |
| `VCS_EXTRA_RUN_ARGS` | なし | エンジンへの生の追加引数 |

## プロジェクト構成

パスはすべてプロジェクトルートからの相対。glob 可。
**マッチしないパターンはエラー**になる (空の設計が黙って合成されるのを防ぐ)。

| キー | 意味 |
|---|---|
| `VCS_PROJECT_NAME` | 既定はプロジェクトディレクトリ名 |
| `VCS_BUILD_DIR` | 出力先。既定 `build`。`--build-dir` |
| `VCS_TOP` | トップモジュール。`--top` |
| `VCS_PART` | デバイス。`--part` |
| `VCS_BOARD_PART` | ボードパーツ (任意) |
| `VCS_SOURCES` | Verilog |
| `VCS_SV_SOURCES` | SystemVerilog (`read_verilog -sv`) |
| `VCS_VHDL_SOURCES` | VHDL |
| `VCS_CONSTRAINTS` | XDC |
| `VCS_IP` | `.xci`。`generate_target` + `synth_ip` される |
| `VCS_BD` | ブロックデザイン `.bd` |
| `VCS_INCLUDE_DIRS` | `include_dirs` プロパティ |
| `VCS_GENERICS` | `NAME=VALUE` を空白区切り。`synth_design -generic` に渡る |
| `VCS_SYNTH_ARGS` | `synth_design` への追加引数 |
| `VCS_IMPL_DIRECTIVE` | `opt/place/route_design -directive` |
| `VCS_ALLOW_TIMING_VIOLATION` | `1` にするとタイミング未達でも失敗させない (既定 `0`) |
| `VCS_PRE_TCL` / `VCS_POST_TCL` | 合成前 / ビットストリーム後に `source` する Tcl |

### フローモード

| キー | 既定 | 意味 |
|---|---|---|
| `VCS_FLOW_MODE` | `nonproject` | `nonproject` = チェックポイント方式、`project` = `.xpr` を駆動 |
| `VCS_XPR` | なし | `project` モードで必須 |

`nonproject` はディスク上に `.xpr` を作らず、再現性が高いので CI 向き。
既存の IDE プロジェクトが正なら `project` を使う。詳細は [05 フロー](05-flows.md)。

## シミュレーション

| キー | 意味 |
|---|---|
| `VCS_SIM_TOP` | テストベンチのトップ |
| `VCS_SIM_SOURCES` | テストベンチ (Verilog/SV)。設計ソースは自動で追加される |
| `VCS_SIM_VHDL_SOURCES` | テストベンチ (VHDL) |
| `VCS_SIM_TIME` | `run <値>`。未設定なら `run all` |
| `VCS_SIM_LIBS` | `xelab -L` に渡す追加ライブラリ |
| `VCS_SIM_XVLOG_ARGS` / `VCS_SIM_XELAB_ARGS` | 追加引数 |

## ライセンス

| キー | 意味 |
|---|---|
| `VCS_LICENSE` | `port@host` \| `/abs/path.lic` \| `dir:/abs/path` \| `none`。`--license` |
| `VCS_XILINX_DOTDIR` | `~/.Xilinx` 相当のディレクトリ。既定は存在すれば自動 |

[04 ライセンス](04-licensing.md) 参照。

## ディスプレイと JTAG

| キー | 既定 | 意味 |
|---|---|---|
| `VCS_DISPLAY_MODE` | `auto` | `auto` \| `x11` \| `wayland` \| `xvfb` \| `none`。`--display` |
| `VCS_VNC` | `0` | ヘッドレス表示を VNC で公開。`vcs gui --vnc` |
| `VCS_VNC_PORT` | `5901` | ホスト側の公開ポート |
| `VCS_VNC_BIND` | `127.0.0.1` | 公開アドレス。`0.0.0.0` は要注意 |
| `VCS_VNC_PASSWORD` | なし | 未設定なら 1 回限りのものを生成。`vcs info` では伏せ字になる |
| `VCS_JTAG_MODE` | `host` | `host` \| `usb` \| `remote:HOST[:PORT]` \| `none`。`--jtag` |
| `VCS_HW_SERVER_PORT` | `3121` | `hw_server` のポート |

[06 GUI と Tcl](06-gui-and-tcl.md) / [07 JTAG](07-jtag.md) 参照。

## グローバルフラグ

```
-C, --project DIR    プロジェクトルート
    --config FILE    vcs.conf の代わりに使うファイル
    --vivado VER     Vivado バージョン
    --engine E       auto | docker | podman
    --image REF      イメージ参照
    --license SPEC   ライセンス指定
    --display MODE   ディスプレイ方式
    --jtag MODE      JTAG 方式
    --part PART      デバイス
    --top MODULE     トップモジュール
    --build-dir DIR  出力先
    --gpu            /dev/dri を渡す (ハードウェア GL)
-n, --dry-run        コンテナを起動せず、コマンドだけ表示
-v, --verbose        デバッグログ
-q, --quiet          警告以上のみ
```
