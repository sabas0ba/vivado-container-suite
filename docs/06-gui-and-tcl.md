# 06 GUI と Tcl

Tcl コンソールと GUI はどちらも同じイメージ・同じマウント構成で動く。
違いはディスプレイの受け渡し方だけ。

## Tcl コンソール

```sh
vcs tcl
```

`vivado -mode tcl` が対話モードで立ち上がる。ディスプレイは不要。

```tcl
Vivado% source $env(VCS_CONTAINER_TCL)/lib.tcl
Vivado% vcs::read_sources
Vivado% synth_design -top blinky -part xc7a35ticsg324-1L
Vivado% report_utilization
Vivado% exit
```

バッチ実行:

```sh
vcs run scripts/analyze.tcl
vcs run scripts/sweep.tcl 100 200 400      # -tclargs として渡る
```

## GUI

```sh
vcs gui                          # 空の IDE
vcs gui hw/blinky.xpr            # プロジェクトを開く
vcs gui build/post_route.dcp     # チェックポイントを開く (nonproject フローの定石)
vcs sim --gui                    # xsim の波形ビューア
```

### ディスプレイ方式

`--display` / `VCS_DISPLAY_MODE`:

| 値 | 動作 |
|---|---|
| `auto` (既定) | `DISPLAY` があれば `x11`、Wayland のみなら `xvfb`、それ以外は `none` |
| `x11` | X ソケット、または ssh 転送された TCP ディスプレイ。実行ごとの untrusted な xauth cookie を渡す |
| `wayland` | XWayland の X ソケット経由。実体は `x11` と同じ |
| `xvfb` | コンテナ内で Xvfb を起動。`--vnc` を付ければ VNC で見られる |
| `none` | ディスプレイなし。`vcs gui` は理由付きで拒否する |

### X11

`vcs` は実行のたびに `xauth nlist | sed 's/^..../ffff/' | xauth nmerge` で
**untrusted な使い捨て cookie** を作り、それだけをコンテナに渡す。
`xhost +local:` のようにアクセス制御を丸ごと開ける必要はなく、
cookie ファイルはコマンド終了時に消える。

ホストに `xauth` が無い場合は警告が出る。その場合の代替:

```sh
xhost +SI:localuser:$(id -un)     # 自分のユーザだけ許可する
```

### ssh -X 経由 (headless サーバ)

ビルドサーバに `ssh -X` で入って GUI を出す場合、`DISPLAY` は `:0` ではなく
`localhost:10.0` という **TCP ディスプレイ**になる。sshd は既定 (`X11UseLocalhost yes`)
でホストの 127.0.0.1 だけを listen するため、ブリッジネットワークのコンテナからは
どのゲートウェイアドレスでも届かない。

そこで `vcs` は `DISPLAY` が TCP 形式のときに自動でホストネットワーク
(`--network host`) を使う。X ソケットの mount は行わず、xauth cookie の扱いは同じ。

```sh
ssh -X buildserver
vcs gui                 # そのまま動く。--network host が自動で付く
```

このとき `--jtag host` の接続先も `host.docker.internal` から `localhost` に
切り替わる (ホストのネットワーク名前空間を共有しているため)。
`VCS_NETWORK` を別の値に設定している場合は競合を警告する。

`DISPLAY` がリモートの X サーバ (`10.20.30.40:0` など) を指している場合は、
コンテナから普通に到達できるので何も特別なことはしない。

### Wayland

Vivado は X11 専用の Qt を同梱しているため、Wayland ネイティブでは動かない。
ほぼすべての Wayland コンポジタが XWayland を持っているので、`DISPLAY` が
設定されていればそのまま `x11` 方式で動く。`DISPLAY` が無ければ、
その旨のエラーが出る (黙って壊れることはない)。

### ヘッドレス (xvfb) と VNC

X サーバが全く無いマシンで GUI を使う場合。

```sh
vcs gui --vnc                        # 127.0.0.1:5901 に公開
vcs gui --vnc --vnc-port 5999        # ポートを変える
vcs sim --vnc                        # 波形ビューアを VNC で
```

コンテナ内で Xvfb が `:99` 以降の空き番号に立ち上がり (解像度は
`VCS_XVFB_GEOMETRY`、既定 `1920x1080x24`)、x11vnc がそれを公開する。

**既定で 127.0.0.1 のみに公開し、パスワードを必須にする。** パスワードは
指定が無ければ 1 回限りのものを生成して表示する。`VCS_VNC_PASSWORD` で自分の
ものを指定してもよい。

パスワードは**環境変数にも引数にも入れない** — どちらも `docker inspect` や
`ps` が見える相手には読めてしまうため。0600 の一時ファイルを read-only で
mount して渡し、コマンド終了時に削除する。x11vnc は `-passwdfile` で受け取る。

別マシンから見るときは SSH ポート転送を使う (VNC の通信自体は暗号化されない)。

```sh
ssh -L 5901:127.0.0.1:5901 you@buildserver
vncviewer 127.0.0.1:5901
```

`--vnc-bind 0.0.0.0` で全インタフェースに公開できるが、警告が出る。
そのポートに到達できる相手は誰でも GUI を操作できる。

VNC を使わず Xvfb だけを起動することもできる (GUI が起動すること自体を
CI で確認したい場合など)。

```sh
vcs --display xvfb gui
```

### 描画

既定は `LIBGL_ALWAYS_SOFTWARE=1` のソフトウェアレンダリング。移植性は最高だが
大規模なデバイスビューは重い。GPU を使う場合:

```sh
vcs --gpu gui        # /dev/dri を渡す
```

`/dev/dri` が無ければエラーになる。ホスト側の GPU ドライバとコンテナ内の Mesa の
組み合わせによっては効果が出ないこともある。

### フォント

`fontconfig` と `fonts-dejavu-core` がイメージに入っているので、□ 文字化けは
起きない。追加フォントが要る場合は `VCS_EXTRA_MOUNTS` でホストの
`/usr/share/fonts` を mount する。

## 確認

```sh
vcs doctor                      # ディスプレイ方式の判定結果
vcs selftest --stage display    # コンテナ内から X に実際に接続できるか
```
