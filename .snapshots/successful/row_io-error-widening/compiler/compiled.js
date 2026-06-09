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

  const v_h = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 63694499: {
          const v__a = __s[1];
          return [7, "h-E1", [5, [0]]];
        }
      }
    }
  };

  const v_failIO = (v_e) => {
    return [6, v_e];
  };

  const v_act = v_failIO([63694499, [24]]);

  const v__cps__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3 = (
    v__args,
    v__k
  ) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 28: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 25: {
                  const v__cap25_0 = __s[1];
                  const __t0 = (v__args[0] = 29, v__args[1] = v__cap25_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 26: {
                  const v__cap26_0 = __s[1];
                  const __t0 = (v__args[0] = 30, v__args[1] = v__cap26_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 27: {
                  const v__cap27_0 = __s[1];
                  const __t0 = (v__args[0] = 31, v__args[1] = v__cap27_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
              }
            }
          }
          case 29: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 28, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [35, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 30: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 28, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [36, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 31: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 28, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [37, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3 = (
    v__args
  ) => {
    return v__cps__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3(
      v__args,
      [34]
    );
  };

  const v__apply1 = (v__cl, v__arg0) => {
    return v__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3(
      [28, v__cl, v__arg0]
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

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 32: {
            return v__x;
          }
          case 33: {
            const v__pk_33 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_33;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_0 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, v_h(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 33, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [8, [25, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [9, [26, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [10, [27, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_0 = (v_io) => {
    return v__cps__df_handleErrorIO_0(v_io, [32]);
  };

  const main = v__df_handleErrorIO_0(v_act);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
