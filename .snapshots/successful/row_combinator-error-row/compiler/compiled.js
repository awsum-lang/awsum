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

  const v_ob = [4, 5 | 0];

  const v_oa = [3, [24]];

  const v_de = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 332136403: {
                const v__a = __s[1];
                return "A";
              }
              case 348914022: {
                const v__b = __s[1];
                return "B";
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
  };

  const v_const = (v_x, v__y) => {
    return v_x;
  };

  const v__lift_20 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [348914022, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v__lam_18 = (v__n) => {
    return v_ob;
  };

  const v__df__rowmono_1_andThenEither_1 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [332136403, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_20(v__lam_18(v_a));
        }
      }
    }
  };

  const v_c2 = v__df__rowmono_1_andThenEither_1(v_oa);

  const v__lam_19 = (v__u) => {
    return [7, v_de(v_c2), [5, [0]]];
  };

  const v__df__rowmono_0_bindEither_0 = (
    v_x,
    v__df__rowmono_0_bindEither_0_cap1_0
  ) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [332136403, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_20(v_const(v__df__rowmono_0_bindEither_0_cap1_0, v_a));
        }
      }
    }
  };

  const v_c1 = v__df__rowmono_0_bindEither_0(v_oa, v_ob);

  const v__cps__scc__apply1__df__lam_5_3__df__lam_6_4__df__lam_7_5__lift_2__lift_3__lift_4 = (
    v__args,
    v__k
  ) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 31: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 25: {
                  const v__cap25_0 = __s[1];
                  const __t0 = (v__args[0] = 32, v__args[1] = v__cap25_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 26: {
                  const v__cap26_0 = __s[1];
                  const __t0 = (v__args[0] = 33, v__args[1] = v__cap26_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 27: {
                  const v__cap27_0 = __s[1];
                  const __t0 = (v__args[0] = 34, v__args[1] = v__cap27_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 28: {
                  const v__cap28_0 = __s[1];
                  const __t0 = (v__args[0] = 35, v__args[1] = v__cap28_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 29: {
                  const v__cap29_0 = __s[1];
                  const __t0 = (v__args[0] = 36, v__args[1] = v__cap29_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 30: {
                  const v__cap30_0 = __s[1];
                  const __t0 = (v__args[0] = 37, v__args[1] = v__cap30_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
              }
            }
          }
          case 32: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 31, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [43, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 33: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 31, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [44, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 34: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 31, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [45, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 35: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 31, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [46, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 36: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 31, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [47, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 37: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 31, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [48, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_5_3__df__lam_6_4__df__lam_7_5__lift_2__lift_3__lift_4 = (
    v__args
  ) => {
    return v__cps__scc__apply1__df__lam_5_3__df__lam_6_4__df__lam_7_5__lift_2__lift_3__lift_4(
      v__args,
      [42]
    );
  };

  const v__apply1 = (v__cl, v__arg0) => {
    return v__scc__apply1__df__lam_5_3__df__lam_6_4__df__lam_7_5__lift_2__lift_3__lift_4(
      [31, v__cl, v__arg0]
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

  const v__apply__lift_1 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 38: {
            return v__x;
          }
          case 39: {
            const v__pk_39 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_39;
            const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__lift_1 = (v___input, v__k) => {
    while (true) {
      {
        const __s = v___input;
        switch (__s[0]) {
          case 5: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [5, v___f0]);
          }
          case 6: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [6, v___f0]);
          }
          case 7: {
            const v___f0 = __s[1];
            const v___f1 = __s[2];
            const __t0 = v___f1;
            const __t1 = (v___input[0] = 39, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [8, [28, v___f0]]);
          }
          case 9: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [9, [29, v___f0]]);
          }
          case 10: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [10, [30, v___f0]]);
          }
        }
      }
    }
  };

  const v__lift_1 = (v___input) => {
    return v__cps__lift_1(v___input, [38]);
  };

  const v__apply__df_andThenIO_2 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 40: {
            return v__x;
          }
          case 41: {
            const v__pk_41 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_41;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_2 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_2(v__k, v__lift_1(v__lam_19(v_a)));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_2(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 41, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_2(v__k, [8, [25, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_2(v__k, [9, [26, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_2(v__k, [10, [27, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_2 = (v_io) => {
    return v__cps__df_andThenIO_2(v_io, [40]);
  };

  const main = v__df_andThenIO_2([7, v_de(v_c1), [5, [0]]]);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
