# 05 フロー

## コマンド

```sh
vcs synth       # 合成
vcs impl        # 配置配線。合成済みチェックポイントが無ければ先に合成する
vcs bitstream   # ビットストリーム。実装済みでなければ先に実装する
vcs flow        # 上記すべてを Vivado 1 回の起動で
vcs sim         # 論理シミュレーション
```

`flow` は Vivado の起動が 1 回で済むぶん速い (起動に 20〜40 秒かかる)。
段階的にデバッグするときは個別コマンドを使う。

## nonproject フロー (既定)

`.xpr` を作らず、チェックポイント (`.dcp`) を段階間の受け渡しに使う。
生成物がすべてファイルとして残り、再現性が高いので CI 向き。

```
sources ──synth_design──▶ post_synth.dcp ──opt/place/phys_opt/route──▶ post_route.dcp ──▶ <top>.bit
```

`tcl/flow.tcl` が実装している。各段階で `build/reports/` にレポートを書く。

| レポート | 内容 |
|---|---|
| `synth_utilization.rpt` / `impl_utilization.rpt` | リソース使用率 |
| `synth_timing.rpt` / `impl_timing.rpt` | タイミングサマリ |
| `impl_drc.rpt` | DRC |
| `impl_power.rpt` | 電力見積 |
| `impl_io.rpt` | I/O 割り当て |

### タイミング未達は失敗として扱う

Vivado 自体はタイミング未達でも終了コード 0 を返す。CI ではこれが致命的なので、
`vcs impl` は WNS/WHS が負なら**ビルドを失敗させる**。

```sh
VCS_ALLOW_TIMING_VIOLATION=1 vcs impl     # 承知のうえで進める
```

### フック

```conf
VCS_PRE_TCL=scripts/pre_synth.tcl     # ソース読み込み後、synth_design の前
VCS_POST_TCL=scripts/post_bit.tcl     # write_bitstream の後
```

フックの中では `tcl/lib.tcl` のヘルパ (`vcs::env`, `vcs::build_dir`, ...) が
使える状態になっている。

## project フロー

既存の `.xpr` が正であるプロジェクト向け。

```conf
VCS_FLOW_MODE=project
VCS_XPR=hw/blinky.xpr
```

`launch_runs synth_1` / `launch_runs impl_1 -to_step write_bitstream` を駆動し、
`wait_on_run` で待ち、生成された `.bit` / `.ltx` を `build/` に集める。
最新の run はスキップされる (`PROGRESS == 100%` かつ `NEEDS_REFRESH == 0`)。

## シミュレーション

```sh
vcs sim                       # ヘッドレス実行
vcs sim --gui                 # xsim の波形ビューアを開く
vcs sim --top tb_other        # トップを一時的に差し替え
vcs sim --time 500us          # 実行時間
vcs sim --no-waves            # 波形を記録しない (速い)
```

Vivado プロジェクトを作らず `xvlog` / `xvhdl` / `xelab` / `xsim` を直接叩くので、
起動が 1 秒程度で済む。`unisims_ver` / `unimacro_ver` / `secureip` は常にリンクされる。

### 合否判定

`xsim` はテストベンチが `$fatal` してもプロセスとしては 0 で終わる。
`container/sim.sh` はログを走査し、`Error` / `Fatal` / `$fatal` / `Failure:` /
`*** FAILED` / `ASSERTION FAILED` のいずれかが出ていれば失敗にする。

テストベンチ側では、失敗時に `*** FAILED:` で始まる行を出せば確実に拾われる。
同梱の `examples/blinky/sim/tb_blinky.v` と `container/smoke/tb_smoke.v` が
その書き方の例になっている。

## 生成物のオーナーシップ

`/work` に書かれるファイルは呼び出したユーザの uid/gid で作られる。
rootful docker では entrypoint が root から降格し、rootless podman では
`--userns=keep-id` が同じ結果を与える。

```sh
vcs selftest --stage identity     # 実際に確認する
```

`VCS_USER_MODE=root` にすると降格しない (デバッグ用。生成物が root 所有になる)。

## 掃除

```sh
vcs clean          # build/ を消す (確認あり)
vcs clean -f       # 確認なし
vcs clean --all    # ツールキャッシュも消す
```

`VCS_BUILD_DIR` が絶対パスや `..` を含む場合、`vcs clean` は拒否する。

## 任意の Tcl を走らせる

```sh
vcs run scripts/report_all.tcl              # vivado -mode batch -source
vcs run scripts/sweep.tcl arg1 arg2         # -tclargs で渡る
vcs tcl                                     # 対話コンソール
```

スクリプトはプロジェクトルート配下に無ければならない (コンテナから見えないため)。
`tcl/lib.tcl` を `source` すればヘルパが使える。

```tcl
source [file join $::env(VCS_CONTAINER_TCL) lib.tcl]
vcs::read_sources
vcs::info_ "part is [vcs::part]"
```
