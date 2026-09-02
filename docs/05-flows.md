---
title: 05 フロー
description: 合成、実装、bitstream生成、シミュレーションの実行方法
---

# 05 フロー

## コマンド

```sh
vvd synth       # 合成
vvd impl        # 配置配線。合成済みチェックポイントが無ければ先に合成する
vvd bitstream   # ビットストリーム。実装済みでなければ先に実装する
vvd flow        # 上記すべてを 1 回の Vivado 起動で実行する
vvd sim         # 論理シミュレーション
```

`flow` は Vivado の起動が 1 回で済むため高速である (起動には 20〜40 秒を要する)。
段階的にデバッグする場合は個別のコマンドを使用する。

## nonproject フロー (既定)

`.xpr` を生成せず、チェックポイント (`.dcp`) を段階間の受け渡しに使用する。
生成物がすべてファイルとして残り、再現性が高いため CI に適している。

```
sources ──synth_design──▶ post_synth.dcp ──opt/place/phys_opt/route──▶ post_route.dcp ──▶ <top>.bit
```

実装は `tcl/flow.tcl` にある。各段階で `build/reports/` にレポートを出力する。

| レポート | 内容 |
|---|---|
| `synth_utilization.rpt` / `impl_utilization.rpt` | リソース使用率 |
| `synth_timing.rpt` / `impl_timing.rpt` | タイミングサマリ |
| `impl_drc.rpt` | DRC |
| `impl_power.rpt` | 電力見積 |
| `impl_io.rpt` | I/O 割り当て |

### タイミング未達は失敗として扱う

Vivado はタイミング未達の場合でも終了コード 0 を返す。CI ではこの挙動が問題となる
ため、`vvd impl` は WNS/WHS が負の場合にビルドを失敗させる。

```sh
VVD_ALLOW_TIMING_VIOLATION=1 vvd impl     # 未達を許容して続行する
```

### フック

```conf
VVD_PRE_TCL=scripts/pre_synth.tcl     # ソース読み込み後、synth_design の前
VVD_POST_TCL=scripts/post_bit.tcl     # write_bitstream の後
```

フック内では `tcl/lib.tcl` のヘルパ (`vvd::env`、`vvd::build_dir` など) が
使用できる。

## project フロー

既存の `.xpr` を正とするプロジェクト向けのモードである。

```conf
VVD_FLOW_MODE=project
VVD_XPR=hw/blinky.xpr
```

`launch_runs synth_1` および `launch_runs impl_1 -to_step write_bitstream` を実行し、
`wait_on_run` で完了を待ち、生成された `.bit` / `.ltx` を `build/` に収集する。
最新の状態にある run はスキップする (`PROGRESS == 100%` かつ `NEEDS_REFRESH == 0`)。

## シミュレーション

```sh
vvd sim                       # ヘッドレス実行
vvd sim --gui                 # xsim の波形ビューアを開く
vvd sim --top tb_other        # トップモジュールを一時的に変更する
vvd sim --time 500us          # 実行時間を指定する
vvd sim --no-waves            # 波形を記録しない (高速)
```

Vivado プロジェクトを生成せず、`xvlog` / `xvhdl` / `xelab` / `xsim` を直接実行する
ため、起動は 1 秒程度で完了する。`unisims_ver` / `unimacro_ver` / `secureip` は
常にリンクされる。

### 合否判定

`xsim` は、テストベンチが `$fatal` を呼んだ場合でもプロセスとしては 0 で終了する。
そのため `container/sim.sh` はログを走査し、`Error` / `Fatal` / `$fatal` / `Failure:` /
`*** FAILED` / `ASSERTION FAILED` のいずれかが出力されていれば失敗として扱う。

テストベンチ側では、失敗時に `*** FAILED:` で始まる行を出力すれば確実に検出される。
同梱の `examples/blinky/sim/tb_blinky.v` および `container/smoke/tb_smoke.v` が
その記述例である。

## 生成物のオーナーシップ

`/work` に書き込まれるファイルは、呼び出したユーザの uid/gid で作成される。
rootful docker では entrypoint が root から権限を降格し、rootless podman では
`--userns=keep-id` が同一の結果をもたらす。

```sh
vvd selftest --stage identity     # 実際の所有者を確認する
```

`VVD_USER_MODE=root` を指定すると権限を降格しない。デバッグ用であり、生成物は
root 所有となる。

## 生成物の削除

```sh
vvd clean          # build/ を削除する (確認あり)
vvd clean -f       # 確認なし
vvd clean --all    # ツールキャッシュも削除する
```

`VVD_BUILD_DIR` が絶対パスまたは `..` を含む場合、`vvd clean` は実行を拒否する。

## 任意の Tcl スクリプトの実行

```sh
vvd run scripts/report_all.tcl              # vivado -mode batch -source
vvd run scripts/sweep.tcl arg1 arg2         # -tclargs として渡される
vvd tcl                                     # 対話コンソール
```

スクリプトはプロジェクトルート配下に配置する必要がある。それ以外の場所にある
ファイルはコンテナから参照できない。`tcl/lib.tcl` を `source` するとヘルパを
使用できる。

```tcl
source [file join $::env(VVD_CONTAINER_TCL) lib.tcl]
vvd::read_sources
vvd::info_ "part is [vvd::part]"
```
