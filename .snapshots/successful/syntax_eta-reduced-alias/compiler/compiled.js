"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __entryArgEither = arg => {
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

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 21: {
          return v__x;
        }
        case 22: {
          const v__pk_22 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_22;
          continue;
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_0 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_0(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_0(
            v__k,
            [7, "INPUT_ERROR", [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [22, v__k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont = v_io[1];
          return v__apply__df_handleErrorIO_0(v__k, [8, [16, v_cont]]);
        }
      }
    }
  };

  const v__apply__df__rowmono_0_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 23: {
          return v__x;
        }
        case 24: {
          const v__pk_24 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_24;
          continue;
        }
      }
    }
  };

  const v__cps__df__rowmono_0_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df__rowmono_0_andThenIO_4(
            v__k,
            (v__inl4_args =>
              (s => {
                switch (s[0]) {
                  case 13: {
                    return [7, "NO_ARG", [5, [0]]];
                  }
                  case 14: {
                    return [7, v__inl4_args[1], [5, [0]]];
                  }
                }
              })(v__inl4_args))(v_io[1])
          );
        }
        case 6: {
          return v__apply__df__rowmono_0_andThenIO_4(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [24, v__k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont = v_io[1];
          return v__apply__df__rowmono_0_andThenIO_4(v__k, [8, [15, v_cont]]);
        }
      }
    }
  };

  const v__apply__scc__apply1__df__lam_13_5__df__lam_9_1 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 25: {
          return v__x;
        }
        case 26: {
          v__k = v__k[1];
          v__x = v__cps__df__rowmono_0_andThenIO_4(v__x, [23]);
          continue;
        }
        case 27: {
          v__k = v__k[1];
          v__x = v__cps__df_handleErrorIO_0(v__x, [21]);
          continue;
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_13_5__df__lam_9_1 = (v__args, v__k) => {
    while (true) {
      switch (v__args[0]) {
        case 18: {
          const v__cl = v__args[1];
          const v__arg0 = v__args[2];
          switch (v__cl[0]) {
            case 15: {
              v__args = (v__args[0] = 19, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 16: {
              v__args = (v__args[0] = 20, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 17: {
              return v__apply__scc__apply1__df__lam_13_5__df__lam_9_1(
                v__k,
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return [6, v__arg0[1]];
                    }
                    case 4: {
                      return [5, v__arg0[1]];
                    }
                  }
                })(v__arg0)
              );
            }
          }
        }
        case 19: {
          v__args = (v__args[0] = 18, v__args);
          v__k = [26, v__k];
          continue;
        }
        case 20: {
          v__args = (v__args[0] = 18, v__args);
          v__k = [27, v__k];
          continue;
        }
      }
    }
  };

  const v_runIO = v_io => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_io[1];
        }
        case 7: {
          const v__inl7_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 8: {
          const __t0 = (v__inl8__arg0 =>
            v__cps__scc__apply1__df__lam_13_5__df__lam_9_1(
              [18, v_io[1], v__inl8__arg0],
              [25]
            ))(__getArgs());
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_handleErrorIO_0(
    v__cps__df__rowmono_0_andThenIO_4([8, [17]], [23]),
    [21]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
