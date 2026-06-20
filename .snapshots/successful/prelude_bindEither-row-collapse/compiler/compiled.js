"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const v__inl69___input = [3, "kS"];
  const v__inl77_x = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [1615808600, v__inl69___input[1]]];
      }
      case 4: {
        return v__inl69___input;
      }
    }
  })(v__inl69___input);
  const v_wE2str = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl77_x;
      }
      case 4: {
        const v__inl74___input = [4, v__inl77_x[1]];
        switch (v__inl74___input[0]) {
          case 3: {
            return [3, [2252990199, v__inl74___input[1]]];
          }
          case 4: {
            return v__inl74___input;
          }
        }
      }
    }
  })(v__inl77_x);

  const v__inl95___input = [3, [24]];
  const v_twoE2 = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2252990199, v__inl95___input[1]]];
      }
      case 4: {
        return v__inl95___input;
      }
    }
  })(v__inl95___input);

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

  const v__inl137___input = [3, [24]];
  const v_strE2 = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2252990199, v__inl137___input[1]]];
      }
      case 4: {
        return v__inl137___input;
      }
    }
  })(v__inl137___input);

  const v_seedT = [4, 4 | 0];

  const v__inl112_x = v_seedT;
  const v_twoOk = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [925038822, v__inl112_x[1]]];
      }
      case 4: {
        const v__inl109___input = [4, v__inl112_x[1]];
        switch (v__inl109___input[0]) {
          case 3: {
            return [3, [2252990199, v__inl109___input[1]]];
          }
          case 4: {
            return v__inl109___input;
          }
        }
      }
    }
  })(v__inl112_x);

  const v__inl45_x = v_seedT;
  const v__inl51_x = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [925038822, v__inl45_x[1]]];
      }
      case 4: {
        const v__inl42___input = [4, v__inl45_x[1]];
        switch (v__inl42___input[0]) {
          case 3: {
            return [3, [1615808600, v__inl42___input[1]]];
          }
          case 4: {
            return v__inl42___input;
          }
        }
      }
    }
  })(v__inl45_x);
  const v_wE3 = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl51_x;
      }
      case 4: {
        const v__inl48___input = [3, [24]];
        switch (v__inl48___input[0]) {
          case 3: {
            return [3, [2252990199, v__inl48___input[1]]];
          }
          case 4: {
            return v__inl48___input;
          }
        }
      }
    }
  })(v__inl51_x);

  const v__inl83_x = v_seedT;
  const v__inl89_x = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [925038822, v__inl83_x[1]]];
      }
      case 4: {
        const v__inl80___input = [4, v__inl83_x[1]];
        switch (v__inl80___input[0]) {
          case 3: {
            return [3, [1615808600, v__inl80___input[1]]];
          }
          case 4: {
            return v__inl80___input;
          }
        }
      }
    }
  })(v__inl83_x);
  const v_wOk = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl89_x;
      }
      case 4: {
        const v__inl86___input = [4, v__inl89_x[1]];
        switch (v__inl86___input[0]) {
          case 3: {
            return [3, [2252990199, v__inl86___input[1]]];
          }
          case 4: {
            return v__inl86___input;
          }
        }
      }
    }
  })(v__inl89_x);

  const v_seedSecond = [3, [27]];

  const v__inl118_x = v_seedSecond;
  const v_twoSecond = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [925038822, v__inl118_x[1]]];
      }
      case 4: {
        const v__inl115___input = [4, v__inl118_x[1]];
        switch (v__inl115___input[0]) {
          case 3: {
            return [3, [2252990199, v__inl115___input[1]]];
          }
          case 4: {
            return v__inl115___input;
          }
        }
      }
    }
  })(v__inl118_x);

  const v_seedS = [4, 3 | 0];

  const v__inl9_x = v_seedS;
  const v_strIdem = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl9_x;
      }
      case 4: {
        return [3, "kS"];
      }
    }
  })(v__inl9_x);

  const v__inl154_x = v_seedS;
  const v_strOk = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [1615808600, v__inl154_x[1]]];
      }
      case 4: {
        const v__inl151___input = [4, v__inl154_x[1]];
        switch (v__inl151___input[0]) {
          case 3: {
            return [3, [2252990199, v__inl151___input[1]]];
          }
          case 4: {
            return v__inl151___input;
          }
        }
      }
    }
  })(v__inl154_x);

  const v_seedNever = [4, 1 | 0];

  const v_seedLeftS = [3, "seedS"];

  const v__inl148_x = v_seedLeftS;
  const v_strE1 = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [1615808600, v__inl148_x[1]]];
      }
      case 4: {
        const v__inl145___input = [4, v__inl148_x[1]];
        switch (v__inl145___input[0]) {
          case 3: {
            return [3, [2252990199, v__inl145___input[1]]];
          }
          case 4: {
            return v__inl145___input;
          }
        }
      }
    }
  })(v__inl148_x);

  const v_seedLeftA = [3, [24]];

  const v_seedFirst = [3, [26]];

  const v__inl106_x = v_seedFirst;
  const v_twoFirst = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [925038822, v__inl106_x[1]]];
      }
      case 4: {
        const v__inl103___input = [4, v__inl106_x[1]];
        switch (v__inl103___input[0]) {
          case 3: {
            return [3, [2252990199, v__inl103___input[1]]];
          }
          case 4: {
            return v__inl103___input;
          }
        }
      }
    }
  })(v__inl106_x);

  const v__inl60_x = v_seedFirst;
  const v__inl66_x = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [925038822, v__inl60_x[1]]];
      }
      case 4: {
        const v__inl57___input = [4, v__inl60_x[1]];
        switch (v__inl57___input[0]) {
          case 3: {
            return [3, [1615808600, v__inl57___input[1]]];
          }
          case 4: {
            return v__inl57___input;
          }
        }
      }
    }
  })(v__inl60_x);
  const v_wE1 = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl66_x;
      }
      case 4: {
        const v__inl63___input = [4, v__inl66_x[1]];
        switch (v__inl63___input[0]) {
          case 3: {
            return [3, [2252990199, v__inl63___input[1]]];
          }
          case 4: {
            return v__inl63___input;
          }
        }
      }
    }
  })(v__inl66_x);

  const v_seedA = [4, 2 | 0];

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

  const v__inl18_x = v_seedNever;
  const v_pureNever = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl18_x;
      }
      case 4: {
        return [4, v__inl18_x[1]];
      }
    }
  })(v__inl18_x);

  const v__inl15_x = v_seedA;
  const v_nevRightOk = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl15_x;
      }
      case 4: {
        return [4, v__inl15_x[1]];
      }
    }
  })(v__inl15_x);

  const v__inl12_x = v_seedLeftA;
  const v_nevRightE1 = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl12_x;
      }
      case 4: {
        return [4, v__inl12_x[1]];
      }
    }
  })(v__inl12_x);

  const v__inl30_x = v_seedNever;
  const v_nevOk = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl30_x;
      }
      case 4: {
        return [4, v__inl30_x[1]];
      }
    }
  })(v__inl30_x);

  const v__inl27_x = v_seedNever;
  const v_nevFail = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl27_x;
      }
      case 4: {
        return [3, [24]];
      }
    }
  })(v__inl27_x);

  const v__inl24_x = v_seedA;
  const v_idemE2 = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl24_x;
      }
      case 4: {
        return [3, [24]];
      }
    }
  })(v__inl24_x);

  const v__inl21_x = v_seedLeftA;
  const v_idemE1 = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl21_x;
      }
      case 4: {
        return [3, [24]];
      }
    }
  })(v__inl21_x);

  const v__inl6_x = v_seedT;
  const v_idem2Second = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl6_x;
      }
      case 4: {
        return [3, [27]];
      }
    }
  })(v__inl6_x);

  const v__inl3_x = v_seedFirst;
  const v_idem2First = (s => {
    switch (s[0]) {
      case 3: {
        return v__inl3_x;
      }
      case 4: {
        return [3, [27]];
      }
    }
  })(v__inl3_x);

  const v__inl129___input = [3, [25]];
  const v_abE2 = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2269767818, v__inl129___input[1]]];
      }
      case 4: {
        return v__inl129___input;
      }
    }
  })(v__inl129___input);

  const v_abE1 = [3, [2252990199, [24]]];

  const v__inl157_e = v_nevOk;
  const v_render = (s => {
    switch (s[0]) {
      case 3: {
        const v__do_e_24 = s[1];
        return [3, v__do_e_24];
      }
      case 4: {
        const v_r01 = s[1];
        let v__inl297_scrut;
        $join296: {
          const v__inl160_e = v_nevFail;
          const __s = v_tagged(
            "nevFail",
            (s => {
              switch (s[0]) {
                case 3: {
                  return "ErrA";
                }
                case 4: {
                  return String(v__inl160_e[1]);
                }
              }
            })(v__inl160_e)
          );
          switch (__s[0]) {
            case 3: {
              const v__inl161__do_e_2 = __s[1];
              return [3, v__inl161__do_e_2];
            }
            case 4: {
              const v__inl162_line = __s[1];
              v__inl297_scrut = __concat(v_r01, v__inl162_line);
              break $join296;
            }
          }
        }
        switch (v__inl297_scrut[0]) {
          case 3: {
            return v__inl297_scrut;
          }
          case 4: {
            let v__inl299_scrut;
            $join298: {
              const v__inl165_e = v_nevRightOk;
              const __s = v_tagged(
                "nevRightOk",
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return "ErrA";
                    }
                    case 4: {
                      return String(v__inl165_e[1]);
                    }
                  }
                })(v__inl165_e)
              );
              switch (__s[0]) {
                case 3: {
                  const v__inl166__do_e_2 = __s[1];
                  return [3, v__inl166__do_e_2];
                }
                case 4: {
                  const v__inl167_line = __s[1];
                  v__inl299_scrut = __concat(
                    v__inl297_scrut[1],
                    v__inl167_line
                  );
                  break $join298;
                }
              }
            }
            switch (v__inl299_scrut[0]) {
              case 3: {
                return v__inl299_scrut;
              }
              case 4: {
                let v__inl301_scrut;
                $join300: {
                  const v__inl170_e = v_nevRightE1;
                  const __s = v_tagged(
                    "nevRightE1",
                    (s => {
                      switch (s[0]) {
                        case 3: {
                          return "ErrA";
                        }
                        case 4: {
                          return String(v__inl170_e[1]);
                        }
                      }
                    })(v__inl170_e)
                  );
                  switch (__s[0]) {
                    case 3: {
                      const v__inl171__do_e_2 = __s[1];
                      return [3, v__inl171__do_e_2];
                    }
                    case 4: {
                      const v__inl172_line = __s[1];
                      v__inl301_scrut = __concat(
                        v__inl299_scrut[1],
                        v__inl172_line
                      );
                      break $join300;
                    }
                  }
                }
                switch (v__inl301_scrut[0]) {
                  case 3: {
                    return v__inl301_scrut;
                  }
                  case 4: {
                    let v__inl303_scrut;
                    $join302: {
                      const v__inl173_e = v_pureNever;
                      const __s = v_tagged("pureNever", String(v__inl173_e[1]));
                      switch (__s[0]) {
                        case 3: {
                          const v__inl174__do_e_2 = __s[1];
                          return [3, v__inl174__do_e_2];
                        }
                        case 4: {
                          const v__inl175_line = __s[1];
                          v__inl303_scrut = __concat(
                            v__inl301_scrut[1],
                            v__inl175_line
                          );
                          break $join302;
                        }
                      }
                    }
                    switch (v__inl303_scrut[0]) {
                      case 3: {
                        return v__inl303_scrut;
                      }
                      case 4: {
                        let v__inl305_scrut;
                        $join304: {
                          const v__inl180_e = v_strOk;
                          const __s = v_tagged(
                            "strOk",
                            (s => {
                              switch (s[0]) {
                                case 3: {
                                  const v__inl176___pa0 = s[1];
                                  switch (v__inl176___pa0[0]) {
                                    case 1615808600: {
                                      return v__inl176___pa0[1];
                                    }
                                    case 2252990199: {
                                      return "ErrA";
                                    }
                                  }
                                }
                                case 4: {
                                  return String(v__inl180_e[1]);
                                }
                              }
                            })(v__inl180_e)
                          );
                          switch (__s[0]) {
                            case 3: {
                              const v__inl181__do_e_2 = __s[1];
                              return [3, v__inl181__do_e_2];
                            }
                            case 4: {
                              const v__inl182_line = __s[1];
                              v__inl305_scrut = __concat(
                                v__inl303_scrut[1],
                                v__inl182_line
                              );
                              break $join304;
                            }
                          }
                        }
                        switch (v__inl305_scrut[0]) {
                          case 3: {
                            return v__inl305_scrut;
                          }
                          case 4: {
                            let v__inl307_scrut;
                            $join306: {
                              const v__inl187_e = v_strE1;
                              const __s = v_tagged(
                                "strE1",
                                (s => {
                                  switch (s[0]) {
                                    case 3: {
                                      const v__inl183___pa0 = s[1];
                                      switch (v__inl183___pa0[0]) {
                                        case 1615808600: {
                                          return v__inl183___pa0[1];
                                        }
                                        case 2252990199: {
                                          return "ErrA";
                                        }
                                      }
                                    }
                                    case 4: {
                                      return String(v__inl187_e[1]);
                                    }
                                  }
                                })(v__inl187_e)
                              );
                              switch (__s[0]) {
                                case 3: {
                                  const v__inl188__do_e_2 = __s[1];
                                  return [3, v__inl188__do_e_2];
                                }
                                case 4: {
                                  const v__inl189_line = __s[1];
                                  v__inl307_scrut = __concat(
                                    v__inl305_scrut[1],
                                    v__inl189_line
                                  );
                                  break $join306;
                                }
                              }
                            }
                            switch (v__inl307_scrut[0]) {
                              case 3: {
                                return v__inl307_scrut;
                              }
                              case 4: {
                                let v__inl309_scrut;
                                $join308: {
                                  const v__inl194_e = v_strE2;
                                  const __s = v_tagged(
                                    "strE2",
                                    (s => {
                                      switch (s[0]) {
                                        case 3: {
                                          const v__inl190___pa0 = s[1];
                                          switch (v__inl190___pa0[0]) {
                                            case 1615808600: {
                                              return v__inl190___pa0[1];
                                            }
                                            case 2252990199: {
                                              return "ErrA";
                                            }
                                          }
                                        }
                                        case 4: {
                                          return String(v__inl194_e[1]);
                                        }
                                      }
                                    })(v__inl194_e)
                                  );
                                  switch (__s[0]) {
                                    case 3: {
                                      const v__inl195__do_e_2 = __s[1];
                                      return [3, v__inl195__do_e_2];
                                    }
                                    case 4: {
                                      const v__inl196_line = __s[1];
                                      v__inl309_scrut = __concat(
                                        v__inl307_scrut[1],
                                        v__inl196_line
                                      );
                                      break $join308;
                                    }
                                  }
                                }
                                switch (v__inl309_scrut[0]) {
                                  case 3: {
                                    return v__inl309_scrut;
                                  }
                                  case 4: {
                                    let v__inl311_scrut;
                                    $join310: {
                                      const v__inl199_e = v_strIdem;
                                      const __s = v_tagged(
                                        "strIdem",
                                        (s => {
                                          switch (s[0]) {
                                            case 3: {
                                              return v__inl199_e[1];
                                            }
                                            case 4: {
                                              return String(v__inl199_e[1]);
                                            }
                                          }
                                        })(v__inl199_e)
                                      );
                                      switch (__s[0]) {
                                        case 3: {
                                          const v__inl200__do_e_2 = __s[1];
                                          return [3, v__inl200__do_e_2];
                                        }
                                        case 4: {
                                          const v__inl201_line = __s[1];
                                          v__inl311_scrut = __concat(
                                            v__inl309_scrut[1],
                                            v__inl201_line
                                          );
                                          break $join310;
                                        }
                                      }
                                    }
                                    switch (v__inl311_scrut[0]) {
                                      case 3: {
                                        return v__inl311_scrut;
                                      }
                                      case 4: {
                                        let v__inl313_scrut;
                                        $join312: {
                                          const v__inl206_e = v_abE1;
                                          const __s = v_tagged(
                                            "abE1",
                                            (s => {
                                              switch (s[0]) {
                                                case 3: {
                                                  {
                                                    const __s = v__inl206_e[1];
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
                                                  return String(v__inl206_e[1]);
                                                }
                                              }
                                            })(v__inl206_e)
                                          );
                                          switch (__s[0]) {
                                            case 3: {
                                              const v__inl207__do_e_2 = __s[1];
                                              return [3, v__inl207__do_e_2];
                                            }
                                            case 4: {
                                              const v__inl208_line = __s[1];
                                              v__inl313_scrut = __concat(
                                                v__inl311_scrut[1],
                                                v__inl208_line
                                              );
                                              break $join312;
                                            }
                                          }
                                        }
                                        switch (v__inl313_scrut[0]) {
                                          case 3: {
                                            return v__inl313_scrut;
                                          }
                                          case 4: {
                                            let v__inl315_scrut;
                                            $join314: {
                                              const v__inl213_e = v_abE2;
                                              const __s = v_tagged(
                                                "abE2",
                                                (s => {
                                                  switch (s[0]) {
                                                    case 3: {
                                                      {
                                                        const __s = v__inl213_e[1];
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
                                                      return String(
                                                        v__inl213_e[1]
                                                      );
                                                    }
                                                  }
                                                })(v__inl213_e)
                                              );
                                              switch (__s[0]) {
                                                case 3: {
                                                  const v__inl214__do_e_2 = __s[1];
                                                  return [3, v__inl214__do_e_2];
                                                }
                                                case 4: {
                                                  const v__inl215_line = __s[1];
                                                  v__inl315_scrut = __concat(
                                                    v__inl313_scrut[1],
                                                    v__inl215_line
                                                  );
                                                  break $join314;
                                                }
                                              }
                                            }
                                            switch (v__inl315_scrut[0]) {
                                              case 3: {
                                                return v__inl315_scrut;
                                              }
                                              case 4: {
                                                let v__inl317_scrut;
                                                $join316: {
                                                  const v__inl220_e = v_twoFirst;
                                                  const __s = v_tagged(
                                                    "twoFirst",
                                                    (s => {
                                                      switch (s[0]) {
                                                        case 3: {
                                                          const v__inl216___pa0 = s[1];
                                                          switch (v__inl216___pa0[0]) {
                                                            case 925038822: {
                                                              {
                                                                const __s = v__inl216___pa0[1];
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
                                                          return String(
                                                            v__inl220_e[1]
                                                          );
                                                        }
                                                      }
                                                    })(v__inl220_e)
                                                  );
                                                  switch (__s[0]) {
                                                    case 3: {
                                                      const v__inl221__do_e_2 = __s[1];
                                                      return [
                                                        3,
                                                        v__inl221__do_e_2
                                                      ];
                                                    }
                                                    case 4: {
                                                      const v__inl222_line = __s[1];
                                                      v__inl317_scrut = __concat(
                                                        v__inl315_scrut[1],
                                                        v__inl222_line
                                                      );
                                                      break $join316;
                                                    }
                                                  }
                                                }
                                                switch (v__inl317_scrut[0]) {
                                                  case 3: {
                                                    return v__inl317_scrut;
                                                  }
                                                  case 4: {
                                                    let v__inl319_scrut;
                                                    $join318: {
                                                      const v__inl227_e = v_twoSecond;
                                                      const __s = v_tagged(
                                                        "twoSecond",
                                                        (s => {
                                                          switch (s[0]) {
                                                            case 3: {
                                                              const v__inl223___pa0 = s[1];
                                                              switch (v__inl223___pa0[0]) {
                                                                case 925038822: {
                                                                  {
                                                                    const __s = v__inl223___pa0[1];
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
                                                              return String(
                                                                v__inl227_e[1]
                                                              );
                                                            }
                                                          }
                                                        })(v__inl227_e)
                                                      );
                                                      switch (__s[0]) {
                                                        case 3: {
                                                          const v__inl228__do_e_2 = __s[1];
                                                          return [
                                                            3,
                                                            v__inl228__do_e_2
                                                          ];
                                                        }
                                                        case 4: {
                                                          const v__inl229_line = __s[1];
                                                          v__inl319_scrut = __concat(
                                                            v__inl317_scrut[1],
                                                            v__inl229_line
                                                          );
                                                          break $join318;
                                                        }
                                                      }
                                                    }
                                                    switch (v__inl319_scrut[0]) {
                                                      case 3: {
                                                        return v__inl319_scrut;
                                                      }
                                                      case 4: {
                                                        let v__inl321_scrut;
                                                        $join320: {
                                                          const v__inl234_e = v_twoE2;
                                                          const __s = v_tagged(
                                                            "twoE2",
                                                            (s => {
                                                              switch (s[0]) {
                                                                case 3: {
                                                                  const v__inl230___pa0 = s[1];
                                                                  switch (v__inl230___pa0[0]) {
                                                                    case 925038822: {
                                                                      {
                                                                        const __s = v__inl230___pa0[1];
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
                                                                  return String(
                                                                    v__inl234_e[1]
                                                                  );
                                                                }
                                                              }
                                                            })(v__inl234_e)
                                                          );
                                                          switch (__s[0]) {
                                                            case 3: {
                                                              const v__inl235__do_e_2 = __s[1];
                                                              return [
                                                                3,
                                                                v__inl235__do_e_2
                                                              ];
                                                            }
                                                            case 4: {
                                                              const v__inl236_line = __s[1];
                                                              v__inl321_scrut = __concat(
                                                                v__inl319_scrut[1],
                                                                v__inl236_line
                                                              );
                                                              break $join320;
                                                            }
                                                          }
                                                        }
                                                        switch (v__inl321_scrut[0]) {
                                                          case 3: {
                                                            return v__inl321_scrut;
                                                          }
                                                          case 4: {
                                                            let v__inl323_scrut;
                                                            $join322: {
                                                              const v__inl241_e = v_twoOk;
                                                              const __s = v_tagged(
                                                                "twoOk",
                                                                (s => {
                                                                  switch (s[0]) {
                                                                    case 3: {
                                                                      const v__inl237___pa0 = s[1];
                                                                      switch (v__inl237___pa0[0]) {
                                                                        case 925038822: {
                                                                          {
                                                                            const __s = v__inl237___pa0[1];
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
                                                                      return String(
                                                                        v__inl241_e[1]
                                                                      );
                                                                    }
                                                                  }
                                                                })(v__inl241_e)
                                                              );
                                                              switch (__s[0]) {
                                                                case 3: {
                                                                  const v__inl242__do_e_2 = __s[1];
                                                                  return [
                                                                    3,
                                                                    v__inl242__do_e_2
                                                                  ];
                                                                }
                                                                case 4: {
                                                                  const v__inl243_line = __s[1];
                                                                  v__inl323_scrut = __concat(
                                                                    v__inl321_scrut[1],
                                                                    v__inl243_line
                                                                  );
                                                                  break $join322;
                                                                }
                                                              }
                                                            }
                                                            switch (v__inl323_scrut[0]) {
                                                              case 3: {
                                                                return v__inl323_scrut;
                                                              }
                                                              case 4: {
                                                                let v__inl325_scrut;
                                                                $join324: {
                                                                  const v__inl246_e = v_idemE1;
                                                                  const __s = v_tagged(
                                                                    "idemE1",
                                                                    (s => {
                                                                      switch (s[0]) {
                                                                        case 3: {
                                                                          return "ErrA";
                                                                        }
                                                                        case 4: {
                                                                          return String(
                                                                            v__inl246_e[1]
                                                                          );
                                                                        }
                                                                      }
                                                                    })(
                                                                      v__inl246_e
                                                                    )
                                                                  );
                                                                  switch (__s[0]) {
                                                                    case 3: {
                                                                      const v__inl247__do_e_2 = __s[1];
                                                                      return [
                                                                        3,
                                                                        v__inl247__do_e_2
                                                                      ];
                                                                    }
                                                                    case 4: {
                                                                      const v__inl248_line = __s[1];
                                                                      v__inl325_scrut = __concat(
                                                                        v__inl323_scrut[1],
                                                                        v__inl248_line
                                                                      );
                                                                      break $join324;
                                                                    }
                                                                  }
                                                                }
                                                                switch (v__inl325_scrut[0]) {
                                                                  case 3: {
                                                                    return v__inl325_scrut;
                                                                  }
                                                                  case 4: {
                                                                    let v__inl327_scrut;
                                                                    $join326: {
                                                                      const v__inl251_e = v_idemE2;
                                                                      const __s = v_tagged(
                                                                        "idemE2",
                                                                        (s => {
                                                                          switch (s[0]) {
                                                                            case 3: {
                                                                              return "ErrA";
                                                                            }
                                                                            case 4: {
                                                                              return String(
                                                                                v__inl251_e[1]
                                                                              );
                                                                            }
                                                                          }
                                                                        })(
                                                                          v__inl251_e
                                                                        )
                                                                      );
                                                                      switch (__s[0]) {
                                                                        case 3: {
                                                                          const v__inl252__do_e_2 = __s[1];
                                                                          return [
                                                                            3,
                                                                            v__inl252__do_e_2
                                                                          ];
                                                                        }
                                                                        case 4: {
                                                                          const v__inl253_line = __s[1];
                                                                          v__inl327_scrut = __concat(
                                                                            v__inl325_scrut[1],
                                                                            v__inl253_line
                                                                          );
                                                                          break $join326;
                                                                        }
                                                                      }
                                                                    }
                                                                    switch (v__inl327_scrut[0]) {
                                                                      case 3: {
                                                                        return v__inl327_scrut;
                                                                      }
                                                                      case 4: {
                                                                        let v__inl329_scrut;
                                                                        $join328: {
                                                                          const v__inl256_e = v_idem2First;
                                                                          const __s = v_tagged(
                                                                            "idem2First",
                                                                            (s => {
                                                                              switch (s[0]) {
                                                                                case 3: {
                                                                                  {
                                                                                    const __s = v__inl256_e[1];
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
                                                                                case 4: {
                                                                                  return String(
                                                                                    v__inl256_e[1]
                                                                                  );
                                                                                }
                                                                              }
                                                                            })(
                                                                              v__inl256_e
                                                                            )
                                                                          );
                                                                          switch (__s[0]) {
                                                                            case 3: {
                                                                              const v__inl257__do_e_2 = __s[1];
                                                                              return [
                                                                                3,
                                                                                v__inl257__do_e_2
                                                                              ];
                                                                            }
                                                                            case 4: {
                                                                              const v__inl258_line = __s[1];
                                                                              v__inl329_scrut = __concat(
                                                                                v__inl327_scrut[1],
                                                                                v__inl258_line
                                                                              );
                                                                              break $join328;
                                                                            }
                                                                          }
                                                                        }
                                                                        switch (v__inl329_scrut[0]) {
                                                                          case 3: {
                                                                            return v__inl329_scrut;
                                                                          }
                                                                          case 4: {
                                                                            let v__inl331_scrut;
                                                                            $join330: {
                                                                              const v__inl261_e = v_idem2Second;
                                                                              const __s = v_tagged(
                                                                                "idem2Second",
                                                                                (s => {
                                                                                  switch (s[0]) {
                                                                                    case 3: {
                                                                                      {
                                                                                        const __s = v__inl261_e[1];
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
                                                                                    case 4: {
                                                                                      return String(
                                                                                        v__inl261_e[1]
                                                                                      );
                                                                                    }
                                                                                  }
                                                                                })(
                                                                                  v__inl261_e
                                                                                )
                                                                              );
                                                                              switch (__s[0]) {
                                                                                case 3: {
                                                                                  const v__inl262__do_e_2 = __s[1];
                                                                                  return [
                                                                                    3,
                                                                                    v__inl262__do_e_2
                                                                                  ];
                                                                                }
                                                                                case 4: {
                                                                                  const v__inl263_line = __s[1];
                                                                                  v__inl331_scrut = __concat(
                                                                                    v__inl329_scrut[1],
                                                                                    v__inl263_line
                                                                                  );
                                                                                  break $join330;
                                                                                }
                                                                              }
                                                                            }
                                                                            switch (v__inl331_scrut[0]) {
                                                                              case 3: {
                                                                                return v__inl331_scrut;
                                                                              }
                                                                              case 4: {
                                                                                let v__inl333_scrut;
                                                                                $join332: {
                                                                                  const v__inl269_e = v_wE1;
                                                                                  const __s = v_tagged(
                                                                                    "wE1",
                                                                                    (s => {
                                                                                      switch (s[0]) {
                                                                                        case 3: {
                                                                                          const v__inl264___pa0 = s[1];
                                                                                          switch (v__inl264___pa0[0]) {
                                                                                            case 925038822: {
                                                                                              {
                                                                                                const __s = v__inl264___pa0[1];
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
                                                                                            case 1615808600: {
                                                                                              return v__inl264___pa0[1];
                                                                                            }
                                                                                            case 2252990199: {
                                                                                              return "ErrA";
                                                                                            }
                                                                                          }
                                                                                        }
                                                                                        case 4: {
                                                                                          return String(
                                                                                            v__inl269_e[1]
                                                                                          );
                                                                                        }
                                                                                      }
                                                                                    })(
                                                                                      v__inl269_e
                                                                                    )
                                                                                  );
                                                                                  switch (__s[0]) {
                                                                                    case 3: {
                                                                                      const v__inl270__do_e_2 = __s[1];
                                                                                      return [
                                                                                        3,
                                                                                        v__inl270__do_e_2
                                                                                      ];
                                                                                    }
                                                                                    case 4: {
                                                                                      const v__inl271_line = __s[1];
                                                                                      v__inl333_scrut = __concat(
                                                                                        v__inl331_scrut[1],
                                                                                        v__inl271_line
                                                                                      );
                                                                                      break $join332;
                                                                                    }
                                                                                  }
                                                                                }
                                                                                switch (v__inl333_scrut[0]) {
                                                                                  case 3: {
                                                                                    return v__inl333_scrut;
                                                                                  }
                                                                                  case 4: {
                                                                                    let v__inl335_scrut;
                                                                                    $join334: {
                                                                                      const v__inl277_e = v_wE2str;
                                                                                      const __s = v_tagged(
                                                                                        "wE2str",
                                                                                        (s => {
                                                                                          switch (s[0]) {
                                                                                            case 3: {
                                                                                              const v__inl272___pa0 = s[1];
                                                                                              switch (v__inl272___pa0[0]) {
                                                                                                case 925038822: {
                                                                                                  {
                                                                                                    const __s = v__inl272___pa0[1];
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
                                                                                                case 1615808600: {
                                                                                                  return v__inl272___pa0[1];
                                                                                                }
                                                                                                case 2252990199: {
                                                                                                  return "ErrA";
                                                                                                }
                                                                                              }
                                                                                            }
                                                                                            case 4: {
                                                                                              return String(
                                                                                                v__inl277_e[1]
                                                                                              );
                                                                                            }
                                                                                          }
                                                                                        })(
                                                                                          v__inl277_e
                                                                                        )
                                                                                      );
                                                                                      switch (__s[0]) {
                                                                                        case 3: {
                                                                                          const v__inl278__do_e_2 = __s[1];
                                                                                          return [
                                                                                            3,
                                                                                            v__inl278__do_e_2
                                                                                          ];
                                                                                        }
                                                                                        case 4: {
                                                                                          const v__inl279_line = __s[1];
                                                                                          v__inl335_scrut = __concat(
                                                                                            v__inl333_scrut[1],
                                                                                            v__inl279_line
                                                                                          );
                                                                                          break $join334;
                                                                                        }
                                                                                      }
                                                                                    }
                                                                                    switch (v__inl335_scrut[0]) {
                                                                                      case 3: {
                                                                                        return v__inl335_scrut;
                                                                                      }
                                                                                      case 4: {
                                                                                        let v__inl337_scrut;
                                                                                        $join336: {
                                                                                          const v__inl285_e = v_wE3;
                                                                                          const __s = v_tagged(
                                                                                            "wE3",
                                                                                            (s => {
                                                                                              switch (s[0]) {
                                                                                                case 3: {
                                                                                                  const v__inl280___pa0 = s[1];
                                                                                                  switch (v__inl280___pa0[0]) {
                                                                                                    case 925038822: {
                                                                                                      {
                                                                                                        const __s = v__inl280___pa0[1];
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
                                                                                                    case 1615808600: {
                                                                                                      return v__inl280___pa0[1];
                                                                                                    }
                                                                                                    case 2252990199: {
                                                                                                      return "ErrA";
                                                                                                    }
                                                                                                  }
                                                                                                }
                                                                                                case 4: {
                                                                                                  return String(
                                                                                                    v__inl285_e[1]
                                                                                                  );
                                                                                                }
                                                                                              }
                                                                                            })(
                                                                                              v__inl285_e
                                                                                            )
                                                                                          );
                                                                                          switch (__s[0]) {
                                                                                            case 3: {
                                                                                              const v__inl286__do_e_2 = __s[1];
                                                                                              return [
                                                                                                3,
                                                                                                v__inl286__do_e_2
                                                                                              ];
                                                                                            }
                                                                                            case 4: {
                                                                                              const v__inl287_line = __s[1];
                                                                                              v__inl337_scrut = __concat(
                                                                                                v__inl335_scrut[1],
                                                                                                v__inl287_line
                                                                                              );
                                                                                              break $join336;
                                                                                            }
                                                                                          }
                                                                                        }
                                                                                        switch (v__inl337_scrut[0]) {
                                                                                          case 3: {
                                                                                            return v__inl337_scrut;
                                                                                          }
                                                                                          case 4: {
                                                                                            {
                                                                                              const v__inl293_e = v_wOk;
                                                                                              const __s = v_tagged(
                                                                                                "wOk",
                                                                                                (s => {
                                                                                                  switch (s[0]) {
                                                                                                    case 3: {
                                                                                                      const v__inl288___pa0 = s[1];
                                                                                                      switch (v__inl288___pa0[0]) {
                                                                                                        case 925038822: {
                                                                                                          {
                                                                                                            const __s = v__inl288___pa0[1];
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
                                                                                                        case 1615808600: {
                                                                                                          return v__inl288___pa0[1];
                                                                                                        }
                                                                                                        case 2252990199: {
                                                                                                          return "ErrA";
                                                                                                        }
                                                                                                      }
                                                                                                    }
                                                                                                    case 4: {
                                                                                                      return String(
                                                                                                        v__inl293_e[1]
                                                                                                      );
                                                                                                    }
                                                                                                  }
                                                                                                })(
                                                                                                  v__inl293_e
                                                                                                )
                                                                                              );
                                                                                              switch (__s[0]) {
                                                                                                case 3: {
                                                                                                  const v__inl294__do_e_2 = __s[1];
                                                                                                  return [
                                                                                                    3,
                                                                                                    v__inl294__do_e_2
                                                                                                  ];
                                                                                                }
                                                                                                case 4: {
                                                                                                  const v__inl295_line = __s[1];
                                                                                                  return __concat(
                                                                                                    v__inl337_scrut[1],
                                                                                                    v__inl295_line
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
      "nevOk",
      (s => {
        switch (s[0]) {
          case 3: {
            return "ErrA";
          }
          case 4: {
            return String(v__inl157_e[1]);
          }
        }
      })(v__inl157_e)
    )
  );

  const v__apply__df_handleErrorIO_14 = (v__k, v__x) => {
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

  const v__cps__df_handleErrorIO_14 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_14(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_14(
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

  const v__apply__df_andThenIO_18 = (v__k, v__x) => {
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

  const v__cps__df_andThenIO_18 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_18(v__k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v__apply__df_andThenIO_18(v__k, v_io);
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

  const v__inl340_x = v_render;
  const main = v__cps__df_handleErrorIO_14(
    v__cps__df_andThenIO_18(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v__inl340_x[1]];
          }
          case 4: {
            return [5, v__inl340_x[1]];
          }
        }
      })(v__inl340_x),
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
