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

  const v__apply__lift_13 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 35: {
          return v__x;
        }
        case 36: {
          const v__pk_36 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_36;
          continue;
        }
      }
    }
  };

  const v__cps__lift_13 = (v___input, v__k) => {
    while (true) {
      switch (v___input[0]) {
        case 5: {
          return v__apply__lift_13(v__k, v___input);
        }
        case 6: {
          const v___f0 = v___input[1];
          return v__apply__lift_13(v__k, [6, [348914022, v___f0]]);
        }
        case 7: {
          const v___f0 = v___input[1];
          const v___f1 = v___input[2];
          v__k = [36, v__k, v___f0];
          v___input = v___f1;
          continue;
        }
        case 8: {
          const v___f0 = v___input[1];
          return v__apply__lift_13(v__k, [8, [29, v___f0]]);
        }
      }
    }
  };

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 37: {
          return v__x;
        }
        case 38: {
          const v__pk_38 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_38;
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
                case 348914022: {
                  return [7, "EB", [5, [0]]];
                }
                case 502975519: {
                  return [7, "UNPAIRED_UTF16_SURROGATE", [5, [0]]];
                }
                case 589989748: {
                  return [7, "STRING_TOO_LONG", [5, [0]]];
                }
              }
            })(v_io[1])
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [38, v__k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont_u0 = v_io[1];
          return v__apply__df_handleErrorIO_0(v__k, [8, [25, v_cont_u0]]);
        }
      }
    }
  };

  const v__apply__df__rowmono_4_bindIO_8 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 41: {
          return v__x;
        }
        case 42: {
          const v__pk_42 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_42;
          continue;
        }
      }
    }
  };

  const v__cps__df__rowmono_4_bindIO_8 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df__rowmono_4_bindIO_8(
            v__k,
            v__cps__lift_13([6, [24]], [35])
          );
        }
        case 6: {
          return v__apply__df__rowmono_4_bindIO_8(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [42, v__k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont_u15 = v_io[1];
          return v__apply__df__rowmono_4_bindIO_8(v__k, [8, [27, v_cont_u15]]);
        }
      }
    }
  };

  const v__apply__df__rowmono_0_bindIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 39: {
          return v__x;
        }
        case 40: {
          const v__pk_40 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_40;
          continue;
        }
      }
    }
  };

  const v__cps__df__rowmono_0_bindIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df__rowmono_0_bindIO_4(
            v__k,
            [7, String(v_io[1]), [5, [0]]]
          );
        }
        case 6: {
          return v__apply__df__rowmono_0_bindIO_4(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [40, v__k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont_u9 = v_io[1];
          return v__apply__df__rowmono_0_bindIO_4(v__k, [8, [26, v_cont_u9]]);
        }
      }
    }
  };

  const v__apply__scc__apply1__df__lam_9_1__df__rowmono_1_bindIOAfterArgs_5__df__rowmono_5_bindIOAfterArgs_9__lift_14 = (
    v__k,
    v__x
  ) => {
    while (true) {
      switch (v__k[0]) {
        case 43: {
          return v__x;
        }
        case 44: {
          v__k = v__k[1];
          v__x = v__cps__df_handleErrorIO_0(v__x, [37]);
          continue;
        }
        case 45: {
          v__k = v__k[1];
          v__x = v__cps__df__rowmono_0_bindIO_4(v__x, [39]);
          continue;
        }
        case 46: {
          v__k = v__k[1];
          v__x = v__cps__df__rowmono_4_bindIO_8(v__x, [41]);
          continue;
        }
        case 47: {
          v__k = v__k[1];
          v__x = v__cps__lift_13(v__x, [35]);
          continue;
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_9_1__df__rowmono_1_bindIOAfterArgs_5__df__rowmono_5_bindIOAfterArgs_9__lift_14 = (
    v__args,
    v__k
  ) => {
    while (true) {
      switch (v__args[0]) {
        case 30: {
          const v__cl = v__args[1];
          const v__arg0 = v__args[2];
          switch (v__cl[0]) {
            case 25: {
              v__args = (v__args[0] = 31, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 26: {
              v__args = (v__args[0] = 32, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 27: {
              v__args = (v__args[0] = 33, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 28: {
              return v__apply__scc__apply1__df__lam_9_1__df__rowmono_1_bindIOAfterArgs_5__df__rowmono_5_bindIOAfterArgs_9__lift_14(
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
            case 29: {
              v__args = (v__args[0] = 34, v__args[1] = v__cl[1], v__args);
              continue;
            }
          }
        }
        case 31: {
          v__args = (v__args[0] = 30, v__args);
          v__k = [44, v__k];
          continue;
        }
        case 32: {
          v__args = (v__args[0] = 30, v__args);
          v__k = [45, v__k];
          continue;
        }
        case 33: {
          v__args = (v__args[0] = 30, v__args);
          v__k = [46, v__k];
          continue;
        }
        case 34: {
          v__args = (v__args[0] = 30, v__args);
          v__k = [47, v__k];
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
          const v__inl5_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 8: {
          const __t0 = (v__inl6__arg0 =>
            v__cps__scc__apply1__df__lam_9_1__df__rowmono_1_bindIOAfterArgs_5__df__rowmono_5_bindIOAfterArgs_9__lift_14(
              [30, v_io[1], v__inl6__arg0],
              [43]
            ))(__getArgs());
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_handleErrorIO_0(
    v__cps__df__rowmono_0_bindIO_4(
      v__cps__df__rowmono_4_bindIO_8([8, [28]], [41]),
      [39]
    ),
    [37]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
