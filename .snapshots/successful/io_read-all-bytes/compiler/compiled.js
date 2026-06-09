"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) => {
    return a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];
  };

  const __entryArgEither = (arg) => {
    if (arg.length > 134217728) {
      return [3, [589989748, [19]]];
    }
    for (let i = 0; i < arg.length; i++) {
      const c = arg.charCodeAt(i);
      if (c >= 0xD800 && c <= 0xDBFF) {
        if (i + 1 >= arg.length) {
          return [3, [502975519, [20]]];
        }
        const next = arg.charCodeAt(i + 1);
        if (next < 0xDC00 || next > 0xDFFF) {
          return [3, [502975519, [20]]];
        }
        i++;
      } else {
        if (c >= 0xDC00 && c <= 0xDFFF) {
          return [3, [502975519, [20]]];
        }
      }
    }
    return [4, arg];
  };

  const __getArgs = () => {
    const args = process.argv.slice(2);
    let list = [13];
    for (let i = args.length - 1; i >= 0; i--) {
      const v = __entryArgEither(args[i]);
      if (v[0] !== 4) {
        return v;
      }
      list = [14, v[1], list];
    }
    return [4, list];
  };

  const __stdinReadAll = () => {
    let s;
    try {
      s = new TextDecoder("utf-8", {fatal: true, ignoreBOM: true}).decode(
        require("fs").readFileSync(0)
      );
    } catch (e) {
      return [3, [3239958583, [21]]];
    }
    if (s.length > 134217728) {
      return [3, [589989748, [19]]];
    }
    return [4, s];
  };

  const __stdinReadAllBytes = () => {
    const buf = require("fs").readFileSync(0);
    let list = [13];
    for (let i = buf.length - 1; i >= 0; i--) {
      list = [14, buf[i], list];
    }
    return list;
  };

  const v__lam_12 = (v_b, v_restHex) => {
    return __concat(v_b.toString(16).padStart(2, "0"), v_restHex);
  };

  const v__io_stdinReadAllBytes_cont = (v_bytes) => {
    return [5, v_bytes];
  };

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
          case 23: {
            return v__x;
          }
          case 24: {
            const v__pk_24 = __s[1];
            const v_b = __s[2];
            const __t0 = v__pk_24;
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
            const __t1 = (v_bytes[0] = 24, v_bytes[1] = v__k, v_bytes[2] = v_b, v_bytes);
            v_bytes = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v_bytesToHexStringNoPrefix = (v_bytes) => {
    return v__cps_bytesToHexStringNoPrefix(v_bytes, [23]);
  };

  const v__lam_13 = (v_bytes) => {
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
          case 25: {
            return v__x;
          }
          case 26: {
            const v__pk_26 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_26;
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
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_1(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 26, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_1(v__k, [8, [15, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_1(v__k, [9, [16, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_1(v__k, [10, [17, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_1 = (v_io) => {
    return v__cps__df_andThenIO_1(v_io, [25]);
  };

  const v__apply__scc__apply1__df__lam_0_2__df__lam_1_3__df__lam_2_4 = (
    v__k,
    v__x
  ) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 27: {
            return v__x;
          }
          case 28: {
            const v__pk_28 = __s[1];
            const __t0 = v__pk_28;
            const __t1 = v__df_andThenIO_1(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 29: {
            const v__pk_29 = __s[1];
            const __t0 = v__pk_29;
            const __t1 = v__df_andThenIO_1(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
          case 30: {
            const v__pk_30 = __s[1];
            const __t0 = v__pk_30;
            const __t1 = v__df_andThenIO_1(v__x);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_0_2__df__lam_1_3__df__lam_2_4 = (
    v__args,
    v__k
  ) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 19: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 15: {
                  const v__cap15_0 = __s[1];
                  const __t0 = (v__args[0] = 20, v__args[1] = v__cap15_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 16: {
                  const v__cap16_0 = __s[1];
                  const __t0 = (v__args[0] = 21, v__args[1] = v__cap16_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 17: {
                  const v__cap17_0 = __s[1];
                  const __t0 = (v__args[0] = 22, v__args[1] = v__cap17_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 18: {
                  return v__apply__scc__apply1__df__lam_0_2__df__lam_1_3__df__lam_2_4(
                    v__k,
                    v__io_stdinReadAllBytes_cont(v__arg0)
                  );
                }
              }
            }
          }
          case 20: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 19, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [28, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 21: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 19, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [29, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 22: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 19, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [30, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_0_2__df__lam_1_3__df__lam_2_4 = (v__args) => {
    return v__cps__scc__apply1__df__lam_0_2__df__lam_1_3__df__lam_2_4(
      v__args,
      [27]
    );
  };

  const v__apply1 = (v__cl, v__arg0) => {
    return v__scc__apply1__df__lam_0_2__df__lam_1_3__df__lam_2_4(
      [19, v__cl, v__arg0]
    );
  };

  const v_runIO = (v_io) => {
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
          case 8: {
            const v_cont = __s[1];
            const __t0 = v__apply1(v_cont, __getArgs());
            v_io = __t0;
            continue;
          }
          case 9: {
            const v_cont = __s[1];
            const __t0 = v__apply1(v_cont, __stdinReadAll());
            v_io = __t0;
            continue;
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

  const main = v__df_andThenIO_1([10, [18]]);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
