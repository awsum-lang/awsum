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

  const v_$apply$mkmb = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 34: {
          return v_$x;
        }
        case 35: {
          const v_$pk__35 = v_$k[1];
          switch (v_$x[0]) {
            case 11: {
              v_$x = [12, v_$k[2]];
              v_$k = v_$pk__35;
              continue;
            }
            case 12: {
              v_$k = v_$pk__35;
              continue;
            }
          }
        }
      }
    }
  };

  const v_$cps$mkmb = (v_c, v_$k) => {
    while (true) {
      {
        const __s = __eqInt32(v_c, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return v_$apply$mkmb(v_$k, [11]);
          }
          case 2: {
            {
              const __s = __predInt32(v_c);
              switch (__s[0]) {
                case 3: {
                  return v_$apply$mkmb(v_$k, [11]);
                }
                case 4: {
                  const v_d = __s[1];
                  v_$k = [35, v_$k, v_c];
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

  const v_$apply$mklist = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 32: {
          return v_$x;
        }
        case 33: {
          const v_$pk__33 = v_$k[1];
          v_$x = (v_$k[0] = 25, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__33;
          continue;
        }
      }
    }
  };

  const v_$cps$mklist = (v_a, v_$k) => {
    while (true) {
      {
        const __s = __eqInt32(v_a, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return v_$apply$mklist(v_$k, [24]);
          }
          case 2: {
            {
              const __s = __predInt32(v_a);
              switch (__s[0]) {
                case 3: {
                  return v_$apply$mklist(v_$k, [24]);
                }
                case 4: {
                  const v_b = __s[1];
                  v_$k = [33, v_$k, v_a];
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

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 36: {
          return v_$x;
        }
        case 37: {
          const v_$pk__37 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__37;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$0(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$0(
            v_$k,
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
          v_$k = [37, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont = v_io[1];
          return v_$apply$$df$handleErrorIO$0(v_$k, [8, [27, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$df$$rowmono$0$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 38: {
          return v_$x;
        }
        case 39: {
          const v_$pk__39 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__39;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$$rowmono$0$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_$inl24$args = v_io[1];
          const v_$inl18$k2 = (s => {
            switch (s[0]) {
              case 13: {
                return 3 | 0;
              }
              case 14: {
                {
                  const __s = __parseInt32(v_$inl24$args[1]);
                  switch (__s[0]) {
                    case 3: {
                      return 4 | 0;
                    }
                    case 4: {
                      const v_$inl17$m = __s[1];
                      return v_$inl17$m;
                    }
                  }
                }
              }
            }
          })(v_$inl24$args);
          return v_$apply$$df$$rowmono$0$andThenIO$4(
            v_$k,
            [
              7,
              String(
                (() => {
                  let v_$inl20$scrut;
                  $join19: {
                    const __s = (s => {
                      switch (s[0]) {
                        case 1: {
                          return [11];
                        }
                        case 2: {
                          return v_$cps$mkmb(v_$inl18$k2, [34]);
                        }
                      }
                    })(__eqInt32(v_$inl18$k2, 5 | 0));
                    switch (__s[0]) {
                      case 11: {
                        return 9 | 0;
                      }
                      case 12: {
                        const v_$inl23$v = __s[1];
                        v_$inl20$scrut = v_$cps$mklist(v_$inl23$v, [32]);
                        break $join19;
                      }
                    }
                  }
                  switch (v_$inl20$scrut[0]) {
                    case 24: {
                      return 0 | 0;
                    }
                    case 25: {
                      return v_$inl20$scrut[1];
                    }
                  }
                })()
              ),
              [5, [0]]
            ]
          );
        }
        case 6: {
          return v_$apply$$df$$rowmono$0$andThenIO$4(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [39, v_$k, v_s];
          v_io = v_next;
          continue;
        }
        case 8: {
          const v_cont = v_io[1];
          return v_$apply$$df$$rowmono$0$andThenIO$4(v_$k, [8, [26, v_cont]]);
        }
      }
    }
  };

  const v_$apply$$scc$$apply1__$df$$lam$14$5__$df$$lam$9$1 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 40: {
          return v_$x;
        }
        case 41: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$$rowmono$0$andThenIO$4(v_$x, [38]);
          continue;
        }
        case 42: {
          v_$k = v_$k[1];
          v_$x = v_$cps$$df$handleErrorIO$0(v_$x, [36]);
          continue;
        }
      }
    }
  };

  const v_$cps$$scc$$apply1__$df$$lam$14$5__$df$$lam$9$1 = (v_$args, v_$k) => {
    while (true) {
      switch (v_$args[0]) {
        case 29: {
          const v_$cl = v_$args[1];
          const v_$arg0 = v_$args[2];
          switch (v_$cl[0]) {
            case 26: {
              v_$args = (v_$args[0] = 30, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 27: {
              v_$args = (v_$args[0] = 31, v_$args[1] = v_$cl[1], v_$args);
              continue;
            }
            case 28: {
              return v_$apply$$scc$$apply1__$df$$lam$14$5__$df$$lam$9$1(
                v_$k,
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return [6, v_$arg0[1]];
                    }
                    case 4: {
                      return [5, v_$arg0[1]];
                    }
                  }
                })(v_$arg0)
              );
            }
          }
        }
        case 30: {
          v_$args = (v_$args[0] = 29, v_$args);
          v_$k = [41, v_$k];
          continue;
        }
        case 31: {
          v_$args = (v_$args[0] = 29, v_$args);
          v_$k = [42, v_$k];
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
          const v_$inl27$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
        case 8: {
          const __t0 = (() => {
            const v_$inl28$$arg0 = __getArgs();
            return v_$cps$$scc$$apply1__$df$$lam$14$5__$df$$lam$9$1(
              [29, v_io[1], v_$inl28$$arg0],
              [40]
            );
          })();
          v_io = __t0;
          continue;
        }
      }
    }
  };

  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$$rowmono$0$andThenIO$4([8, [28]], [38]),
    [36]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
