"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

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

  const v_rightSrc = [4, 5 | 0];

  const v_$inl21$x = v_rightSrc;
  const v_mappedOk = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2252990199, [27]]];
      }
      case 4: {
        return v_$inl21$x;
      }
    }
  })(v_$inl21$x);

  const v_leftY = [3, [3640903312, [26]]];

  const v_$inl12$x = v_leftY;
  const v_remappedY = (s => {
    switch (s[0]) {
      case 3: {
        return [
          3,
          (s => {
            switch (s[0]) {
              case 3640903312: {
                return [2269767818, [28]];
              }
              case 3657680931: {
                return [2252990199, [27]];
              }
            }
          })(v_$inl12$x[1])
        ];
      }
      case 4: {
        return v_$inl12$x;
      }
    }
  })(v_$inl12$x);

  const v_leftX = [3, [3657680931, [25]]];

  const v_$inl7$x = v_leftX;
  const v_remappedX = (s => {
    switch (s[0]) {
      case 3: {
        return [
          3,
          (s => {
            switch (s[0]) {
              case 3640903312: {
                return [2269767818, [28]];
              }
              case 3657680931: {
                return [2252990199, [27]];
              }
            }
          })(v_$inl7$x[1])
        ];
      }
      case 4: {
        return v_$inl7$x;
      }
    }
  })(v_$inl7$x);

  const v_leftSrc = [3, [24]];

  const v_$inl18$x = v_leftSrc;
  const v_mappedA = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2252990199, [27]]];
      }
      case 4: {
        return v_$inl18$x;
      }
    }
  })(v_$inl18$x);

  const v_$inl15$x = v_leftSrc;
  const v_mappedB = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2269767818, [28]]];
      }
      case 4: {
        return v_$inl15$x;
      }
    }
  })(v_$inl15$x);

  const v_$inl26$e = v_mappedA;
  const v_render = (s => {
    switch (s[0]) {
      case 3: {
        const v_$do__e__6 = s[1];
        return [3, v_$do__e__6];
      }
      case 4: {
        const v_r01 = s[1];
        let v_$inl56$scrut;
        $join55: {
          const v_$inl31$e = v_mappedB;
          const __s = v_tagged(
            "mappedB",
            (s => {
              switch (s[0]) {
                case 3: {
                  {
                    const __s = v_$inl31$e[1];
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
                  return String(v_$inl31$e[1]);
                }
              }
            })(v_$inl31$e)
          );
          switch (__s[0]) {
            case 3: {
              const v_$inl32$$do__e__2 = __s[1];
              return [3, v_$inl32$$do__e__2];
            }
            case 4: {
              const v_$inl33$line = __s[1];
              v_$inl56$scrut = __concat(v_r01, v_$inl33$line);
              break $join55;
            }
          }
        }
        switch (v_$inl56$scrut[0]) {
          case 3: {
            return v_$inl56$scrut;
          }
          case 4: {
            let v_$inl58$scrut;
            $join57: {
              const v_$inl38$e = v_mappedOk;
              const __s = v_tagged(
                "mappedOk",
                (s => {
                  switch (s[0]) {
                    case 3: {
                      {
                        const __s = v_$inl38$e[1];
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
                      return String(v_$inl38$e[1]);
                    }
                  }
                })(v_$inl38$e)
              );
              switch (__s[0]) {
                case 3: {
                  const v_$inl39$$do__e__2 = __s[1];
                  return [3, v_$inl39$$do__e__2];
                }
                case 4: {
                  const v_$inl40$line = __s[1];
                  v_$inl58$scrut = __concat(v_$inl56$scrut[1], v_$inl40$line);
                  break $join57;
                }
              }
            }
            switch (v_$inl58$scrut[0]) {
              case 3: {
                return v_$inl58$scrut;
              }
              case 4: {
                let v_$inl60$scrut;
                $join59: {
                  const v_$inl45$e = v_remappedX;
                  const __s = v_tagged(
                    "remappedX",
                    (s => {
                      switch (s[0]) {
                        case 3: {
                          {
                            const __s = v_$inl45$e[1];
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
                          return String(v_$inl45$e[1]);
                        }
                      }
                    })(v_$inl45$e)
                  );
                  switch (__s[0]) {
                    case 3: {
                      const v_$inl46$$do__e__2 = __s[1];
                      return [3, v_$inl46$$do__e__2];
                    }
                    case 4: {
                      const v_$inl47$line = __s[1];
                      v_$inl60$scrut = __concat(
                        v_$inl58$scrut[1],
                        v_$inl47$line
                      );
                      break $join59;
                    }
                  }
                }
                switch (v_$inl60$scrut[0]) {
                  case 3: {
                    return v_$inl60$scrut;
                  }
                  case 4: {
                    {
                      const v_$inl52$e = v_remappedY;
                      const __s = v_tagged(
                        "remappedY",
                        (s => {
                          switch (s[0]) {
                            case 3: {
                              {
                                const __s = v_$inl52$e[1];
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
                              return String(v_$inl52$e[1]);
                            }
                          }
                        })(v_$inl52$e)
                      );
                      switch (__s[0]) {
                        case 3: {
                          const v_$inl53$$do__e__2 = __s[1];
                          return [3, v_$inl53$$do__e__2];
                        }
                        case 4: {
                          const v_$inl54$line = __s[1];
                          return __concat(v_$inl60$scrut[1], v_$inl54$line);
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
      "mappedA",
      (s => {
        switch (s[0]) {
          case 3: {
            {
              const __s = v_$inl26$e[1];
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
            return String(v_$inl26$e[1]);
          }
        }
      })(v_$inl26$e)
    )
  );

  const v_$apply$$df$handleErrorIO$3 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 29: {
          return v_$x;
        }
        case 30: {
          const v_$pk__30 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__30;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$3 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$3(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$3(
            v_$k,
            [7, "STRING_TOO_LONG", [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [30, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$7 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 31: {
          return v_$x;
        }
        case 32: {
          const v_$pk__32 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__32;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$7 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$7(v_$k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$7(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [32, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl63$x = v_render;
  const main = v_$cps$$df$handleErrorIO$3(
    v_$cps$$df$andThenIO$7(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl63$x[1]];
          }
          case 4: {
            return [5, v_$inl63$x[1]];
          }
        }
      })(v_$inl63$x),
      [31]
    ),
    [29]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
