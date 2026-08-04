# 04 ライセンス

原則: **ライセンスはイメージに入らない。** コンテナ起動側が実行時に注入する。

## 4 つの指定方式

`VCS_LICENSE` (または `--license`) の値で決まる。

| 形式 | 例 | コンテナへの渡り方 |
|---|---|---|
| 浮動ライセンスサーバ | `2100@license.example.com` | 環境変数のみ。mount なし |
| 複数サーバ | `2100@a.example.com:2100@b.example.com` | 同上 (Vivado が順に試す) |
| ノードロックファイル | `/home/me/Xilinx.lic` | `/opt/vcs/license/Xilinx.lic` に read-only mount |
| ディレクトリ | `dir:/home/me/licenses` | `/opt/vcs/license` に read-only mount |
| 無効 | `none` | 何も渡さない |

いずれの場合も `XILINXD_LICENSE_FILE` がコンテナ内に設定される。

## 解決順序

`VCS_LICENSE` が未設定なら、次の順に自動で探す。

1. ホストの `XILINXD_LICENSE_FILE` 環境変数
2. `~/.Xilinx/Xilinx.lic`
3. なし (`none`)

加えて `~/.Xilinx` (または `VCS_XILINX_DOTDIR`) が存在すれば、
コンテナの `$HOME/.Xilinx` に read-only で mount される。ここには
インストール済みライセンスのメタデータやツール設定が入っている。

## 使い分け

**浮動ライセンス (推奨)**
ファイルがコンテナに入らないので最も安全。ライセンスサーバへ TCP 到達できることが
条件。コンテナは既定でホストのネットワークを共有しないため、社内 VPN 越しの
ライセンスサーバに繋がらない場合は `VCS_NETWORK=host` を検討する。

```conf
# vcs.local.conf
VCS_LICENSE=2100@license.example.com
```

**ノードロック**
オフライン環境や個人ライセンス向け。read-only mount なので、コンテナ内から
書き換えられることはない。

```conf
VCS_LICENSE=/home/me/.Xilinx/Xilinx.lic
```

**CI**
シークレットからファイルを書き出すか、ライセンスサーバのアドレスを変数で渡す。
ファイルを書き出す場合は、ジョブ終了時に確実に消す。

```yaml
- name: Write the license
  run: |
    umask 077
    printf '%s' "${{ secrets.XILINX_LIC }}" > "$RUNNER_TEMP/Xilinx.lic"
- name: Build
  env:
    VCS_LICENSE: ${{ runner.temp }}/Xilinx.lic
  run: vcs flow
- name: Shred the license
  if: always()
  run: rm -f "$RUNNER_TEMP/Xilinx.lic"
```

## 確認する

```sh
vcs doctor
```

- サーバ形式なら、ホストからポートに到達できるかを実際に試す
- ファイル形式なら、読めるかを確認する

```sh
vcs selftest --stage license   # コンテナ内から到達できるか
vcs selftest --stage synth     # 実際に合成が通るか (本当の確認はこれ)
```

`license` ステージは到達性しか見ない。ライセンスが機能しているかどうかの
最終的な証明は、小さな設計が実際に合成できることであり、それが `synth` ステージ。

## 漏洩防止

- `docker/Dockerfile` の最終ステップで `*.lic` を探し、見つかればビルドを失敗させる
- `.dockerignore` が `**/*.lic` と `vcs.local.conf` をビルドコンテキストから除外する
- `.gitignore` が `vcs.local.conf` をコミット対象から外す
- CI がビルドしたイメージに対して改めて `.lic` の有無を検査する
  (`.github/workflows/ci.yml`)

## よくある失敗

| 症状 | 原因 |
|---|---|
| `ERROR: [Common 17-345] ... no valid license` | ライセンス未注入、または期限切れ |
| ホストでは通るがコンテナでは通らない | サーバへ到達できていない。`vcs selftest --stage license` で確認。`VCS_NETWORK=host` を検討 |
| ノードロックが効かない | ライセンスは MAC アドレス紐付け。既定ではコンテナの MAC が異なる。`VCS_NETWORK=host` で解決することが多い |
| `Feature not licensed` | デバイスがそのエディションの対象外。`vcs shell vivado -mode batch -source ...` で `get_parts` を確認 |
