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

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 25: {
          return v_$x;
        }
        case 26: {
          const v_$pk__26 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__26;
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
          v_$k = [26, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 27: {
          return v_$x;
        }
        case 28: {
          const v_$pk__28 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__28;
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
          v_$k = [28, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl95$fromNothing = [3, [24]];
  const v_$inl69$fromJust = [4, "hi"];
  const v_$inl70$xs = [14, "first", [14, "second", [13]]];
  const v_$inl73$chained = (s => {
    switch (s[0]) {
      case 13: {
        return [3, [24]];
      }
      case 14: {
        return [4, v_$inl70$xs[1]];
      }
    }
  })(v_$inl70$xs);
  const v_$inl92$msg = (s => {
    switch (s[0]) {
      case 3: {
        const v_$inl76$$do__e__6 = s[1];
        return [3, v_$inl76$$do__e__6];
      }
      case 4: {
        const v_$inl77$a = s[1];
        {
          const __s = (s => {
            switch (s[0]) {
              case 3: {
                return [4, "Left Missing"];
              }
              case 4: {
                return __concat("Right ", v_$inl69$fromJust[1]);
              }
            }
          })(v_$inl69$fromJust);
          switch (__s[0]) {
            case 3: {
              const v_$inl80$$do__e__5 = __s[1];
              return [3, v_$inl80$$do__e__5];
            }
            case 4: {
              const v_$inl81$b = __s[1];
              {
                const __s = (s => {
                  switch (s[0]) {
                    case 3: {
                      return [4, "Left Missing"];
                    }
                    case 4: {
                      return __concat("Right ", v_$inl73$chained[1]);
                    }
                  }
                })(v_$inl73$chained);
                switch (__s[0]) {
                  case 3: {
                    const v_$inl84$$do__e__4 = __s[1];
                    return [3, v_$inl84$$do__e__4];
                  }
                  case 4: {
                    const v_$inl85$c = __s[1];
                    {
                      const __s = __concat(v_$inl77$a, "|");
                      switch (__s[0]) {
                        case 3: {
                          const v_$inl86$$do__e__3 = __s[1];
                          return [3, v_$inl86$$do__e__3];
                        }
                        case 4: {
                          const v_$inl87$sep = __s[1];
                          {
                            const __s = __concat(v_$inl87$sep, v_$inl81$b);
                            switch (__s[0]) {
                              case 3: {
                                const v_$inl88$$do__e__2 = __s[1];
                                return [3, v_$inl88$$do__e__2];
                              }
                              case 4: {
                                const v_$inl89$s1 = __s[1];
                                {
                                  const __s = __concat(v_$inl89$s1, "|");
                                  switch (__s[0]) {
                                    case 3: {
                                      const v_$inl90$$do__e__1 = __s[1];
                                      return [3, v_$inl90$$do__e__1];
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
        case 3: {
          return [4, "Left Missing"];
        }
        case 4: {
          return __concat("Right ", v_$inl95$fromNothing[1]);
        }
      }
    })(v_$inl95$fromNothing)
  );
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl92$msg[1]];
          }
          case 4: {
            return [5, v_$inl92$msg[1]];
          }
        }
      })(v_$inl92$msg),
      [27]
    ),
    [25]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
