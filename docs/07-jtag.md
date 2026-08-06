# 07 JTAG

## 3 つの転送方式

`--jtag` / `VVD_JTAG_MODE`:

| 値 | `hw_server` の場所 | コンテナに渡す権限 |
|---|---|---|
| `host` (既定) | **ホスト** | なし。TCP 接続のみ |
| `remote:HOST[:PORT]` | 指定したマシン | なし。TCP 接続のみ |
| `usb` | コンテナ内 | 該当する USB デバイスノードのみ |
| `none` | — | — |

**既定の `host` が最も安全**で、これを勧める。コンテナにはデバイスも
ケーパビリティも一切渡らない。`--privileged` はどのモードでも使わない。

## host モード

ホストで `hw_server` を動かし、コンテナはそこへ TCP で繋ぐ。

```sh
# ホスト側 (一度だけ)
source /tools/Xilinx/Vivado/2025.2/settings64.sh
hw_server &
```

```sh
vvd program                    # 既定でこの経路を使う
vvd program --list             # スキャンチェーンの列挙だけ
```

コンテナ内からは `host.docker.internal` (docker) /
`host.containers.internal` (podman) で解決される。docker では
`--add-host ...:host-gateway` が自動で付く。

ホストに Vivado が入っていない場合は、USB を渡したコンテナで `hw_server` を
動かして、その口を公開できる:

```sh
vvd hw-server                       # 127.0.0.1:3121 で待ち受け
vvd hw-server --bind 0.0.0.0        # 他マシンからも (要注意: 誰でも書き込める)
```

## remote モード

ラボの共有マシンや CI のハードウェアランナーに繋ぐ。

```sh
vvd --jtag remote:lab-01.example.com:3121 program
```

```conf
# vvd.local.conf
VVD_JTAG_MODE=remote:lab-01.example.com
VVD_HW_SERVER_PORT=3121
```

## usb モード

ケーブルをコンテナに直接渡す。手軽だが、`host` モードより権限が広い。

```sh
vvd --jtag usb program
```

`lsusb` を見て、既知のベンダ ID を持つデバイスの
`/dev/bus/usb/<bus>/<dev>` だけを `--device` で渡す。

| VID | ケーブル |
|---|---|
| `0403` | FTDI 系 — Digilent HS1/HS2/HS3、JTAG-SMT2/SMT3、Arty/Nexys のオンボード |
| `03fd` | Xilinx Platform Cable USB / USB II (DLC9, DLC10) |
| `1443` | Digilent (旧 VID) |
| `1d50` | 一部のオープンなアダプタ |

**制約**: USB のバス番号・デバイス番号は抜き差しで変わる。ケーブルを挿し直したら
コンテナを起動し直す必要がある。これを避けたい場合は `host` モードにするか、
明示的に USB ツリー全体を渡す:

```sh
VVD_JTAG_USB_ALL=1 vvd --jtag usb program     # 全 USB デバイスが見える。警告が出る
```

### udev ルール

デバイスノードを一般ユーザで開けるようにする。これはホスト側の設定であり、
これがあるおかげで Vivado もコンテナも root で動かす必要がなくなる。

```sh
vvd jtag-rules --print     # 内容を確認
vvd jtag-rules --install   # /etc/udev/rules.d/ に導入 (sudo)
vvd jtag-rules --list      # 今つながっているケーブル
```

導入したらケーブルを挿し直す。ルールは `uaccess` タグ (ローカルログイン
セッションのユーザに付与) と `plugdev` グループの両方を設定するので、
どちらの運用にも対応する。

## 書き込む

```sh
vvd program                                 # build/<top>.bit
vvd program --bit build/other.bit
vvd program --target xc7a35t_0              # スキャンチェーンに複数デバイスがある場合
vvd program --probes build/blinky.ltx       # ILA/VIO のプローブ
vvd program --list                          # 列挙のみ
```

`tcl/program.tcl` が `connect_hw_server` → `open_hw_target` →
`program_hw_devices` を実行し、最後に DONE ビットを確認する。
到達できない・ターゲットが無い場合は、原因と対処を添えて失敗する。

## 確認

```sh
vvd doctor                   # hw_server の待ち受け、ケーブル、パーミッション
vvd selftest --stage jtag    # 実際に接続してスキャンチェーンを読む
```

`vvd selftest` の JTAG ステージは、ケーブルが無い・`hw_server` が居ない場合は
失敗ではなく **skip** になる。ハードウェアの有無で CI が壊れないようにするため。

## よくある失敗

| 症状 | 対処 |
|---|---|
| `cannot reach hw_server at TCP:host.docker.internal:3121` | ホストで `hw_server` が動いていない。`vvd doctor` が教える |
| `no JTAG target is attached` | ケーブル・ボード電源・udev ルールを確認 |
| `no JTAG cable found on the USB bus` | `vvd jtag-rules --list` で認識を確認。挿し直したら再起動 |
| 抜き差し後に動かない (usb モード) | デバイス番号が変わった。コンテナを起動し直す |
| 権限エラー | `vvd jtag-rules --install` の後、ケーブルを挿し直す |
