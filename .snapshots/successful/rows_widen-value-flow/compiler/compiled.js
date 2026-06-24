"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const v_vStr = [3, "strErr"];

  const v_vSecond = [3, [27]];

  const v_vOkA = [4, 7 | 0];

  const v_vFirst = [3, [26]];

  const v_vErrB = [3, [25]];

  const v_vErrA = [3, [24]];

  const v_tagged = (v_label, v_val) => {
    {
      const __s = __concat(v_label, "=");
      switch (__s[0]) {
        case 3: {
          const v_$do__e__1 = __s[1];
          return [3, v_$do__e__1];
        }
        case 4: {
          const v_a = __s[1];
          {
            const __s = __concat(v_a, v_val);
            switch (__s[0]) {
              case 3: {
                const v_$do__e__0 = __s[1];
                return [3, v_$do__e__0];
              }
              case 4: {
                const v_b = __s[1];
                return __concat(v_b, "\n");
              }
            }
          }
        }
      }
    }
  };

  const v_$inl3$____input = v_vStr;
  const v_strWiden = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [1615808600, v_$inl3$____input[1]]];
      }
      case 4: {
        return v_$inl3$____input;
      }
    }
  })(v_$inl3$____input);

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

  const v_nestedUnion = v_m => {
    switch (v_m[0]) {
      case 11: {
        const v_$inl6$____input = v_vFirst;
        switch (v_$inl6$____input[0]) {
          case 3: {
            return [3, [925038822, v_$inl6$____input[1]]];
          }
          case 4: {
            return v_$inl6$____input;
          }
        }
      }
      case 12: {
        {
          const __s = v_m[1];
          switch (__s[0]) {
            case 1: {
              const v_$inl9$____input = v_vErrA;
              switch (v_$inl9$____input[0]) {
                case 3: {
                  return [3, [2252990199, v_$inl9$____input[1]]];
                }
                case 4: {
                  return v_$inl9$____input;
                }
              }
            }
            case 2: {
              const v_$inl12$____input = v_vSecond;
              switch (v_$inl12$____input[0]) {
                case 3: {
                  return [3, [925038822, v_$inl12$____input[1]]];
                }
                case 4: {
                  return v_$inl12$____input;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_$inl29$x = v_vErrB;
  const v_letBody = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2269767818, v_$inl29$x[1]]];
      }
      case 4: {
        return v_$inl29$x;
      }
    }
  })(v_$inl29$x);

  const v_$inl24$____input = v_vOkA;
  const v_defBodyRight = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2252990199, v_$inl24$____input[1]]];
      }
      case 4: {
        return v_$inl24$____input;
      }
    }
  })(v_$inl24$____input);

  const v_$inl21$____input = v_vErrA;
  const v_defBodyLeft = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2252990199, v_$inl21$____input[1]]];
      }
      case 4: {
        return v_$inl21$____input;
      }
    }
  })(v_$inl21$____input);

  const v_caseUnion = v_flag => {
    switch (v_flag[0]) {
      case 1: {
        const v_$inl15$____input = v_vErrA;
        switch (v_$inl15$____input[0]) {
          case 3: {
            return [3, [2252990199, v_$inl15$____input[1]]];
          }
          case 4: {
            return v_$inl15$____input;
          }
        }
      }
      case 2: {
        const v_$inl18$____input = v_vErrB;
        switch (v_$inl18$____input[0]) {
          case 3: {
            return [3, [2269767818, v_$inl18$____input[1]]];
          }
          case 4: {
            return v_$inl18$____input;
          }
        }
      }
    }
  };

  const v_$inl34$e = v_defBodyLeft;
  const v_render = (s => {
    switch (s[0]) {
      case 3: {
        const v_$do__e__10 = s[1];
        return [3, v_$do__e__10];
      }
      case 4: {
        const v_r01 = s[1];
        let v_$inl92$scrut;
        $join91: {
          const v_$inl39$e = v_defBodyRight;
          const __s = v_tagged(
            "defBodyRight",
            (s => {
              switch (s[0]) {
                case 3: {
                  {
                    const __s = v_$inl39$e[1];
                    switch (__s[0]) {
                      case 2252990199: {
                        return "ErrA";
                      }
                      case 2269767818: {
                        return "ErrB";
                      }
                    }
                  }
                }
                case 4: {
                  return String(v_$inl39$e[1]);
                }
              }
            })(v_$inl39$e)
          );
          switch (__s[0]) {
            case 3: {
              const v_$inl40$$do__e__2 = __s[1];
              return [3, v_$inl40$$do__e__2];
            }
            case 4: {
              const v_$inl41$line = __s[1];
              v_$inl92$scrut = __concat(v_r01, v_$inl41$line);
              break $join91;
            }
          }
        }
        switch (v_$inl92$scrut[0]) {
          case 3: {
            return v_$inl92$scrut;
          }
          case 4: {
            let v_$inl94$scrut;
            $join93: {
              const v_$inl46$e = v_letBody;
              const __s = v_tagged(
                "letBody",
                (s => {
                  switch (s[0]) {
                    case 3: {
                      {
                        const __s = v_$inl46$e[1];
                        switch (__s[0]) {
                          case 2252990199: {
                            return "ErrA";
                          }
                          case 2269767818: {
                            return "ErrB";
                          }
                        }
                      }
                    }
                    case 4: {
                      return String(v_$inl46$e[1]);
                    }
                  }
                })(v_$inl46$e)
              );
              switch (__s[0]) {
                case 3: {
                  const v_$inl47$$do__e__2 = __s[1];
                  return [3, v_$inl47$$do__e__2];
                }
                case 4: {
                  const v_$inl48$line = __s[1];
                  v_$inl94$scrut = __concat(v_$inl92$scrut[1], v_$inl48$line);
                  break $join93;
                }
              }
            }
            switch (v_$inl94$scrut[0]) {
              case 3: {
                return v_$inl94$scrut;
              }
              case 4: {
                let v_$inl96$scrut;
                $join95: {
                  const v_$inl53$e = v_caseUnion([1]);
                  const __s = v_tagged(
                    "caseTrue",
                    (s => {
                      switch (s[0]) {
                        case 3: {
                          {
                            const __s = v_$inl53$e[1];
                            switch (__s[0]) {
                              case 2252990199: {
                                return "ErrA";
                              }
                              case 2269767818: {
                                return "ErrB";
                              }
                            }
                          }
                        }
                        case 4: {
                          return String(v_$inl53$e[1]);
                        }
                      }
                    })(v_$inl53$e)
                  );
                  switch (__s[0]) {
                    case 3: {
                      const v_$inl54$$do__e__2 = __s[1];
                      return [3, v_$inl54$$do__e__2];
                    }
                    case 4: {
                      const v_$inl55$line = __s[1];
                      v_$inl96$scrut = __concat(
                        v_$inl94$scrut[1],
                        v_$inl55$line
                      );
                      break $join95;
                    }
                  }
                }
                switch (v_$inl96$scrut[0]) {
                  case 3: {
                    return v_$inl96$scrut;
                  }
                  case 4: {
                    let v_$inl98$scrut;
                    $join97: {
                      const v_$inl60$e = v_caseUnion([2]);
                      const __s = v_tagged(
                        "caseFalse",
                        (s => {
                          switch (s[0]) {
                            case 3: {
                              {
                                const __s = v_$inl60$e[1];
                                switch (__s[0]) {
                                  case 2252990199: {
                                    return "ErrA";
                                  }
                                  case 2269767818: {
                                    return "ErrB";
                                  }
                                }
                              }
                            }
                            case 4: {
                              return String(v_$inl60$e[1]);
                            }
                          }
                        })(v_$inl60$e)
                      );
                      switch (__s[0]) {
                        case 3: {
                          const v_$inl61$$do__e__2 = __s[1];
                          return [3, v_$inl61$$do__e__2];
                        }
                        case 4: {
                          const v_$inl62$line = __s[1];
                          v_$inl98$scrut = __concat(
                            v_$inl96$scrut[1],
                            v_$inl62$line
                          );
                          break $join97;
                        }
                      }
                    }
                    switch (v_$inl98$scrut[0]) {
                      case 3: {
                        return v_$inl98$scrut;
                      }
                      case 4: {
                        let v_$inl100$scrut;
                        $join99: {
                          const v_$inl67$e = v_nestedUnion([11]);
                          const __s = v_tagged(
                            "nestedNothing",
                            (s => {
                              switch (s[0]) {
                                case 3: {
                                  const v_$inl63$____pa0 = s[1];
                                  switch (v_$inl63$____pa0[0]) {
                                    case 925038822: {
                                      {
                                        const __s = v_$inl63$____pa0[1];
                                        switch (__s[0]) {
                                          case 26: {
                                            return "First";
                                          }
                                          case 27: {
                                            return "Second";
                                          }
                                        }
                                      }
                                    }
                                    case 2252990199: {
                                      return "ErrA";
                                    }
                                  }
                                }
                                case 4: {
                                  return String(v_$inl67$e[1]);
                                }
                              }
                            })(v_$inl67$e)
                          );
                          switch (__s[0]) {
                            case 3: {
                              const v_$inl68$$do__e__2 = __s[1];
                              return [3, v_$inl68$$do__e__2];
                            }
                            case 4: {
                              const v_$inl69$line = __s[1];
                              v_$inl100$scrut = __concat(
                                v_$inl98$scrut[1],
                                v_$inl69$line
                              );
                              break $join99;
                            }
                          }
                        }
                        switch (v_$inl100$scrut[0]) {
                          case 3: {
                            return v_$inl100$scrut;
                          }
                          case 4: {
                            let v_$inl102$scrut;
                            $join101: {
                              const v_$inl74$e = v_nestedUnion([12, [1]]);
                              const __s = v_tagged(
                                "nestedJustTrue",
                                (s => {
                                  switch (s[0]) {
                                    case 3: {
                                      const v_$inl70$____pa0 = s[1];
                                      switch (v_$inl70$____pa0[0]) {
                                        case 925038822: {
                                          {
                                            const __s = v_$inl70$____pa0[1];
                                            switch (__s[0]) {
                                              case 26: {
                                                return "First";
                                              }
                                              case 27: {
                                                return "Second";
                                              }
                                            }
                                          }
                                        }
                                        case 2252990199: {
                                          return "ErrA";
                                        }
                                      }
                                    }
                                    case 4: {
                                      return String(v_$inl74$e[1]);
                                    }
                                  }
                                })(v_$inl74$e)
                              );
                              switch (__s[0]) {
                                case 3: {
                                  const v_$inl75$$do__e__2 = __s[1];
                                  return [3, v_$inl75$$do__e__2];
                                }
                                case 4: {
                                  const v_$inl76$line = __s[1];
                                  v_$inl102$scrut = __concat(
                                    v_$inl100$scrut[1],
                                    v_$inl76$line
                                  );
                                  break $join101;
                                }
                              }
                            }
                            switch (v_$inl102$scrut[0]) {
                              case 3: {
                                return v_$inl102$scrut;
                              }
                              case 4: {
                                let v_$inl104$scrut;
                                $join103: {
                                  const v_$inl81$e = v_nestedUnion([12, [2]]);
                                  const __s = v_tagged(
                                    "nestedJustFalse",
                                    (s => {
                                      switch (s[0]) {
                                        case 3: {
                                          const v_$inl77$____pa0 = s[1];
                                          switch (v_$inl77$____pa0[0]) {
                                            case 925038822: {
                                              {
                                                const __s = v_$inl77$____pa0[1];
                                                switch (__s[0]) {
                                                  case 26: {
                                                    return "First";
                                                  }
                                                  case 27: {
                                                    return "Second";
                                                  }
                                                }
                                              }
                                            }
                                            case 2252990199: {
                                              return "ErrA";
                                            }
                                          }
                                        }
                                        case 4: {
                                          return String(v_$inl81$e[1]);
                                        }
                                      }
                                    })(v_$inl81$e)
                                  );
                                  switch (__s[0]) {
                                    case 3: {
                                      const v_$inl82$$do__e__2 = __s[1];
                                      return [3, v_$inl82$$do__e__2];
                                    }
                                    case 4: {
                                      const v_$inl83$line = __s[1];
                                      v_$inl104$scrut = __concat(
                                        v_$inl102$scrut[1],
                                        v_$inl83$line
                                      );
                                      break $join103;
                                    }
                                  }
                                }
                                switch (v_$inl104$scrut[0]) {
                                  case 3: {
                                    return v_$inl104$scrut;
                                  }
                                  case 4: {
                                    {
                                      const v_$inl88$e = v_strWiden;
                                      const __s = v_tagged(
                                        "strWiden",
                                        (s => {
                                          switch (s[0]) {
                                            case 3: {
                                              const v_$inl84$____pa0 = s[1];
                                              switch (v_$inl84$____pa0[0]) {
                                                case 1615808600: {
                                                  return v_$inl84$____pa0[1];
                                                }
                                                case 2252990199: {
                                                  return "ErrA";
                                                }
                                              }
                                            }
                                            case 4: {
                                              return String(v_$inl88$e[1]);
                                            }
                                          }
                                        })(v_$inl88$e)
                                      );
                                      switch (__s[0]) {
                                        case 3: {
                                          const v_$inl89$$do__e__2 = __s[1];
                                          return [3, v_$inl89$$do__e__2];
                                        }
                                        case 4: {
                                          const v_$inl90$line = __s[1];
                                          return __concat(
                                            v_$inl104$scrut[1],
                                            v_$inl90$line
                                          );
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
      }
    }
  })(
    v_tagged(
      "defBodyLeft",
      (s => {
        switch (s[0]) {
          case 3: {
            {
              const __s = v_$inl34$e[1];
              switch (__s[0]) {
                case 2252990199: {
                  return "ErrA";
                }
                case 2269767818: {
                  return "ErrB";
                }
              }
            }
          }
          case 4: {
            return String(v_$inl34$e[1]);
          }
        }
      })(v_$inl34$e)
    )
  );

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 28: {
          return v_$x;
        }
        case 29: {
          const v_$pk__29 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__29;
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
          v_$k = [29, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 30: {
          return v_$x;
        }
        case 31: {
          const v_$pk__31 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__31;
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
          v_$k = [31, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl107$x = v_render;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl107$x[1]];
          }
          case 4: {
            return [5, v_$inl107$x[1]];
          }
        }
      })(v_$inl107$x),
      [30]
    ),
    [28]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
