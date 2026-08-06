# 04 ライセンス

原則として、ライセンスはイメージに含めない。コンテナの起動側が実行時に注入する。

## 4 種類の指定方式

`VVD_LICENSE` (または `--license`) の値によって決まる。

| 形式 | 例 | コンテナへの受け渡し |
|---|---|---|
| 浮動ライセンスサーバ | `2100@license.example.com` | 環境変数のみを設定し、mount は行わない |
| 複数サーバ | `2100@a.example.com:2100@b.example.com` | 同上 (Vivado が順に試行する) |
| ノードロックファイル | `/home/me/Xilinx.lic` | `/opt/vvd/license/Xilinx.lic` に read-only mount |
| ディレクトリ | `dir:/home/me/licenses` | `/opt/vvd/license` に read-only mount |
| 無効 | `none` | 何も渡さない |

いずれの場合も `XILINXD_LICENSE_FILE` がコンテナ内に設定される。

## 解決順序

`VVD_LICENSE` が未設定の場合、次の順序で自動的に探索する。

1. ホストの `XILINXD_LICENSE_FILE` 環境変数
2. `~/.Xilinx/Xilinx.lic`
3. なし (`none`)

加えて `~/.Xilinx` (または `VVD_XILINX_DOTDIR`) が存在する場合、コンテナの
`$HOME/.Xilinx` に read-only で mount される。このディレクトリには、インストール済み
ライセンスのメタデータやツール設定が格納されている。

## 方式の選択

**浮動ライセンス (推奨)**
ファイルがコンテナに渡らないため最も安全である。ライセンスサーバへ TCP で到達できる
ことが条件となる。コンテナは既定でホストのネットワークを共有しないため、社内 VPN
経由のライセンスサーバに到達できない場合は `VVD_NETWORK=host` を検討する。

```conf
# vvd.local.conf
VVD_LICENSE=2100@license.example.com
```

**ノードロック**
オフライン環境および個人ライセンス向けである。read-only mount のため、コンテナ内から
変更されることはない。

```conf
VVD_LICENSE=/home/me/.Xilinx/Xilinx.lic
```

**CI**
シークレットからファイルを書き出すか、ライセンスサーバのアドレスを変数で渡す。
ファイルを書き出す場合は、ジョブ終了時に確実に削除する。

```yaml
- name: Write the license
  run: |
    umask 077
    printf '%s' "${{ secrets.XILINX_LIC }}" > "$RUNNER_TEMP/Xilinx.lic"
- name: Build
  env:
    VVD_LICENSE: ${{ runner.temp }}/Xilinx.lic
  run: vvd flow
- name: Shred the license
  if: always()
  run: rm -f "$RUNNER_TEMP/Xilinx.lic"
```

## 確認する

```sh
vvd doctor
```

- サーバ形式の場合は、ホストからポートに到達できるかを実際に試行する
- ファイル形式の場合は、読み取り可能かを確認する

```sh
vvd selftest --stage license   # コンテナ内から到達できるかを確認する
vvd selftest --stage synth     # 実際に合成が成功するかを確認する
```

`license` ステージが検査するのは到達性のみである。ライセンスが機能していることの
最終的な確認は、小規模な設計を実際に合成できることであり、これを行うのが `synth`
ステージである。

## 漏洩防止

- `docker/Dockerfile` の最終ステップで `*.lic` を探し、見つかればビルドを失敗させる
- `.dockerignore` が `**/*.lic` と `vvd.local.conf` をビルドコンテキストから除外する
- `.gitignore` が `vvd.local.conf` をコミット対象から除外する
- CI がビルドしたイメージに対して改めて `.lic` の有無を検査する
  (`.github/workflows/ci.yml`)

## よくあるエラー

| 症状 | 原因 |
|---|---|
| `ERROR: [Common 17-345] ... no valid license` | ライセンス未注入、または期限切れ |
| ホストでは成功するがコンテナでは失敗する | サーバへ到達できていない。`vvd selftest --stage license` で確認し、`VVD_NETWORK=host` を検討する |
| ノードロックが機能しない | ライセンスは MAC アドレスに紐付く。既定ではコンテナの MAC が異なるため、`VVD_NETWORK=host` で解決する場合が多い |
| `Feature not licensed` | デバイスがそのエディションの対象外である。`vvd shell vivado -mode batch -source ...` で `get_parts` を確認する |
