"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const __stdinReadAllBytes = () => {
    const buf = require("fs").readFileSync(0);
    let list = [13];
    for (let i = buf.length - 1; i >= 0; i--) {
      list = [14, buf[i], list];
    }
    return list;
  };

  const v__lam_12 = (v_b, v_restHex) =>
    __concat(v_b.toString(16).padStart(2, "0"), v_restHex);

  const v__io_stdinReadAllBytes_cont = v_bytes => [5, v_bytes];

  const v__df_bindEither_0 = (v_x, v__df_bindEither_0_cap1_0) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_e];
        }
        case 4: {
          const v_a = __s[1];
          return v__lam_12(v__df_bindEither_0_cap1_0, v_a);
        }
      }
    }
  };

  const v__apply_bytesToHexStringNoPrefix = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 19: {
            return v__x;
          }
          case 20: {
            const v__pk_20 = __s[1];
            const v_b = __s[2];
            const __t0 = v__pk_20;
            const __t1 = v__df_bindEither_0(v__x, v_b);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps_bytesToHexStringNoPrefix = (v_bytes, v__k) => {
    while (true) {
      {
        const __s = v_bytes;
        switch (__s[0]) {
          case 13: {
            return v__apply_bytesToHexStringNoPrefix(v__k, [4, ""]);
          }
          case 14: {
            const v_b = __s[1];
            const v_rest = __s[2];
            const __t0 = v_rest;
            const __t1 = (v_bytes[0] = 20, v_bytes[1] = v__k, v_bytes[2] = v_b, v_bytes);
            v_bytes = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v_bytesToHexStringNoPrefix = v_bytes =>
    v__cps_bytesToHexStringNoPrefix(v_bytes, [19]);

  const v__lam_13 = v_bytes => {
    {
      const __s = v_bytesToHexStringNoPrefix(v_bytes);
      switch (__s[0]) {
        case 3: {
          const v__e = __s[1];
          return [7, "TOO_LONG", [5, [0]]];
        }
        case 4: {
          const v_hex = __s[1];
          return [7, v_hex, [5, [0]]];
        }
      }
    }
  };

  const v__apply__df_andThenIO_1 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 21: {
            return v__x;
          }
          case 22: {
            const v__pk_22 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_22;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_1 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_1(v__k, v__lam_13(v_a));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 22, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_1(v__k, [10, [15, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_1 = v_io => v__cps__df_andThenIO_1(v_io, [21]);

  const v__apply__scc__apply1__df__lam_2_4 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 23: {
            return v__x;
          }
          case 24: {
            const v__pk_24 = __s[1];
            const __t0 = v__pk_24;
            const __t1 = v__df_andThenIO_1(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_2_4 = (v__args, v__k) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 17: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 15: {
                  const v__cap15_0 = __s[1];
                  const __t0 = (v__args[0] = 18, v__args[1] = v__cap15_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 16: {
                  return v__apply__scc__apply1__df__lam_2_4(
                    v__k,
                    v__io_stdinReadAllBytes_cont(v__arg0)
                  );
                }
              }
            }
          }
          case 18: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 17, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [24, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_2_4 = v__args =>
    v__cps__scc__apply1__df__lam_2_4(v__args, [23]);

  const v__apply1 = (v__cl, v__arg0) =>
    v__scc__apply1__df__lam_2_4([17, v__cl, v__arg0]);

  const v_runIO = v_io => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_u = __s[1];
            return v_u;
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            {
              const __s = __print(v_s);
              switch (__s[0]) {
                case 0: {
                  const __t0 = v_next;
                  v_io = __t0;
                  continue;
                }
              }
            }
          }
          case 10: {
            const v_cont = __s[1];
            const __t0 = v__apply1(v_cont, __stdinReadAllBytes());
            v_io = __t0;
            continue;
          }
        }
      }
    }
  };

  const main = v__df_andThenIO_1([10, [16]]);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
