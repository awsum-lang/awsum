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

  const v_spin = v_n => {
    while (true) {
      {
        const __s = __eqInt32(v_n, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [28];
          }
          case 2: {
            {
              const __s = __predInt32(v_n);
              switch (__s[0]) {
                case 3: {
                  return [28];
                }
                case 4: {
                  const v_m = __s[1];
                  v_n = v_m;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_label = v_k => {
    {
      const __s = (() => {
        let v__inl1_scrut;
        $join0: {
          const __s = __eqInt32(v_k, 7 | 0);
          switch (__s[0]) {
            case 1: {
              return [27];
            }
            case 2: {
              v__inl1_scrut = (s => {
                switch (s[0]) {
                  case 1: {
                    return [24];
                  }
                  case 2: {
                    {
                      const __s = __eqInt32(v_k, 1 | 0);
                      switch (__s[0]) {
                        case 1: {
                          return [25];
                        }
                        case 2: {
                          return [26];
                        }
                      }
                    }
                  }
                }
              })(__eqInt32(v_k, 0 | 0));
              break $join0;
            }
          }
        }
        switch (v__inl1_scrut[0]) {
          case 24: {
            return [27];
          }
          case 25: {
            return v_spin(v_k);
          }
          case 26: {
            return [29];
          }
        }
      })();
      switch (__s[0]) {
        case 27: {
          return "x";
        }
        case 28: {
          return "y";
        }
        case 29: {
          return "z";
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
                  return [7, "UPS", [5, [0]]];
                }
                case 589989748: {
                  return [7, "STL", [5, [0]]];
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
          return v__apply__df_handleErrorIO_0(v__k, [8, [31, v_cont]]);
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
          const v__inl12_args = v_io[1];
          return v__apply__df__rowmono_0_andThenIO_4(
            v__k,
            (s => {
              switch (s[0]) {
                case 13: {
                  return [7, v_label(3 | 0), [5, [0]]];
                }
                case 14: {
                  {
                    const __s = __parseInt32(v__inl12_args[1]);
                    switch (__s[0]) {
                      case 3: {
                        return [7, "PARSE", [5, [0]]];
                      }
                      case 4: {
                        const v__inl11_n = __s[1];
                        return [7, v_label(v__inl11_n), [5, [0]]];
                      }
                    }
                  }
                }
              }
            })(v__inl12_args)
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
          return v__apply__df__rowmono_0_andThenIO_4(v__k, [8, [30, v_cont]]);
        }
      }
    }
  };

  const v__apply__scc__apply1__df__lam_13_5__df__lam_9_1 = (v__k, v__x) => {
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

  const v__cps__scc__apply1__df__lam_13_5__df__lam_9_1 = (v__args, v__k) => {
    while (true) {
      switch (v__args[0]) {
        case 33: {
          const v__cl = v__args[1];
          const v__arg0 = v__args[2];
          switch (v__cl[0]) {
            case 30: {
              v__args = (v__args[0] = 34, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 31: {
              v__args = (v__args[0] = 35, v__args[1] = v__cl[1], v__args);
              continue;
            }
            case 32: {
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
        case 34: {
          v__args = (v__args[0] = 33, v__args);
          v__k = [41, v__k];
          continue;
        }
        case 35: {
          v__args = (v__args[0] = 33, v__args);
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
          const v__inl15_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 8: {
          const __t0 = (() => {
            const v__inl16__arg0 = __getArgs();
            return v__cps__scc__apply1__df__lam_13_5__df__lam_9_1(
              [33, v_io[1], v__inl16__arg0],
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
    v__cps__df__rowmono_0_andThenIO_4([8, [32]], [38]),
    [36]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
