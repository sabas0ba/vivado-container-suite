---
title: 07 JTAG
description: host、remote、USBによるJTAG接続とdevice書き込み
---

# 07 JTAG

## 3 種類の転送方式

`--jtag` / `VVD_JTAG_MODE` で指定する。

| 値 | `hw_server` の場所 | コンテナに渡す権限 |
|---|---|---|
| `host` (既定) | ホスト | なし。TCP 接続のみを行う |
| `remote:HOST[:PORT]` | 指定したマシン | なし。TCP 接続のみを行う |
| `usb` | コンテナ内 | 該当する USB デバイスノードのみを渡す |
| `none` | — | — |

既定の `host` が最も安全であり、通常はこれを使用する。コンテナにはデバイスも
ケーパビリティも一切渡らない。`--privileged` はいずれのモードでも使用しない。

## host モード

ホスト上で `hw_server` を起動し、コンテナからそこへ TCP で接続する。

```sh
# ホスト側 (一度だけ)
source /tools/Xilinx/Vivado/2025.2/settings64.sh
hw_server &
```

```sh
vvd program                    # 既定でこの経路を使用する
vvd program --list             # スキャンチェーンの列挙のみを行う
```

コンテナ内からは `host.docker.internal` (docker) または
`host.containers.internal` (podman) で解決される。docker では
`--add-host ...:host-gateway` が自動的に付与される。

ホストに Vivado が導入されていない場合は、USB を渡したコンテナで `hw_server` を
起動し、そのポートを公開できる。

```sh
vvd hw-server                       # 127.0.0.1:3121 で待ち受ける
vvd hw-server --bind 0.0.0.0        # 他マシンからも到達可能にする (誰でも書き込める点に注意)
```

## remote モード

ラボの共有マシンや CI のハードウェアランナーへ接続する場合に使用する。

```sh
vvd --jtag remote:lab-01.example.com:3121 program
```

```conf
# vvd.local.conf
VVD_JTAG_MODE=remote:lab-01.example.com
VVD_HW_SERVER_PORT=3121
```

## usb モード

ケーブルをコンテナへ直接渡す方式である。簡便だが、`host` モードより広い権限を
必要とする。

```sh
vvd --jtag usb program
```

`lsusb` の出力を参照し、既知のベンダ ID を持つデバイスの
`/dev/bus/usb/<bus>/<dev>` のみを `--device` で渡す。

| VID | ケーブル |
|---|---|
| `0403` | FTDI 系。Digilent HS1/HS2/HS3、JTAG-SMT2/SMT3、Arty/Nexys のオンボード |
| `03fd` | Xilinx Platform Cable USB / USB II (DLC9, DLC10) |
| `1443` | Digilent (旧 VID) |
| `1d50` | 一部のオープンハードウェアのアダプタ |

制約として、USB のバス番号およびデバイス番号は抜き差しによって変化する。ケーブルを
接続し直した場合はコンテナを再起動する必要がある。これを回避するには `host` モードを
使用するか、次のように USB ツリー全体を明示的に渡す。

```sh
VVD_JTAG_USB_ALL=1 vvd --jtag usb program     # 全 USB デバイスが見える (警告を表示する)
```

### udev ルール

デバイスノードを一般ユーザで開けるようにするための設定である。ホスト側の設定で
あり、これによって Vivado もコンテナも root で実行する必要がなくなる。

```sh
vvd jtag-rules --print     # 内容を確認する
vvd jtag-rules --install   # /etc/udev/rules.d/ に導入する (sudo)
vvd jtag-rules --list      # 現在接続されているケーブルを表示する
```

導入後はケーブルを接続し直す。ルールは `uaccess` タグ (ローカルログインセッションの
ユーザに付与される) と `plugdev` グループの両方を設定するため、いずれの運用にも
対応する。

## デバイスへの書き込み

```sh
vvd program                                 # build/<top>.bit
vvd program --bit build/other.bit
vvd program --target xc7a35t_0              # スキャンチェーンに複数デバイスがある場合
vvd program --probes build/blinky.ltx       # ILA/VIO のプローブを指定する
vvd program --list                          # 列挙のみ
```

`tcl/program.tcl` が `connect_hw_server` → `open_hw_target` →
`program_hw_devices` を実行し、最後に DONE ビットを確認する。到達できない場合や
ターゲットが存在しない場合は、原因と対処方法を示して失敗する。

## 確認

```sh
vvd doctor                   # hw_server の待ち受け、ケーブル、パーミッションを検査する
vvd selftest --stage jtag    # 実際に接続してスキャンチェーンを読み取る
```

`vvd selftest` の JTAG ステージは、ケーブルが接続されていない場合や `hw_server` が
起動していない場合、失敗ではなく skip として扱う。ハードウェアの有無によって CI が
失敗しないようにするためである。

## よくあるエラー

| 症状 | 対処 |
|---|---|
| `cannot reach hw_server at TCP:host.docker.internal:3121` | ホストで `hw_server` が起動していない。`vvd doctor` で確認できる |
| `no JTAG target is attached` | ケーブル、ボードの電源、udev ルールを確認する |
| `no JTAG cable found on the USB bus` | `vvd jtag-rules --list` で認識状況を確認する。接続し直した場合はコンテナを再起動する |
| 抜き差し後に動作しない (usb モード) | デバイス番号が変化している。コンテナを再起動する |
| 権限エラー | `vvd jtag-rules --install` を実行し、ケーブルを接続し直す |
