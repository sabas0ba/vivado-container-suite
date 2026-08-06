# 10 トラブルシューティング

まず:

```sh
vvd doctor              # ホスト・エンジン・イメージ・ライセンス・表示・JTAG
vvd doctor --deep       # コンテナの中まで
vvd --dry-run <cmd>     # 実際に走るコンテナコマンドを見る
vvd -v <cmd>            # デバッグログ
```

## 起動しない

| メッセージ | 原因と対処 |
|---|---|
| `no container engine found` | podman か docker を入れる |
| `docker is installed but not usable` | デーモンが止まっている / `docker` グループに入っていない。podman なら `podman system migrate`、`/etc/subuid` を確認 |
| `image not found: ...` | `vvd build` |
| `VVD_XILINX_ROOT does not exist` | Vivado の場所を `VVD_XILINX_ROOT` で指す。あるいは `VVD_VIVADO_MODE=image` |
| `Vivado 2025.2 not found under ...` | 存在するバージョンが一覧表示される。`--vivado` で合わせる |

## Vivado が PATH に無い

```
vvd-container: WARNING: /opt/Xilinx/Vivado/2025.2/settings64.sh not found
```

- `mount` モード: ホストのインストール先とバージョンの指定が合っていない。
  `vvd doctor` の `vivado` セクションを見る
- `image` モード: イメージが `--installer` 付きでビルドされていない

## ライセンス

| メッセージ | 対処 |
|---|---|
| `no valid license was found` | `vvd doctor` でライセンス設定を確認。[04 ライセンス](04-licensing.md) |
| ホストでは通るがコンテナでは通らない | `vvd selftest --stage license`。ライセンスサーバに届いていない場合は `VVD_NETWORK=host` |
| ノードロックが効かない | MAC アドレス紐付けのため。`VVD_NETWORK=host` |

## 生成物が root 所有になる

```sh
vvd selftest --stage identity
```

- rootful docker: entrypoint が `VVD_UID`/`VVD_GID` を受け取って降格する。
  `VVD_USER_MODE=root` になっていないか確認
- rootless podman: `--userns=keep-id` が使われる。podman が古いと未対応

すでに root 所有になったファイル:

```sh
sudo chown -R "$(id -u):$(id -g)" build/
```

## GUI

| 症状 | 対処 |
|---|---|
| `no display available` | `--display x11` (X 転送) か `--display xvfb` (ヘッドレス) |
| `DISPLAY is unset` | X セッション外から起動している。`vvd gui --vnc` を使う |
| `ssh -X` したのに GUI が出ない | `vvd` が TCP ディスプレイを検出して `--network host` を付ける。`VVD_NETWORK` を別値に設定していると競合する (警告が出る) |
| VNC に繋がらない | ポートは既定で 127.0.0.1 のみ。別マシンからは `ssh -L 5901:127.0.0.1:5901` |
| VNC のパスワードが分からない | `vvd gui --vnc` が起動時に表示する。固定したいなら `VVD_VNC_PASSWORD` |
| ウィンドウが出ない / `cannot connect to X server` | `xhost +SI:localuser:$(id -un)`。ホストに `xauth` を入れる |
| Wayland で動かない | XWayland が必要。`echo $DISPLAY` が空なら XWayland が無い |
| 描画が極端に遅い | 既定はソフトウェアレンダリング。`--gpu` を試す |
| フォントが □ になる | `fontconfig` はイメージに入っている。追加フォントは `VVD_EXTRA_MOUNTS` |

## JTAG

[07 JTAG](07-jtag.md) の末尾に一覧がある。要点:

- 既定の `host` モードはホスト側で `hw_server` が動いていることが前提
- `usb` モードは抜き差しでデバイス番号が変わるので、コンテナの再起動が要る
- 権限エラーは `vvd jtag-rules --install` の後、ケーブルを挿し直す

## ビルド・実行

| 症状 | 対処 |
|---|---|
| `pattern matched no files: rtl/*.v` | `vvd.conf` のパスはプロジェクトルート相対。`vvd info` でルートを確認 |
| `timing not met` | 実際にタイミング未達。`build/reports/impl_timing.rpt` を見る。承知のうえで進めるなら `VVD_ALLOW_TIMING_VIOLATION=1` |
| 実装中に落ちる / OOM | `/dev/shm` は 1 GB に拡張済み。`VVD_MEMORY` を上げる、`VVD_JOBS` を下げる |
| ディスクが足りない | `vvd doctor` が空き容量を警告する。実装には数十 GB 要ることがある |
| `xsim` が 0 で終わるのにテストが落ちている | 失敗行を `*** FAILED:` で始める。[05 フロー](05-flows.md) |
| `unknown configuration key: VVD_...` | `vvd.conf` の打ち間違い。`vvd info --all` で有効なキー一覧 |

## イメージのビルド

| 症状 | 対処 |
|---|---|
| `Certificate verification failed` / `certificate issuer is unknown` | TLS を検査するプロキシの内側にいる。`vvd build --ca-cert /path/to/proxy-ca.crt` |
| apt が 404 を返す | スナップショットが古すぎるかミラーの障害。`scripts/lock-apt.sh --snapshot <新しい値>` |
| `--build-context` が使えない | BuildKit が要る。docker 23+ / podman 4.4+。`DOCKER_BUILDKIT=1` |
| `no SHA256 recorded for Vivado ...` | `config/vivado-versions.lock` に digest を追加する。[09 ピン留め](09-pinning.md) |
| `installer checksum mismatch` | ダウンロードが壊れているか、ファイルが記録と違う |
| `refusing to ship an image containing a .lic file` | ビルドコンテキストにライセンスが混入している。`.dockerignore` を確認 |

## それでも分からないとき

```sh
vvd shell                          # コンテナの中に入って直接調べる
vvd shell vivado -version
vvd shell ldd "$(command -v vivado)"
vvd --dry-run --verbose flow       # 組み立てられたコマンド全体
vvd info --all                     # 解決済みの全設定
```

`vvd selftest --list` でステージ一覧が出る。個別に走らせて切り分けられる。

```sh
vvd selftest --stage libs --stage env --stage tcl
```
