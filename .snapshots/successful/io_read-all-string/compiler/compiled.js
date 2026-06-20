"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
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

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 28: {
          return v__x;
        }
        case 29: {
          const v__pk_29 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_29;
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
            (s => {
              switch (s[0]) {
                case 589989748: {
                  return [7, "STRING_TOO_LONG", [5, [0]]];
                }
                case 3239958583: {
                  return [7, "INVALID_UTF8", [5, [0]]];
                }
              }
            })(v_io[1])
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [29, v__k, v_s];
          v_io = v_next;
          continue;
        }
        case 9: {
          const v_cont = v_io[1];
          return v__apply__df_handleErrorIO_0(v__k, [9, [22, v_cont]]);
        }
      }
    }
  };

  const v__apply__df__rowmono_0_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 30: {
          return v__x;
        }
        case 31: {
          const v__pk_31 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_31;
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
            [7, v_io[1], [5, [0]]]
          );
        }
        case 6: {
          return v__apply__df__rowmono_0_andThenIO_4(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [31, v__k, v_s];
          v_io = v_next;
          continue;
        }
        case 9: {
          const v_cont = v_io[1];
          return v__apply__df__rowmono_0_andThenIO_4(v__k, [9, [23, v_cont]]);
        }
      }
    }
  };

  const v__apply__scc__apply1__df__lam_10_2__df__lam_14_6 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 32: {
          return v__x;
        }
        case 33: {
          v__k = v__k[1];
          v__x = v__cps__df_handleErrorIO_0(v__x, [28]);
          continue;
        }
        case 34: {
          v__k = v__k[1];
          v__x = v__cps__df__rowmono_0_andThenIO_4(v__x, [30]);
          continue;
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_10_2__df__lam_14_6 = (v__args, v__k) => {
    while (true) {
      switch (v__args[0]) {
        case 25: {
          const v__cl = v__args[1];
          const v__arg0 = v__args[2];
          switch (v__cl[0]) {
            case 22: {
              v__args = (v__args[0] = 26, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 23: {
              v__args = (v__args[0] = 27, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 24: {
              return v__apply__scc__apply1__df__lam_10_2__df__lam_14_6(
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
        case 26: {
          v__args = (v__args[0] = 25, v__args);
          v__k = [33, v__k];
          continue;
        }
        case 27: {
          v__args = (v__args[0] = 25, v__args);
          v__k = [34, v__k];
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
          const v__inl4_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 9: {
          const __t0 = (() => {
            const v__inl5__arg0 = __stdinReadAll();
            return v__cps__scc__apply1__df__lam_10_2__df__lam_14_6(
              [25, v_io[1], v__inl5__arg0],
              [32]
            );
          })();
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_handleErrorIO_0(
    v__cps__df__rowmono_0_andThenIO_4([9, [24]], [30]),
    [28]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
