"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const v_runIO = v_io => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_io[1];
        }
        case 7: {
          const v_$inl0$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v_$apply$showList = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 20: {
          return v_$x;
        }
        case 21: {
          const v_$pk__21 = v_$k[1];
          switch (v_$x[0]) {
            case 3: {
              v_$k = v_$pk__21;
              continue;
            }
            case 4: {
              const v_rest = v_$x[1];
              {
                const __s = __concat(v_$k[2], ",");
                switch (__s[0]) {
                  case 3: {
                    const v_$do__e__0 = __s[1];
                    v_$k = v_$pk__21;
                    v_$x = [3, v_$do__e__0];
                    continue;
                  }
                  case 4: {
                    const v_hc = __s[1];
                    v_$k = v_$pk__21;
                    v_$x = __concat(v_hc, v_rest);
                    continue;
                  }
                }
              }
            }
          }
        }
      }
    }
  };

  const v_$cps$showList = (v_xs, v_$k) => {
    while (true) {
      switch (v_xs[0]) {
        case 13: {
          return v_$apply$showList(v_$k, [4, "Nil"]);
        }
        case 14: {
          const v_h = v_xs[1];
          const v_t = v_xs[2];
          v_$k = [21, v_$k, v_h];
          v_xs = v_t;
          continue;
        }
      }
    }
  };

  const v_$inl66$xs = [13];
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v_$inl70$$do__e__8 = s[1];
        return [3, v_$inl70$$do__e__8];
      }
      case 4: {
        const v_$inl71$a = s[1];
        const v_$inl72$xs = [14, "a", [13]];
        {
          const __s = (s => {
            switch (s[0]) {
              case 13: {
                return [4, "Nothing"];
              }
              case 14: {
                {
                  const __s = v_$cps$showList(v_$inl72$xs[2], [20]);
                  switch (__s[0]) {
                    case 3: {
                      const v_$inl75$$do__e__2 = __s[1];
                      return [3, v_$inl75$$do__e__2];
                    }
                    case 4: {
                      const v_$inl76$rendered = __s[1];
                      return __concat("Just ", v_$inl76$rendered);
                    }
                  }
                }
              }
            }
          })(v_$inl72$xs);
          switch (__s[0]) {
            case 3: {
              const v_$inl77$$do__e__7 = __s[1];
              return [3, v_$inl77$$do__e__7];
            }
            case 4: {
              const v_$inl78$b = __s[1];
              const v_$inl79$xs = [14, "a", [14, "b", [14, "c", [13]]]];
              {
                const __s = (s => {
                  switch (s[0]) {
                    case 13: {
                      return [4, "Nothing"];
                    }
                    case 14: {
                      {
                        const __s = v_$cps$showList(v_$inl79$xs[2], [20]);
                        switch (__s[0]) {
                          case 3: {
                            const v_$inl82$$do__e__2 = __s[1];
                            return [3, v_$inl82$$do__e__2];
                          }
                          case 4: {
                            const v_$inl83$rendered = __s[1];
                            return __concat("Just ", v_$inl83$rendered);
                          }
                        }
                      }
                    }
                  }
                })(v_$inl79$xs);
                switch (__s[0]) {
                  case 3: {
                    const v_$inl84$$do__e__6 = __s[1];
                    return [3, v_$inl84$$do__e__6];
                  }
                  case 4: {
                    const v_$inl85$c = __s[1];
                    {
                      const __s = __concat(v_$inl71$a, "|");
                      switch (__s[0]) {
                        case 3: {
                          const v_$inl86$$do__e__5 = __s[1];
                          return [3, v_$inl86$$do__e__5];
                        }
                        case 4: {
                          const v_$inl87$s0 = __s[1];
                          {
                            const __s = __concat(v_$inl87$s0, v_$inl78$b);
                            switch (__s[0]) {
                              case 3: {
                                const v_$inl88$$do__e__4 = __s[1];
                                return [3, v_$inl88$$do__e__4];
                              }
                              case 4: {
                                const v_$inl89$s1 = __s[1];
                                {
                                  const __s = __concat(v_$inl89$s1, "|");
                                  switch (__s[0]) {
                                    case 3: {
                                      const v_$inl90$$do__e__3 = __s[1];
                                      return [3, v_$inl90$$do__e__3];
                                    }
                                    case 4: {
                                      const v_$inl91$s2 = __s[1];
                                      return __concat(v_$inl91$s2, v_$inl85$c);
                                    }
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  })(
    (s => {
      switch (s[0]) {
        case 13: {
          return [4, "Nothing"];
        }
        case 14: {
          {
            const __s = v_$cps$showList(v_$inl66$xs[2], [20]);
            switch (__s[0]) {
              case 3: {
                const v_$inl92$$do__e__2 = __s[1];
                return [3, v_$inl92$$do__e__2];
              }
              case 4: {
                const v_$inl93$rendered = __s[1];
                return __concat("Just ", v_$inl93$rendered);
              }
            }
          }
        }
      }
    })(v_$inl66$xs)
  );

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 22: {
          return v_$x;
        }
        case 23: {
          const v_$pk__23 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__23;
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
            [7, "STRING_TOO_LONG", [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [23, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 24: {
          return v_$x;
        }
        case 25: {
          const v_$pk__25 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__25;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$4(v_$k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$4(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [25, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl96$x = v_res;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl96$x[1]];
          }
          case 4: {
            return [5, v_$inl96$x[1]];
          }
        }
      })(v_$inl96$x),
      [24]
    ),
    [22]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
