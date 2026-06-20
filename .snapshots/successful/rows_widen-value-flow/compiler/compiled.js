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

  const v__inl3___input = v_vStr;
  const v_strWiden = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [1615808600, v__inl3___input[1]]];
      }
      case 4: {
        return v__inl3___input;
      }
    }
  })(v__inl3___input);

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

  const v_nestedUnion = v_m => {
    switch (v_m[0]) {
      case 11: {
        const v__inl6___input = v_vFirst;
        switch (v__inl6___input[0]) {
          case 3: {
            return [3, [925038822, v__inl6___input[1]]];
          }
          case 4: {
            return v__inl6___input;
          }
        }
      }
      case 12: {
        {
          const __s = v_m[1];
          switch (__s[0]) {
            case 1: {
              const v__inl9___input = v_vErrA;
              switch (v__inl9___input[0]) {
                case 3: {
                  return [3, [2252990199, v__inl9___input[1]]];
                }
                case 4: {
                  return v__inl9___input;
                }
              }
            }
            case 2: {
              const v__inl12___input = v_vSecond;
              switch (v__inl12___input[0]) {
                case 3: {
                  return [3, [925038822, v__inl12___input[1]]];
                }
                case 4: {
                  return v__inl12___input;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__inl29_x = v_vErrB;
  const v_letBody = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2269767818, v__inl29_x[1]]];
      }
      case 4: {
        return v__inl29_x;
      }
    }
  })(v__inl29_x);

  const v__inl24___input = v_vOkA;
  const v_defBodyRight = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2252990199, v__inl24___input[1]]];
      }
      case 4: {
        return v__inl24___input;
      }
    }
  })(v__inl24___input);

  const v__inl21___input = v_vErrA;
  const v_defBodyLeft = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2252990199, v__inl21___input[1]]];
      }
      case 4: {
        return v__inl21___input;
      }
    }
  })(v__inl21___input);

  const v_caseUnion = v_flag => {
    switch (v_flag[0]) {
      case 1: {
        const v__inl15___input = v_vErrA;
        switch (v__inl15___input[0]) {
          case 3: {
            return [3, [2252990199, v__inl15___input[1]]];
          }
          case 4: {
            return v__inl15___input;
          }
        }
      }
      case 2: {
        const v__inl18___input = v_vErrB;
        switch (v__inl18___input[0]) {
          case 3: {
            return [3, [2269767818, v__inl18___input[1]]];
          }
          case 4: {
            return v__inl18___input;
          }
        }
      }
    }
  };

  const v__inl34_e = v_defBodyLeft;
  const v_render = (s => {
    switch (s[0]) {
      case 3: {
        const v__do_e_10 = s[1];
        return [3, v__do_e_10];
      }
      case 4: {
        const v_r01 = s[1];
        let v__inl92_scrut;
        $join91: {
          const v__inl39_e = v_defBodyRight;
          const __s = v_tagged(
            "defBodyRight",
            (s => {
              switch (s[0]) {
                case 3: {
                  {
                    const __s = v__inl39_e[1];
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
                  return String(v__inl39_e[1]);
                }
              }
            })(v__inl39_e)
          );
          switch (__s[0]) {
            case 3: {
              const v__inl40__do_e_2 = __s[1];
              return [3, v__inl40__do_e_2];
            }
            case 4: {
              const v__inl41_line = __s[1];
              v__inl92_scrut = __concat(v_r01, v__inl41_line);
              break $join91;
            }
          }
        }
        switch (v__inl92_scrut[0]) {
          case 3: {
            return v__inl92_scrut;
          }
          case 4: {
            let v__inl94_scrut;
            $join93: {
              const v__inl46_e = v_letBody;
              const __s = v_tagged(
                "letBody",
                (s => {
                  switch (s[0]) {
                    case 3: {
                      {
                        const __s = v__inl46_e[1];
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
                      return String(v__inl46_e[1]);
                    }
                  }
                })(v__inl46_e)
              );
              switch (__s[0]) {
                case 3: {
                  const v__inl47__do_e_2 = __s[1];
                  return [3, v__inl47__do_e_2];
                }
                case 4: {
                  const v__inl48_line = __s[1];
                  v__inl94_scrut = __concat(v__inl92_scrut[1], v__inl48_line);
                  break $join93;
                }
              }
            }
            switch (v__inl94_scrut[0]) {
              case 3: {
                return v__inl94_scrut;
              }
              case 4: {
                let v__inl96_scrut;
                $join95: {
                  const v__inl53_e = v_caseUnion([1]);
                  const __s = v_tagged(
                    "caseTrue",
                    (s => {
                      switch (s[0]) {
                        case 3: {
                          {
                            const __s = v__inl53_e[1];
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
                          return String(v__inl53_e[1]);
                        }
                      }
                    })(v__inl53_e)
                  );
                  switch (__s[0]) {
                    case 3: {
                      const v__inl54__do_e_2 = __s[1];
                      return [3, v__inl54__do_e_2];
                    }
                    case 4: {
                      const v__inl55_line = __s[1];
                      v__inl96_scrut = __concat(
                        v__inl94_scrut[1],
                        v__inl55_line
                      );
                      break $join95;
                    }
                  }
                }
                switch (v__inl96_scrut[0]) {
                  case 3: {
                    return v__inl96_scrut;
                  }
                  case 4: {
                    let v__inl98_scrut;
                    $join97: {
                      const v__inl60_e = v_caseUnion([2]);
                      const __s = v_tagged(
                        "caseFalse",
                        (s => {
                          switch (s[0]) {
                            case 3: {
                              {
                                const __s = v__inl60_e[1];
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
                              return String(v__inl60_e[1]);
                            }
                          }
                        })(v__inl60_e)
                      );
                      switch (__s[0]) {
                        case 3: {
                          const v__inl61__do_e_2 = __s[1];
                          return [3, v__inl61__do_e_2];
                        }
                        case 4: {
                          const v__inl62_line = __s[1];
                          v__inl98_scrut = __concat(
                            v__inl96_scrut[1],
                            v__inl62_line
                          );
                          break $join97;
                        }
                      }
                    }
                    switch (v__inl98_scrut[0]) {
                      case 3: {
                        return v__inl98_scrut;
                      }
                      case 4: {
                        let v__inl100_scrut;
                        $join99: {
                          const v__inl67_e = v_nestedUnion([11]);
                          const __s = v_tagged(
                            "nestedNothing",
                            (s => {
                              switch (s[0]) {
                                case 3: {
                                  const v__inl63___pa0 = s[1];
                                  switch (v__inl63___pa0[0]) {
                                    case 925038822: {
                                      {
                                        const __s = v__inl63___pa0[1];
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
                                  return String(v__inl67_e[1]);
                                }
                              }
                            })(v__inl67_e)
                          );
                          switch (__s[0]) {
                            case 3: {
                              const v__inl68__do_e_2 = __s[1];
                              return [3, v__inl68__do_e_2];
                            }
                            case 4: {
                              const v__inl69_line = __s[1];
                              v__inl100_scrut = __concat(
                                v__inl98_scrut[1],
                                v__inl69_line
                              );
                              break $join99;
                            }
                          }
                        }
                        switch (v__inl100_scrut[0]) {
                          case 3: {
                            return v__inl100_scrut;
                          }
                          case 4: {
                            let v__inl102_scrut;
                            $join101: {
                              const v__inl74_e = v_nestedUnion([12, [1]]);
                              const __s = v_tagged(
                                "nestedJustTrue",
                                (s => {
                                  switch (s[0]) {
                                    case 3: {
                                      const v__inl70___pa0 = s[1];
                                      switch (v__inl70___pa0[0]) {
                                        case 925038822: {
                                          {
                                            const __s = v__inl70___pa0[1];
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
                                      return String(v__inl74_e[1]);
                                    }
                                  }
                                })(v__inl74_e)
                              );
                              switch (__s[0]) {
                                case 3: {
                                  const v__inl75__do_e_2 = __s[1];
                                  return [3, v__inl75__do_e_2];
                                }
                                case 4: {
                                  const v__inl76_line = __s[1];
                                  v__inl102_scrut = __concat(
                                    v__inl100_scrut[1],
                                    v__inl76_line
                                  );
                                  break $join101;
                                }
                              }
                            }
                            switch (v__inl102_scrut[0]) {
                              case 3: {
                                return v__inl102_scrut;
                              }
                              case 4: {
                                let v__inl104_scrut;
                                $join103: {
                                  const v__inl81_e = v_nestedUnion([12, [2]]);
                                  const __s = v_tagged(
                                    "nestedJustFalse",
                                    (s => {
                                      switch (s[0]) {
                                        case 3: {
                                          const v__inl77___pa0 = s[1];
                                          switch (v__inl77___pa0[0]) {
                                            case 925038822: {
                                              {
                                                const __s = v__inl77___pa0[1];
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
                                          return String(v__inl81_e[1]);
                                        }
                                      }
                                    })(v__inl81_e)
                                  );
                                  switch (__s[0]) {
                                    case 3: {
                                      const v__inl82__do_e_2 = __s[1];
                                      return [3, v__inl82__do_e_2];
                                    }
                                    case 4: {
                                      const v__inl83_line = __s[1];
                                      v__inl104_scrut = __concat(
                                        v__inl102_scrut[1],
                                        v__inl83_line
                                      );
                                      break $join103;
                                    }
                                  }
                                }
                                switch (v__inl104_scrut[0]) {
                                  case 3: {
                                    return v__inl104_scrut;
                                  }
                                  case 4: {
                                    {
                                      const v__inl88_e = v_strWiden;
                                      const __s = v_tagged(
                                        "strWiden",
                                        (s => {
                                          switch (s[0]) {
                                            case 3: {
                                              const v__inl84___pa0 = s[1];
                                              switch (v__inl84___pa0[0]) {
                                                case 1615808600: {
                                                  return v__inl84___pa0[1];
                                                }
                                                case 2252990199: {
                                                  return "ErrA";
                                                }
                                              }
                                            }
                                            case 4: {
                                              return String(v__inl88_e[1]);
                                            }
                                          }
                                        })(v__inl88_e)
                                      );
                                      switch (__s[0]) {
                                        case 3: {
                                          const v__inl89__do_e_2 = __s[1];
                                          return [3, v__inl89__do_e_2];
                                        }
                                        case 4: {
                                          const v__inl90_line = __s[1];
                                          return __concat(
                                            v__inl104_scrut[1],
                                            v__inl90_line
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
              const __s = v__inl34_e[1];
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
            return String(v__inl34_e[1]);
          }
        }
      })(v__inl34_e)
    )
  );

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 28: {
          return v__x;
        }
        case 29: {
          const v__pk_29 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_29;
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
            [7, "STRING_TOO_LONG", [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [29, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_4 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 30: {
          return v__x;
        }
        case 31: {
          const v__pk_31 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_31;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_4(v__k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v__apply__df_andThenIO_4(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [31, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__inl107_x = v_render;
  const main = v__cps__df_handleErrorIO_0(
    v__cps__df_andThenIO_4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v__inl107_x[1]];
          }
          case 4: {
            return [5, v__inl107_x[1]];
          }
        }
      })(v__inl107_x),
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
