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

  const v_$inl51$xs = [13];
  const v_$inl75$noElems = (s => {
    switch (s[0]) {
      case 13: {
        return [11];
      }
      case 14: {
        return [12, v_$inl51$xs[1]];
      }
    }
  })(v_$inl51$xs);
  const v_$inl52$xs = [14, "a", [13]];
  const v_$inl55$single = (s => {
    switch (s[0]) {
      case 13: {
        return [11];
      }
      case 14: {
        return [12, v_$inl52$xs[1]];
      }
    }
  })(v_$inl52$xs);
  const v_$inl56$xs = [14, "a", [14, "b", [14, "c", [13]]]];
  const v_$inl59$multi = (s => {
    switch (s[0]) {
      case 13: {
        return [11];
      }
      case 14: {
        return [12, v_$inl56$xs[1]];
      }
    }
  })(v_$inl56$xs);
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v_$inl61$$do__e__5 = s[1];
        return [3, v_$inl61$$do__e__5];
      }
      case 4: {
        const v_$inl62$a = s[1];
        {
          const __s = (s => {
            switch (s[0]) {
              case 11: {
                return [4, "Nothing"];
              }
              case 12: {
                return __concat("Just ", v_$inl55$single[1]);
              }
            }
          })(v_$inl55$single);
          switch (__s[0]) {
            case 3: {
              const v_$inl64$$do__e__4 = __s[1];
              return [3, v_$inl64$$do__e__4];
            }
            case 4: {
              const v_$inl65$b = __s[1];
              {
                const __s = (s => {
                  switch (s[0]) {
                    case 11: {
                      return [4, "Nothing"];
                    }
                    case 12: {
                      return __concat("Just ", v_$inl59$multi[1]);
                    }
                  }
                })(v_$inl59$multi);
                switch (__s[0]) {
                  case 3: {
                    const v_$inl67$$do__e__3 = __s[1];
                    return [3, v_$inl67$$do__e__3];
                  }
                  case 4: {
                    const v_$inl68$c = __s[1];
                    {
                      const __s = __concat(v_$inl62$a, "|");
                      switch (__s[0]) {
                        case 3: {
                          const v_$inl69$$do__e__2 = __s[1];
                          return [3, v_$inl69$$do__e__2];
                        }
                        case 4: {
                          const v_$inl70$s0 = __s[1];
                          {
                            const __s = __concat(v_$inl70$s0, v_$inl65$b);
                            switch (__s[0]) {
                              case 3: {
                                const v_$inl71$$do__e__1 = __s[1];
                                return [3, v_$inl71$$do__e__1];
                              }
                              case 4: {
                                const v_$inl72$s1 = __s[1];
                                {
                                  const __s = __concat(v_$inl72$s1, "|");
                                  switch (__s[0]) {
                                    case 3: {
                                      const v_$inl73$$do__e__0 = __s[1];
                                      return [3, v_$inl73$$do__e__0];
                                    }
                                    case 4: {
                                      const v_$inl74$s2 = __s[1];
                                      return __concat(v_$inl74$s2, v_$inl68$c);
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
        case 11: {
          return [4, "Nothing"];
        }
        case 12: {
          return __concat("Just ", v_$inl75$noElems[1]);
        }
      }
    })(v_$inl75$noElems)
  );

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 20: {
          return v_$x;
        }
        case 21: {
          const v_$pk__21 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__21;
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
          v_$k = [21, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
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
          v_$k = [23, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl78$x = v_res;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl78$x[1]];
          }
          case 4: {
            return [5, v_$inl78$x[1]];
          }
        }
      })(v_$inl78$x),
      [22]
    ),
    [20]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
