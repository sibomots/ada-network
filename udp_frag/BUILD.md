# Building udp_frag

## Host (Linux)

```sh
gprbuild -p -P udp_frag.gpr
```

Without gprbuild:

```sh
mkdir -p obj bin
for m in udp_frag_send udp_frag_recv; do
  gnatmake -gnat2012 -gnatwa -gnatVa -gnata -gnato -O1 -g \
           -aIsrc -D obj src/$m.adb -o bin/$m -bargs -Es
done
```

## VxWorks 7 RTP (GNAT Pro for VxWorks)

1. Open a Wind River environment shell (`wrenv -p vxworks-7`) with your VSB configured per the GNAT Pro VxWorks install notes.
2. Build:

   ```sh
   gprbuild -p -P udp_frag.gpr --target=aarch64-wrs-vxworks7r2 --RTS=rtp
   ```

   Substitute your triple (`arm-`, `ppc64-`, `x86_64-wrs-vxworks7r2`, ...), or set `Target` / `Runtime` in `udp_frag.gpr`.
3. Name outputs `.vxe` by renaming, or add to `udp_frag.gpr`:

   ```ada
   package Builder is
      for Executable_Suffix use ".vxe";
   end Builder;
   ```

The cross build has not been tested; only the host build has.

## Run

Use the same file on both ends.

```
udp_frag_recv.vxe 5000 -f /ram0/test.bin -a 10.0.0.2 -n 10
udp_frag_send.vxe 10.0.0.2 5000 /ram0/test.bin -c 10 -s 40000
```

From the C shell: `rtpSp "/ram0/udp_frag_recv.vxe 5000 -f /ram0/test.bin -a 10.0.0.2 -n 10"`
