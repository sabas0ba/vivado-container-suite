# blinky

`vivado-container-suite` の動作確認用サンプル。Digilent Arty A7-35T 向けだが、
`vvd.conf` の `VVD_PART` と `constr/blinky.xdc` を書き換えれば任意のボードで動く。

```sh
vvd -C examples/blinky sim        # 論理シミュレーション (ライセンス不要)
vvd -C examples/blinky flow       # 合成 → 配置配線 → ビットストリーム
vvd -C examples/blinky program    # JTAG 書き込み
```

`sim` はライセンス不要で走るので、コンテナが正しく組めているかを最短で確認できる。
