# 10 トラブルシューティング

最初に次のコマンドを実行する。

```sh
vvd doctor              # ホスト、エンジン、イメージ、ライセンス、表示、JTAG を検査する
vvd doctor --deep       # コンテナ内部の状態も検査する
vvd --dry-run <cmd>     # 実行されるコンテナコマンドを表示する
vvd -v <cmd>            # デバッグログを出力する
```

## 起動しない

| メッセージ | 原因と対処 |
|---|---|
| `no container engine found` | podman または docker を導入する |
| `docker is installed but not usable` | デーモンが停止している、または `docker` グループに所属していない。podman の場合は `podman system migrate` の実行と `/etc/subuid` を確認する |
| `image not found: ...` | `vvd build` を実行する |
| `VVD_XILINX_ROOT does not exist` | Vivado の位置を `VVD_XILINX_ROOT` で指定する。または `VVD_VIVADO_MODE=image` を使用する |
| `Vivado 2025.2 not found under ...` | 存在するバージョンが一覧表示される。`--vivado` で指定を合わせる |

## Vivado が PATH に無い

```
vvd-container: WARNING: /opt/Xilinx/Vivado/2025.2/settings64.sh not found
```

- `mount` モード: ホストのインストール先とバージョンの指定が一致していない。
  `vvd doctor` の `vivado` セクションを確認する
- `image` モード: イメージが `--installer` 付きでビルドされていない

## ライセンス

| メッセージ | 対処 |
|---|---|
| `no valid license was found` | `vvd doctor` でライセンス設定を確認する。[04 ライセンス](04-licensing.md) を参照 |
| ホストでは成功するがコンテナでは失敗する | `vvd selftest --stage license` で確認する。ライセンスサーバに到達できない場合は `VVD_NETWORK=host` を指定する |
| ノードロックが機能しない | ライセンスが MAC アドレスに紐付くため。`VVD_NETWORK=host` を指定する |

## 生成物が root 所有になる

```sh
vvd selftest --stage identity
```

- rootful docker: entrypoint が `VVD_UID` / `VVD_GID` を受け取って権限を降格する。
  `VVD_USER_MODE=root` が設定されていないか確認する
- rootless podman: `--userns=keep-id` を使用する。podman のバージョンが古い場合は
  未対応である

すでに root 所有となったファイルは次のように変更する。

```sh
sudo chown -R "$(id -u):$(id -g)" build/
```

## GUI

| 症状 | 対処 |
|---|---|
| `no display available` | `--display x11` (X 転送) または `--display xvfb` (ヘッドレス) を指定する |
| `DISPLAY is unset` | X セッション外から起動している。`vvd gui --vnc` を使用する |
| `ssh -X` で接続したが GUI が表示されない | `vvd` は TCP ディスプレイを検出して `--network host` を付与する。`VVD_NETWORK` に別の値を設定していると競合する (警告を表示する) |
| VNC に接続できない | ポートは既定で 127.0.0.1 のみに公開される。別のマシンからは `ssh -L 5901:127.0.0.1:5901` を使用する |
| VNC のパスワードが不明 | `vvd gui --vnc` が起動時に表示する。固定する場合は `VVD_VNC_PASSWORD` を指定する |
| ウィンドウが表示されない / `cannot connect to X server` | `xhost +SI:localuser:$(id -un)` を実行する。ホストに `xauth` を導入する |
| Wayland で動作しない | XWayland が必要である。`echo $DISPLAY` が空の場合は XWayland が存在しない |
| 描画が極端に遅い | 既定はソフトウェアレンダリングである。`--gpu` を試す |
| フォントが豆腐文字になる | `fontconfig` はイメージに含まれている。追加のフォントは `VVD_EXTRA_MOUNTS` で mount する |

## JTAG

一覧は [07 JTAG](07-jtag.md) の末尾にある。要点は次のとおり。

- 既定の `host` モードは、ホスト側で `hw_server` が起動していることを前提とする
- `usb` モードでは抜き差しによりデバイス番号が変化するため、コンテナの再起動が必要
- 権限エラーの場合は `vvd jtag-rules --install` を実行し、ケーブルを接続し直す

## ビルド・実行

| 症状 | 対処 |
|---|---|
| `pattern matched no files: rtl/*.v` | `vvd.conf` のパスはプロジェクトルートからの相対である。`vvd info` でルートを確認する |
| `timing not met` | タイミングが未達である。`build/reports/impl_timing.rpt` を確認する。未達を許容する場合は `VVD_ALLOW_TIMING_VIOLATION=1` を指定する |
| 実装中に異常終了する / OOM | `/dev/shm` は 1 GB に拡張済みである。`VVD_MEMORY` を増やすか、`VVD_JOBS` を減らす |
| ディスク容量が不足する | `vvd doctor` が空き容量を警告する。実装には数十 GB を要する場合がある |
| `xsim` が 0 で終了するがテストは失敗している | 失敗行を `*** FAILED:` で開始する。[05 フロー](05-flows.md) を参照 |
| `unknown configuration key: VVD_...` | `vvd.conf` の記述誤りである。有効なキーの一覧は `vvd info --all` で確認する |

## イメージのビルド

| 症状 | 対処 |
|---|---|
| `Certificate verification failed` / `certificate issuer is unknown` | TLS を検査するプロキシの内側で実行している。`vvd build --ca-cert /path/to/proxy-ca.crt` を使用する |
| apt が 404 を返す | スナップショットが古いか、ミラーの障害である。`scripts/lock-apt.sh --snapshot <新しい値>` を実行する |
| `--build-context` が使用できない | BuildKit が必要である (docker 23 以降 / podman 4.4 以降)。`DOCKER_BUILDKIT=1` を設定する |
| `no SHA256 recorded for Vivado ...` | `config/vivado-versions.lock` に digest を追加する。[09 ピン留め](09-pinning.md) を参照 |
| `installer checksum mismatch` | ダウンロードが破損しているか、ファイルが記録と異なる |
| `refusing to ship an image containing a .lic file` | ビルドコンテキストにライセンスが混入している。`.dockerignore` を確認する |

## 原因を特定できない場合

```sh
vvd shell                          # コンテナ内に入って直接調査する
vvd shell vivado -version
vvd shell ldd "$(command -v vivado)"
vvd --dry-run --verbose flow       # 組み立てたコマンド全体を表示する
vvd info --all                     # 解決済みの全設定を表示する
```

`vvd selftest --list` でステージの一覧を表示する。個別に実行して問題を切り分けられる。

```sh
vvd selftest --stage libs --stage env --stage tcl
```
