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
| `x11` | `/tmp/.X11-unix` を mount し、実行ごとの untrusted な xauth cookie を渡す |
| `wayland` | XWayland の X ソケット経由。実体は `x11` と同じ |
| `xvfb` | コンテナ内で Xvfb を起動。表示はされない |
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

### Wayland

Vivado は X11 専用の Qt を同梱しているため、Wayland ネイティブでは動かない。
ほぼすべての Wayland コンポジタが XWayland を持っているので、`DISPLAY` が
設定されていればそのまま `x11` 方式で動く。`DISPLAY` が無ければ、
その旨のエラーが出る (黙って壊れることはない)。

### ヘッドレス (xvfb)

サーバ上で GUI を動かして VNC で覗きたい、あるいは GUI が起動することだけを
CI で確認したい場合に使う。

```sh
vcs --display xvfb gui
```

コンテナ内で Xvfb が `:99` 以降の空き番号に立ち上がる。解像度は
`VCS_XVFB_GEOMETRY` (既定 `1920x1080x24`)。

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
