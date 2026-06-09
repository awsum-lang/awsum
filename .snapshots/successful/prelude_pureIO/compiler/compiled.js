"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
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

  const v_pureIO = (v_x) => {
    return [5, v_x];
  };

  const v__cps__scc__apply1__df_bindIOAfterArgs_1__df_bindIOAfterStdinBytes_3__df_bindIOAfterStdinString_2 = (
    v__args,
    v__k
  ) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 14: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 11: {
                  const v__cap11_0 = __s[1];
                  const __t0 = (v__args[0] = 15, v__args[1] = v__cap11_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 12: {
                  const v__cap12_0 = __s[1];
                  const __t0 = (v__args[0] = 16, v__args[1] = v__cap12_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 13: {
                  const v__cap13_0 = __s[1];
                  const __t0 = (v__args[0] = 17, v__args[1] = v__cap13_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
              }
            }
          }
          case 15: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 14, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [21, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 16: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 14, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [22, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 17: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 14, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [23, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df_bindIOAfterArgs_1__df_bindIOAfterStdinBytes_3__df_bindIOAfterStdinString_2 = (
    v__args
  ) => {
    return v__cps__scc__apply1__df_bindIOAfterArgs_1__df_bindIOAfterStdinBytes_3__df_bindIOAfterStdinString_2(
      v__args,
      [20]
    );
  };

  const v__bi_IO_Stdout_print = (v__x0) => {
    return [7, v__x0, [5, [0]]];
  };

  const v__apply1 = (v__cl, v__arg0) => {
    return v__scc__apply1__df_bindIOAfterArgs_1__df_bindIOAfterStdinBytes_3__df_bindIOAfterStdinString_2(
      [14, v__cl, v__arg0]
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

  const v__apply__df_bindIO_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 18: {
            return v__x;
          }
          case 19: {
            const v__pk_19 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_19;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_bindIO_0 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_bindIO_0(v__k, v__bi_IO_Stdout_print(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_bindIO_0(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 19, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_bindIO_0(v__k, [8, [11, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_bindIO_0(v__k, [9, [13, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_bindIO_0(v__k, [10, [12, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_bindIO_0 = (v_io) => {
    return v__cps__df_bindIO_0(v_io, [18]);
  };

  const main = v__df_bindIO_0(v_pureIO("from pureIO"));

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
