"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = x => x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];

  const __eqInt32 = (a, b) => a === b ? [1] : [2];

  const __parseInt32 = s => {
    if (!/^-?[0-9]+$/.test(s)) {
      return [3, [22]];
    }
    const n = Number(s);
    if (n < -2147483648 || n > 2147483647) {
      return [3, [22]];
    }
    return [4, n | 0];
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

  const v__apply_mkmb = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 34: {
          return v__x;
        }
        case 35: {
          const v__pk_35 = v__k[1];
          switch (v__x[0]) {
            case 11: {
              v__x = [12, v__k[2]];
              v__k = v__pk_35;
              continue;
            }
            case 12: {
              v__k = v__pk_35;
              continue;
            }
          }
        }
      }
    }
  };

  const v__cps_mkmb = (v_c, v__k) => {
    while (true) {
      {
        const __s = __eqInt32(v_c, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return v__apply_mkmb(v__k, [11]);
          }
          case 2: {
            {
              const __s = __predInt32(v_c);
              switch (__s[0]) {
                case 3: {
                  return v__apply_mkmb(v__k, [11]);
                }
                case 4: {
                  const v_d = __s[1];
                  v__k = [35, v__k, v_c];
                  v_c = v_d;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__apply_mklist = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 32: {
          return v__x;
        }
        case 33: {
          const v__pk_33 = v__k[1];
          v__x = (v__k[0] = 25, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_33;
          continue;
        }
      }
    }
  };

  const v__cps_mklist = (v_a, v__k) => {
    while (true) {
      {
        const __s = __eqInt32(v_a, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return v__apply_mklist(v__k, [24]);
          }
          case 2: {
            {
              const __s = __predInt32(v_a);
              switch (__s[0]) {
                case 3: {
                  return v__apply_mklist(v__k, [24]);
                }
                case 4: {
                  const v_b = __s[1];
                  v__k = [33, v__k, v_a];
                  v_a = v_b;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 36: {
          return v__x;
        }
        case 37: {
          const v__pk_37 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_37;
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
                case 502975519: {
                  return [7, "UNPAIRED", [5, [0]]];
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
          v__k = [37, v__k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont = v_io[1];
          return v__apply__df_handleErrorIO_0(v__k, [8, [27, v_cont]]);
        }
      }
    }
  };

  const v__apply__df__rowmono_0_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 38: {
          return v__x;
        }
        case 39: {
          const v__pk_39 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_39;
          continue;
        }
      }
    }
  };

  const v__cps__df__rowmono_0_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v__inl24_args = v_io[1];
          const v__inl18_k2 = (s => {
            switch (s[0]) {
              case 13: {
                return 3 | 0;
              }
              case 14: {
                {
                  const __s = __parseInt32(v__inl24_args[1]);
                  switch (__s[0]) {
                    case 3: {
                      return 4 | 0;
                    }
                    case 4: {
                      const v__inl17_m = __s[1];
                      return v__inl17_m;
                    }
                  }
                }
              }
            }
          })(v__inl24_args);
          return v__apply__df__rowmono_0_andThenIO_4(
            v__k,
            [
              7,
              String(
                (() => {
                  let v__inl20_scrut;
                  $join19: {
                    const __s = (s => {
                      switch (s[0]) {
                        case 1: {
                          return [11];
                        }
                        case 2: {
                          return v__cps_mkmb(v__inl18_k2, [34]);
                        }
                      }
                    })(__eqInt32(v__inl18_k2, 5 | 0));
                    switch (__s[0]) {
                      case 11: {
                        return 9 | 0;
                      }
                      case 12: {
                        const v__inl23_v = __s[1];
                        v__inl20_scrut = v__cps_mklist(v__inl23_v, [32]);
                        break $join19;
                      }
                    }
                  }
                  switch (v__inl20_scrut[0]) {
                    case 24: {
                      return 0 | 0;
                    }
                    case 25: {
                      return v__inl20_scrut[1];
                    }
                  }
                })()
              ),
              [5, [0]]
            ]
          );
        }
        case 6: {
          return v__apply__df__rowmono_0_andThenIO_4(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [39, v__k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont = v_io[1];
          return v__apply__df__rowmono_0_andThenIO_4(v__k, [8, [26, v_cont]]);
        }
      }
    }
  };

  const v__apply__scc__apply1__df__lam_14_5__df__lam_9_1 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 40: {
          return v__x;
        }
        case 41: {
          v__k = v__k[1];
          v__x = v__cps__df__rowmono_0_andThenIO_4(v__x, [38]);
          continue;
        }
        case 42: {
          v__k = v__k[1];
          v__x = v__cps__df_handleErrorIO_0(v__x, [36]);
          continue;
        }
      }
    }
  };

  const v__cps__scc__apply1__df__lam_14_5__df__lam_9_1 = (v__args, v__k) => {
    while (true) {
      switch (v__args[0]) {
        case 29: {
          const v__cl = v__args[1];
          const v__arg0 = v__args[2];
          switch (v__cl[0]) {
            case 26: {
              v__args = (v__args[0] = 30, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 27: {
              v__args = (v__args[0] = 31, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 28: {
              return v__apply__scc__apply1__df__lam_14_5__df__lam_9_1(
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
        case 30: {
          v__args = (v__args[0] = 29, v__args);
          v__k = [41, v__k];
          continue;
        }
        case 31: {
          v__args = (v__args[0] = 29, v__args);
          v__k = [42, v__k];
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
          const v__inl27_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 8: {
          const __t0 = (() => {
            const v__inl28__arg0 = __getArgs();
            return v__cps__scc__apply1__df__lam_14_5__df__lam_9_1(
              [29, v_io[1], v__inl28__arg0],
              [40]
            );
          })();
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_handleErrorIO_0(
    v__cps__df__rowmono_0_andThenIO_4([8, [28]], [38]),
    [36]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
