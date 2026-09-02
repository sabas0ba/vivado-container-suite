---
title: 06 GUI と Tcl
description: Vivado GUI、Tcl console、headless displayの使用方法
---

# 06 GUI と Tcl

Tcl コンソールと GUI は、いずれも同一のイメージとマウント構成で動作する。
両者の違いはディスプレイの受け渡し方のみである。

## Tcl コンソール

```sh
vvd tcl
```

`vivado -mode tcl` が対話モードで起動する。ディスプレイは不要である。

```tcl
Vivado% source $env(VVD_CONTAINER_TCL)/lib.tcl
Vivado% vvd::read_sources
Vivado% synth_design -top blinky -part xc7a35ticsg324-1L
Vivado% report_utilization
Vivado% exit
```

バッチ実行の場合は次のようにする。

```sh
vvd run scripts/analyze.tcl
vvd run scripts/sweep.tcl 100 200 400      # -tclargs として渡される
```

## GUI

```sh
vvd gui                          # 空の IDE
vvd gui hw/blinky.xpr            # プロジェクトを開く
vvd gui build/post_route.dcp     # チェックポイントを開く (nonproject フローの標準手順)
vvd sim --gui                    # xsim の波形ビューアを開く
```

### ディスプレイ方式

`--display` / `VVD_DISPLAY_MODE` で指定する。

| 値 | 動作 |
|---|---|
| `auto` (既定) | `DISPLAY` があれば `x11`、Wayland のみであれば `xvfb`、いずれも無い場合は `none` を選択する |
| `x11` | X ソケット、または ssh 転送された TCP ディスプレイを使用する。実行ごとに untrusted な xauth cookie を渡す |
| `wayland` | XWayland の X ソケットを経由する。実体は `x11` と同一である |
| `xvfb` | コンテナ内で Xvfb を起動する。`--vnc` を指定すると VNC で表示できる |
| `none` | ディスプレイを使用しない。`vvd gui` は理由を示して実行を拒否する |

### X11

`vvd` は実行のたびに `xauth nlist | sed 's/^..../ffff/' | xauth nmerge` によって
untrusted な使い捨て cookie を生成し、これのみをコンテナに渡す。`xhost +local:` の
ようにアクセス制御全体を開放する必要はなく、cookie ファイルはコマンドの終了時に
削除される。

ホストに `xauth` が存在しない場合は警告を表示する。その場合は次の方法で代替する。

```sh
xhost +SI:localuser:$(id -un)     # 自分のユーザだけ許可する
```

### ssh -X 経由 (headless サーバ)

ビルドサーバに `ssh -X` で接続して GUI を表示する場合、`DISPLAY` は `:0` ではなく
`localhost:10.0` という TCP ディスプレイとなる。sshd は既定 (`X11UseLocalhost yes`)
でホストの 127.0.0.1 のみを listen するため、ブリッジネットワーク上のコンテナからは
いずれのゲートウェイアドレスを経由しても到達できない。

そのため `vvd` は、`DISPLAY` が TCP 形式の場合に自動的にホストネットワーク
(`--network host`) を使用する。X ソケットの mount は行わず、xauth cookie の扱いは
同一である。

```sh
ssh -X buildserver
vvd gui                 # --network host が自動的に付与される
```

このとき `--jtag host` の接続先も `host.docker.internal` から `localhost` へ
切り替わる。ホストのネットワーク名前空間を共有するためである。`VVD_NETWORK` に
別の値を設定している場合は、競合を警告する。

`DISPLAY` がリモートの X サーバ (`10.20.30.40:0` など) を指す場合は、コンテナから
通常どおり到達できるため、特別な処理は行わない。

### Wayland

Vivado は X11 専用の Qt を同梱しているため、Wayland ネイティブでは動作しない。
ほぼすべての Wayland コンポジタが XWayland を備えているため、`DISPLAY` が設定されて
いれば `x11` 方式で動作する。`DISPLAY` が存在しない場合は、その旨のエラーを表示する。

### ヘッドレス (xvfb) と VNC

X サーバが存在しないマシンで GUI を使用する場合の方式である。

```sh
vvd gui --vnc                        # 127.0.0.1:5901 に公開する
vvd gui --vnc --vnc-port 5999        # ポートを変更する
vvd sim --vnc                        # 波形ビューアを VNC で表示する
```

コンテナ内で Xvfb が `:99` 以降の空き番号で起動し (解像度は `VVD_XVFB_GEOMETRY`、
既定値は `1920x1080x24`)、x11vnc がこれを公開する。

既定では 127.0.0.1 のみに公開し、パスワードを必須とする。パスワードの指定が無い
場合は 1 回限りのものを生成して表示する。`VVD_VNC_PASSWORD` で任意のものを指定する
こともできる。

パスワードは環境変数にも引数にも格納しない。いずれも `docker inspect` や `ps` を
実行できる相手から読み取れるためである。パーミッション 0600 の一時ファイルを
read-only で mount して受け渡し、コマンドの終了時に削除する。x11vnc へは
`-passwdfile` で渡す。

別のマシンから接続する場合は SSH ポート転送を使用する。VNC の通信自体は暗号化
されないためである。

```sh
ssh -L 5901:127.0.0.1:5901 you@buildserver
vncviewer 127.0.0.1:5901
```

`--vnc-bind 0.0.0.0` を指定すると全インタフェースに公開できるが、警告を表示する。
そのポートに到達できる相手は誰でも GUI を操作できる状態となる。

VNC を使用せず Xvfb のみを起動することもできる。GUI が起動すること自体を CI で
確認する場合などに使用する。

```sh
vvd --display xvfb gui
```

### 描画

既定は `LIBGL_ALWAYS_SOFTWARE=1` によるソフトウェアレンダリングである。移植性が
高い一方、大規模なデバイスビューでは描画が遅い。GPU を使用する場合は次のように
指定する。

```sh
vvd --gpu gui        # /dev/dri を渡す
```

`/dev/dri` が存在しない場合はエラーとなる。ホスト側の GPU ドライバとコンテナ内の
Mesa の組み合わせによっては、効果が得られない場合がある。

### フォント

`fontconfig` と `fonts-dejavu-core` をイメージに含めているため、豆腐文字の
発生しない状態になっている。追加のフォントが必要な場合は、`VVD_EXTRA_MOUNTS` で
ホストの `/usr/share/fonts` を mount する。

## 確認

```sh
vvd doctor                      # ディスプレイ方式の判定結果を表示する
vvd selftest --stage display    # コンテナ内から X に接続できるかを検証する
```
