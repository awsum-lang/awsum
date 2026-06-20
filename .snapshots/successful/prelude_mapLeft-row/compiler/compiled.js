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
          const v__do_e_1 = __s[1];
          return [3, v__do_e_1];
        }
        case 4: {
          const v_a = __s[1];
          {
            const __s = __concat(v_a, v_val);
            switch (__s[0]) {
              case 3: {
                const v__do_e_0 = __s[1];
                return [3, v__do_e_0];
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
          const v__inl0_eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v_rightSrc = [4, 5 | 0];

  const v__inl21_x = v_rightSrc;
  const v_mappedOk = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2252990199, [27]]];
      }
      case 4: {
        return v__inl21_x;
      }
    }
  })(v__inl21_x);

  const v_leftY = [3, [3640903312, [26]]];

  const v__inl12_x = v_leftY;
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
          })(v__inl12_x[1])
        ];
      }
      case 4: {
        return v__inl12_x;
      }
    }
  })(v__inl12_x);

  const v_leftX = [3, [3657680931, [25]]];

  const v__inl7_x = v_leftX;
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
          })(v__inl7_x[1])
        ];
      }
      case 4: {
        return v__inl7_x;
      }
    }
  })(v__inl7_x);

  const v_leftSrc = [3, [24]];

  const v__inl18_x = v_leftSrc;
  const v_mappedA = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2252990199, [27]]];
      }
      case 4: {
        return v__inl18_x;
      }
    }
  })(v__inl18_x);

  const v__inl15_x = v_leftSrc;
  const v_mappedB = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2269767818, [28]]];
      }
      case 4: {
        return v__inl15_x;
      }
    }
  })(v__inl15_x);

  const v__inl26_e = v_mappedA;
  const v_render = (s => {
    switch (s[0]) {
      case 3: {
        const v__do_e_6 = s[1];
        return [3, v__do_e_6];
      }
      case 4: {
        const v_r01 = s[1];
        let v__inl56_scrut;
        $join55: {
          const v__inl31_e = v_mappedB;
          const __s = v_tagged(
            "mappedB",
            (s => {
              switch (s[0]) {
                case 3: {
                  {
                    const __s = v__inl31_e[1];
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
                  return String(v__inl31_e[1]);
                }
              }
            })(v__inl31_e)
          );
          switch (__s[0]) {
            case 3: {
              const v__inl32__do_e_2 = __s[1];
              return [3, v__inl32__do_e_2];
            }
            case 4: {
              const v__inl33_line = __s[1];
              v__inl56_scrut = __concat(v_r01, v__inl33_line);
              break $join55;
            }
          }
        }
        switch (v__inl56_scrut[0]) {
          case 3: {
            return v__inl56_scrut;
          }
          case 4: {
            let v__inl58_scrut;
            $join57: {
              const v__inl38_e = v_mappedOk;
              const __s = v_tagged(
                "mappedOk",
                (s => {
                  switch (s[0]) {
                    case 3: {
                      {
                        const __s = v__inl38_e[1];
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
                      return String(v__inl38_e[1]);
                    }
                  }
                })(v__inl38_e)
              );
              switch (__s[0]) {
                case 3: {
                  const v__inl39__do_e_2 = __s[1];
                  return [3, v__inl39__do_e_2];
                }
                case 4: {
                  const v__inl40_line = __s[1];
                  v__inl58_scrut = __concat(v__inl56_scrut[1], v__inl40_line);
                  break $join57;
                }
              }
            }
            switch (v__inl58_scrut[0]) {
              case 3: {
                return v__inl58_scrut;
              }
              case 4: {
                let v__inl60_scrut;
                $join59: {
                  const v__inl45_e = v_remappedX;
                  const __s = v_tagged(
                    "remappedX",
                    (s => {
                      switch (s[0]) {
                        case 3: {
                          {
                            const __s = v__inl45_e[1];
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
                          return String(v__inl45_e[1]);
                        }
                      }
                    })(v__inl45_e)
                  );
                  switch (__s[0]) {
                    case 3: {
                      const v__inl46__do_e_2 = __s[1];
                      return [3, v__inl46__do_e_2];
                    }
                    case 4: {
                      const v__inl47_line = __s[1];
                      v__inl60_scrut = __concat(
                        v__inl58_scrut[1],
                        v__inl47_line
                      );
                      break $join59;
                    }
                  }
                }
                switch (v__inl60_scrut[0]) {
                  case 3: {
                    return v__inl60_scrut;
                  }
                  case 4: {
                    {
                      const v__inl52_e = v_remappedY;
                      const __s = v_tagged(
                        "remappedY",
                        (s => {
                          switch (s[0]) {
                            case 3: {
                              {
                                const __s = v__inl52_e[1];
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
                              return String(v__inl52_e[1]);
                            }
                          }
                        })(v__inl52_e)
                      );
                      switch (__s[0]) {
                        case 3: {
                          const v__inl53__do_e_2 = __s[1];
                          return [3, v__inl53__do_e_2];
                        }
                        case 4: {
                          const v__inl54_line = __s[1];
                          return __concat(v__inl60_scrut[1], v__inl54_line);
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
              const __s = v__inl26_e[1];
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
            return String(v__inl26_e[1]);
          }
        }
      })(v__inl26_e)
    )
  );

  const v__apply__df_handleErrorIO_3 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 29: {
          return v__x;
        }
        case 30: {
          const v__pk_30 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_30;
          continue;
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_3 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_3(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_3(
            v__k,
            [7, "STRING_TOO_LONG", [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [30, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_7 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 31: {
          return v__x;
        }
        case 32: {
          const v__pk_32 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_32;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_7 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_7(v__k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v__apply__df_andThenIO_7(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [32, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl63_x = v_render;
  const main = v__cps__df_handleErrorIO_3(
    v__cps__df_andThenIO_7(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v__inl63_x[1]];
          }
          case 4: {
            return [5, v__inl63_x[1]];
          }
        }
      })(v__inl63_x),
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
