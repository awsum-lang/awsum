"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

  const v_$inl69$____input = [3, "kS"];
  const v_$inl77$x = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [1615808600, v_$inl69$____input[1]]];
      }
      case 4: {
        return v_$inl69$____input;
      }
    }
  })(v_$inl69$____input);
  const v_wE2str = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl77$x;
      }
      case 4: {
        const v_$inl74$____input = [4, v_$inl77$x[1]];
        switch (v_$inl74$____input[0]) {
          case 3: {
            return [3, [2252990199, v_$inl74$____input[1]]];
          }
          case 4: {
            return v_$inl74$____input;
          }
        }
      }
    }
  })(v_$inl77$x);

  const v_$inl95$____input = [3, [24]];
  const v_twoE2 = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2252990199, v_$inl95$____input[1]]];
      }
      case 4: {
        return v_$inl95$____input;
      }
    }
  })(v_$inl95$____input);

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

  const v_$inl137$____input = [3, [24]];
  const v_strE2 = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2252990199, v_$inl137$____input[1]]];
      }
      case 4: {
        return v_$inl137$____input;
      }
    }
  })(v_$inl137$____input);

  const v_seedT = [4, 4 | 0];

  const v_$inl112$x = v_seedT;
  const v_twoOk = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [925038822, v_$inl112$x[1]]];
      }
      case 4: {
        const v_$inl109$____input = [4, v_$inl112$x[1]];
        switch (v_$inl109$____input[0]) {
          case 3: {
            return [3, [2252990199, v_$inl109$____input[1]]];
          }
          case 4: {
            return v_$inl109$____input;
          }
        }
      }
    }
  })(v_$inl112$x);

  const v_$inl45$x = v_seedT;
  const v_$inl51$x = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [925038822, v_$inl45$x[1]]];
      }
      case 4: {
        const v_$inl42$____input = [4, v_$inl45$x[1]];
        switch (v_$inl42$____input[0]) {
          case 3: {
            return [3, [1615808600, v_$inl42$____input[1]]];
          }
          case 4: {
            return v_$inl42$____input;
          }
        }
      }
    }
  })(v_$inl45$x);
  const v_wE3 = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl51$x;
      }
      case 4: {
        const v_$inl48$____input = [3, [24]];
        switch (v_$inl48$____input[0]) {
          case 3: {
            return [3, [2252990199, v_$inl48$____input[1]]];
          }
          case 4: {
            return v_$inl48$____input;
          }
        }
      }
    }
  })(v_$inl51$x);

  const v_$inl83$x = v_seedT;
  const v_$inl89$x = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [925038822, v_$inl83$x[1]]];
      }
      case 4: {
        const v_$inl80$____input = [4, v_$inl83$x[1]];
        switch (v_$inl80$____input[0]) {
          case 3: {
            return [3, [1615808600, v_$inl80$____input[1]]];
          }
          case 4: {
            return v_$inl80$____input;
          }
        }
      }
    }
  })(v_$inl83$x);
  const v_wOk = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl89$x;
      }
      case 4: {
        const v_$inl86$____input = [4, v_$inl89$x[1]];
        switch (v_$inl86$____input[0]) {
          case 3: {
            return [3, [2252990199, v_$inl86$____input[1]]];
          }
          case 4: {
            return v_$inl86$____input;
          }
        }
      }
    }
  })(v_$inl89$x);

  const v_seedSecond = [3, [27]];

  const v_$inl118$x = v_seedSecond;
  const v_twoSecond = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [925038822, v_$inl118$x[1]]];
      }
      case 4: {
        const v_$inl115$____input = [4, v_$inl118$x[1]];
        switch (v_$inl115$____input[0]) {
          case 3: {
            return [3, [2252990199, v_$inl115$____input[1]]];
          }
          case 4: {
            return v_$inl115$____input;
          }
        }
      }
    }
  })(v_$inl118$x);

  const v_seedS = [4, 3 | 0];

  const v_$inl9$x = v_seedS;
  const v_strIdem = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl9$x;
      }
      case 4: {
        return [3, "kS"];
      }
    }
  })(v_$inl9$x);

  const v_$inl154$x = v_seedS;
  const v_strOk = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [1615808600, v_$inl154$x[1]]];
      }
      case 4: {
        const v_$inl151$____input = [4, v_$inl154$x[1]];
        switch (v_$inl151$____input[0]) {
          case 3: {
            return [3, [2252990199, v_$inl151$____input[1]]];
          }
          case 4: {
            return v_$inl151$____input;
          }
        }
      }
    }
  })(v_$inl154$x);

  const v_seedNever = [4, 1 | 0];

  const v_seedLeftS = [3, "seedS"];

  const v_$inl148$x = v_seedLeftS;
  const v_strE1 = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [1615808600, v_$inl148$x[1]]];
      }
      case 4: {
        const v_$inl145$____input = [4, v_$inl148$x[1]];
        switch (v_$inl145$____input[0]) {
          case 3: {
            return [3, [2252990199, v_$inl145$____input[1]]];
          }
          case 4: {
            return v_$inl145$____input;
          }
        }
      }
    }
  })(v_$inl148$x);

  const v_seedLeftA = [3, [24]];

  const v_seedFirst = [3, [26]];

  const v_$inl106$x = v_seedFirst;
  const v_twoFirst = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [925038822, v_$inl106$x[1]]];
      }
      case 4: {
        const v_$inl103$____input = [4, v_$inl106$x[1]];
        switch (v_$inl103$____input[0]) {
          case 3: {
            return [3, [2252990199, v_$inl103$____input[1]]];
          }
          case 4: {
            return v_$inl103$____input;
          }
        }
      }
    }
  })(v_$inl106$x);

  const v_$inl60$x = v_seedFirst;
  const v_$inl66$x = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [925038822, v_$inl60$x[1]]];
      }
      case 4: {
        const v_$inl57$____input = [4, v_$inl60$x[1]];
        switch (v_$inl57$____input[0]) {
          case 3: {
            return [3, [1615808600, v_$inl57$____input[1]]];
          }
          case 4: {
            return v_$inl57$____input;
          }
        }
      }
    }
  })(v_$inl60$x);
  const v_wE1 = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl66$x;
      }
      case 4: {
        const v_$inl63$____input = [4, v_$inl66$x[1]];
        switch (v_$inl63$____input[0]) {
          case 3: {
            return [3, [2252990199, v_$inl63$____input[1]]];
          }
          case 4: {
            return v_$inl63$____input;
          }
        }
      }
    }
  })(v_$inl66$x);

  const v_seedA = [4, 2 | 0];

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

  const v_$inl18$x = v_seedNever;
  const v_pureNever = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl18$x;
      }
      case 4: {
        return [4, v_$inl18$x[1]];
      }
    }
  })(v_$inl18$x);

  const v_$inl15$x = v_seedA;
  const v_nevRightOk = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl15$x;
      }
      case 4: {
        return [4, v_$inl15$x[1]];
      }
    }
  })(v_$inl15$x);

  const v_$inl12$x = v_seedLeftA;
  const v_nevRightE1 = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl12$x;
      }
      case 4: {
        return [4, v_$inl12$x[1]];
      }
    }
  })(v_$inl12$x);

  const v_$inl30$x = v_seedNever;
  const v_nevOk = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl30$x;
      }
      case 4: {
        return [4, v_$inl30$x[1]];
      }
    }
  })(v_$inl30$x);

  const v_$inl27$x = v_seedNever;
  const v_nevFail = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl27$x;
      }
      case 4: {
        return [3, [24]];
      }
    }
  })(v_$inl27$x);

  const v_$inl24$x = v_seedA;
  const v_idemE2 = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl24$x;
      }
      case 4: {
        return [3, [24]];
      }
    }
  })(v_$inl24$x);

  const v_$inl21$x = v_seedLeftA;
  const v_idemE1 = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl21$x;
      }
      case 4: {
        return [3, [24]];
      }
    }
  })(v_$inl21$x);

  const v_$inl6$x = v_seedT;
  const v_idem2Second = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl6$x;
      }
      case 4: {
        return [3, [27]];
      }
    }
  })(v_$inl6$x);

  const v_$inl3$x = v_seedFirst;
  const v_idem2First = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl3$x;
      }
      case 4: {
        return [3, [27]];
      }
    }
  })(v_$inl3$x);

  const v_$inl129$____input = [3, [25]];
  const v_abE2 = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [2269767818, v_$inl129$____input[1]]];
      }
      case 4: {
        return v_$inl129$____input;
      }
    }
  })(v_$inl129$____input);

  const v_abE1 = [3, [2252990199, [24]]];

  const v_$inl157$e = v_nevOk;
  const v_render = (s => {
    switch (s[0]) {
      case 3: {
        const v_$do__e__24 = s[1];
        return [3, v_$do__e__24];
      }
      case 4: {
        const v_r01 = s[1];
        let v_$inl297$scrut;
        $join296: {
          const v_$inl160$e = v_nevFail;
          const __s = v_tagged(
            "nevFail",
            (s => {
              switch (s[0]) {
                case 3: {
                  return "ErrA";
                }
                case 4: {
                  return String(v_$inl160$e[1]);
                }
              }
            })(v_$inl160$e)
          );
          switch (__s[0]) {
            case 3: {
              const v_$inl161$$do__e__2 = __s[1];
              return [3, v_$inl161$$do__e__2];
            }
            case 4: {
              const v_$inl162$line = __s[1];
              v_$inl297$scrut = __concat(v_r01, v_$inl162$line);
              break $join296;
            }
          }
        }
        switch (v_$inl297$scrut[0]) {
          case 3: {
            return v_$inl297$scrut;
          }
          case 4: {
            let v_$inl299$scrut;
            $join298: {
              const v_$inl165$e = v_nevRightOk;
              const __s = v_tagged(
                "nevRightOk",
                (s => {
                  switch (s[0]) {
                    case 3: {
                      return "ErrA";
                    }
                    case 4: {
                      return String(v_$inl165$e[1]);
                    }
                  }
                })(v_$inl165$e)
              );
              switch (__s[0]) {
                case 3: {
                  const v_$inl166$$do__e__2 = __s[1];
                  return [3, v_$inl166$$do__e__2];
                }
                case 4: {
                  const v_$inl167$line = __s[1];
                  v_$inl299$scrut = __concat(
                    v_$inl297$scrut[1],
                    v_$inl167$line
                  );
                  break $join298;
                }
              }
            }
            switch (v_$inl299$scrut[0]) {
              case 3: {
                return v_$inl299$scrut;
              }
              case 4: {
                let v_$inl301$scrut;
                $join300: {
                  const v_$inl170$e = v_nevRightE1;
                  const __s = v_tagged(
                    "nevRightE1",
                    (s => {
                      switch (s[0]) {
                        case 3: {
                          return "ErrA";
                        }
                        case 4: {
                          return String(v_$inl170$e[1]);
                        }
                      }
                    })(v_$inl170$e)
                  );
                  switch (__s[0]) {
                    case 3: {
                      const v_$inl171$$do__e__2 = __s[1];
                      return [3, v_$inl171$$do__e__2];
                    }
                    case 4: {
                      const v_$inl172$line = __s[1];
                      v_$inl301$scrut = __concat(
                        v_$inl299$scrut[1],
                        v_$inl172$line
                      );
                      break $join300;
                    }
                  }
                }
                switch (v_$inl301$scrut[0]) {
                  case 3: {
                    return v_$inl301$scrut;
                  }
                  case 4: {
                    let v_$inl303$scrut;
                    $join302: {
                      const v_$inl173$e = v_pureNever;
                      const __s = v_tagged("pureNever", String(v_$inl173$e[1]));
                      switch (__s[0]) {
                        case 3: {
                          const v_$inl174$$do__e__2 = __s[1];
                          return [3, v_$inl174$$do__e__2];
                        }
                        case 4: {
                          const v_$inl175$line = __s[1];
                          v_$inl303$scrut = __concat(
                            v_$inl301$scrut[1],
                            v_$inl175$line
                          );
                          break $join302;
                        }
                      }
                    }
                    switch (v_$inl303$scrut[0]) {
                      case 3: {
                        return v_$inl303$scrut;
                      }
                      case 4: {
                        let v_$inl305$scrut;
                        $join304: {
                          const v_$inl180$e = v_strOk;
                          const __s = v_tagged(
                            "strOk",
                            (s => {
                              switch (s[0]) {
                                case 3: {
                                  const v_$inl176$____pa0 = s[1];
                                  switch (v_$inl176$____pa0[0]) {
                                    case 1615808600: {
                                      return v_$inl176$____pa0[1];
                                    }
                                    case 2252990199: {
                                      return "ErrA";
                                    }
                                  }
                                }
                                case 4: {
                                  return String(v_$inl180$e[1]);
                                }
                              }
                            })(v_$inl180$e)
                          );
                          switch (__s[0]) {
                            case 3: {
                              const v_$inl181$$do__e__2 = __s[1];
                              return [3, v_$inl181$$do__e__2];
                            }
                            case 4: {
                              const v_$inl182$line = __s[1];
                              v_$inl305$scrut = __concat(
                                v_$inl303$scrut[1],
                                v_$inl182$line
                              );
                              break $join304;
                            }
                          }
                        }
                        switch (v_$inl305$scrut[0]) {
                          case 3: {
                            return v_$inl305$scrut;
                          }
                          case 4: {
                            let v_$inl307$scrut;
                            $join306: {
                              const v_$inl187$e = v_strE1;
                              const __s = v_tagged(
                                "strE1",
                                (s => {
                                  switch (s[0]) {
                                    case 3: {
                                      const v_$inl183$____pa0 = s[1];
                                      switch (v_$inl183$____pa0[0]) {
                                        case 1615808600: {
                                          return v_$inl183$____pa0[1];
                                        }
                                        case 2252990199: {
                                          return "ErrA";
                                        }
                                      }
                                    }
                                    case 4: {
                                      return String(v_$inl187$e[1]);
                                    }
                                  }
                                })(v_$inl187$e)
                              );
                              switch (__s[0]) {
                                case 3: {
                                  const v_$inl188$$do__e__2 = __s[1];
                                  return [3, v_$inl188$$do__e__2];
                                }
                                case 4: {
                                  const v_$inl189$line = __s[1];
                                  v_$inl307$scrut = __concat(
                                    v_$inl305$scrut[1],
                                    v_$inl189$line
                                  );
                                  break $join306;
                                }
                              }
                            }
                            switch (v_$inl307$scrut[0]) {
                              case 3: {
                                return v_$inl307$scrut;
                              }
                              case 4: {
                                let v_$inl309$scrut;
                                $join308: {
                                  const v_$inl194$e = v_strE2;
                                  const __s = v_tagged(
                                    "strE2",
                                    (s => {
                                      switch (s[0]) {
                                        case 3: {
                                          const v_$inl190$____pa0 = s[1];
                                          switch (v_$inl190$____pa0[0]) {
                                            case 1615808600: {
                                              return v_$inl190$____pa0[1];
                                            }
                                            case 2252990199: {
                                              return "ErrA";
                                            }
                                          }
                                        }
                                        case 4: {
                                          return String(v_$inl194$e[1]);
                                        }
                                      }
                                    })(v_$inl194$e)
                                  );
                                  switch (__s[0]) {
                                    case 3: {
                                      const v_$inl195$$do__e__2 = __s[1];
                                      return [3, v_$inl195$$do__e__2];
                                    }
                                    case 4: {
                                      const v_$inl196$line = __s[1];
                                      v_$inl309$scrut = __concat(
                                        v_$inl307$scrut[1],
                                        v_$inl196$line
                                      );
                                      break $join308;
                                    }
                                  }
                                }
                                switch (v_$inl309$scrut[0]) {
                                  case 3: {
                                    return v_$inl309$scrut;
                                  }
                                  case 4: {
                                    let v_$inl311$scrut;
                                    $join310: {
                                      const v_$inl199$e = v_strIdem;
                                      const __s = v_tagged(
                                        "strIdem",
                                        (s => {
                                          switch (s[0]) {
                                            case 3: {
                                              return v_$inl199$e[1];
                                            }
                                            case 4: {
                                              return String(v_$inl199$e[1]);
                                            }
                                          }
                                        })(v_$inl199$e)
                                      );
                                      switch (__s[0]) {
                                        case 3: {
                                          const v_$inl200$$do__e__2 = __s[1];
                                          return [3, v_$inl200$$do__e__2];
                                        }
                                        case 4: {
                                          const v_$inl201$line = __s[1];
                                          v_$inl311$scrut = __concat(
                                            v_$inl309$scrut[1],
                                            v_$inl201$line
                                          );
                                          break $join310;
                                        }
                                      }
                                    }
                                    switch (v_$inl311$scrut[0]) {
                                      case 3: {
                                        return v_$inl311$scrut;
                                      }
                                      case 4: {
                                        let v_$inl313$scrut;
                                        $join312: {
                                          const v_$inl206$e = v_abE1;
                                          const __s = v_tagged(
                                            "abE1",
                                            (s => {
                                              switch (s[0]) {
                                                case 3: {
                                                  {
                                                    const __s = v_$inl206$e[1];
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
                                                  return String(v_$inl206$e[1]);
                                                }
                                              }
                                            })(v_$inl206$e)
                                          );
                                          switch (__s[0]) {
                                            case 3: {
                                              const v_$inl207$$do__e__2 = __s[1];
                                              return [3, v_$inl207$$do__e__2];
                                            }
                                            case 4: {
                                              const v_$inl208$line = __s[1];
                                              v_$inl313$scrut = __concat(
                                                v_$inl311$scrut[1],
                                                v_$inl208$line
                                              );
                                              break $join312;
                                            }
                                          }
                                        }
                                        switch (v_$inl313$scrut[0]) {
                                          case 3: {
                                            return v_$inl313$scrut;
                                          }
                                          case 4: {
                                            let v_$inl315$scrut;
                                            $join314: {
                                              const v_$inl213$e = v_abE2;
                                              const __s = v_tagged(
                                                "abE2",
                                                (s => {
                                                  switch (s[0]) {
                                                    case 3: {
                                                      {
                                                        const __s = v_$inl213$e[1];
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
                                                        v_$inl213$e[1]
                                                      );
                                                    }
                                                  }
                                                })(v_$inl213$e)
                                              );
                                              switch (__s[0]) {
                                                case 3: {
                                                  const v_$inl214$$do__e__2 = __s[1];
                                                  return [
                                                    3,
                                                    v_$inl214$$do__e__2
                                                  ];
                                                }
                                                case 4: {
                                                  const v_$inl215$line = __s[1];
                                                  v_$inl315$scrut = __concat(
                                                    v_$inl313$scrut[1],
                                                    v_$inl215$line
                                                  );
                                                  break $join314;
                                                }
                                              }
                                            }
                                            switch (v_$inl315$scrut[0]) {
                                              case 3: {
                                                return v_$inl315$scrut;
                                              }
                                              case 4: {
                                                let v_$inl317$scrut;
                                                $join316: {
                                                  const v_$inl220$e = v_twoFirst;
                                                  const __s = v_tagged(
                                                    "twoFirst",
                                                    (s => {
                                                      switch (s[0]) {
                                                        case 3: {
                                                          const v_$inl216$____pa0 = s[1];
                                                          switch (v_$inl216$____pa0[0]) {
                                                            case 925038822: {
                                                              {
                                                                const __s = v_$inl216$____pa0[1];
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
                                                            v_$inl220$e[1]
                                                          );
                                                        }
                                                      }
                                                    })(v_$inl220$e)
                                                  );
                                                  switch (__s[0]) {
                                                    case 3: {
                                                      const v_$inl221$$do__e__2 = __s[1];
                                                      return [
                                                        3,
                                                        v_$inl221$$do__e__2
                                                      ];
                                                    }
                                                    case 4: {
                                                      const v_$inl222$line = __s[1];
                                                      v_$inl317$scrut = __concat(
                                                        v_$inl315$scrut[1],
                                                        v_$inl222$line
                                                      );
                                                      break $join316;
                                                    }
                                                  }
                                                }
                                                switch (v_$inl317$scrut[0]) {
                                                  case 3: {
                                                    return v_$inl317$scrut;
                                                  }
                                                  case 4: {
                                                    let v_$inl319$scrut;
                                                    $join318: {
                                                      const v_$inl227$e = v_twoSecond;
                                                      const __s = v_tagged(
                                                        "twoSecond",
                                                        (s => {
                                                          switch (s[0]) {
                                                            case 3: {
                                                              const v_$inl223$____pa0 = s[1];
                                                              switch (v_$inl223$____pa0[0]) {
                                                                case 925038822: {
                                                                  {
                                                                    const __s = v_$inl223$____pa0[1];
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
                                                                v_$inl227$e[1]
                                                              );
                                                            }
                                                          }
                                                        })(v_$inl227$e)
                                                      );
                                                      switch (__s[0]) {
                                                        case 3: {
                                                          const v_$inl228$$do__e__2 = __s[1];
                                                          return [
                                                            3,
                                                            v_$inl228$$do__e__2
                                                          ];
                                                        }
                                                        case 4: {
                                                          const v_$inl229$line = __s[1];
                                                          v_$inl319$scrut = __concat(
                                                            v_$inl317$scrut[1],
                                                            v_$inl229$line
                                                          );
                                                          break $join318;
                                                        }
                                                      }
                                                    }
                                                    switch (v_$inl319$scrut[0]) {
                                                      case 3: {
                                                        return v_$inl319$scrut;
                                                      }
                                                      case 4: {
                                                        let v_$inl321$scrut;
                                                        $join320: {
                                                          const v_$inl234$e = v_twoE2;
                                                          const __s = v_tagged(
                                                            "twoE2",
                                                            (s => {
                                                              switch (s[0]) {
                                                                case 3: {
                                                                  const v_$inl230$____pa0 = s[1];
                                                                  switch (v_$inl230$____pa0[0]) {
                                                                    case 925038822: {
                                                                      {
                                                                        const __s = v_$inl230$____pa0[1];
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
                                                                    v_$inl234$e[1]
                                                                  );
                                                                }
                                                              }
                                                            })(v_$inl234$e)
                                                          );
                                                          switch (__s[0]) {
                                                            case 3: {
                                                              const v_$inl235$$do__e__2 = __s[1];
                                                              return [
                                                                3,
                                                                v_$inl235$$do__e__2
                                                              ];
                                                            }
                                                            case 4: {
                                                              const v_$inl236$line = __s[1];
                                                              v_$inl321$scrut = __concat(
                                                                v_$inl319$scrut[1],
                                                                v_$inl236$line
                                                              );
                                                              break $join320;
                                                            }
                                                          }
                                                        }
                                                        switch (v_$inl321$scrut[0]) {
                                                          case 3: {
                                                            return v_$inl321$scrut;
                                                          }
                                                          case 4: {
                                                            let v_$inl323$scrut;
                                                            $join322: {
                                                              const v_$inl241$e = v_twoOk;
                                                              const __s = v_tagged(
                                                                "twoOk",
                                                                (s => {
                                                                  switch (s[0]) {
                                                                    case 3: {
                                                                      const v_$inl237$____pa0 = s[1];
                                                                      switch (v_$inl237$____pa0[0]) {
                                                                        case 925038822: {
                                                                          {
                                                                            const __s = v_$inl237$____pa0[1];
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
                                                                        v_$inl241$e[1]
                                                                      );
                                                                    }
                                                                  }
                                                                })(v_$inl241$e)
                                                              );
                                                              switch (__s[0]) {
                                                                case 3: {
                                                                  const v_$inl242$$do__e__2 = __s[1];
                                                                  return [
                                                                    3,
                                                                    v_$inl242$$do__e__2
                                                                  ];
                                                                }
                                                                case 4: {
                                                                  const v_$inl243$line = __s[1];
                                                                  v_$inl323$scrut = __concat(
                                                                    v_$inl321$scrut[1],
                                                                    v_$inl243$line
                                                                  );
                                                                  break $join322;
                                                                }
                                                              }
                                                            }
                                                            switch (v_$inl323$scrut[0]) {
                                                              case 3: {
                                                                return v_$inl323$scrut;
                                                              }
                                                              case 4: {
                                                                let v_$inl325$scrut;
                                                                $join324: {
                                                                  const v_$inl246$e = v_idemE1;
                                                                  const __s = v_tagged(
                                                                    "idemE1",
                                                                    (s => {
                                                                      switch (s[0]) {
                                                                        case 3: {
                                                                          return "ErrA";
                                                                        }
                                                                        case 4: {
                                                                          return String(
                                                                            v_$inl246$e[1]
                                                                          );
                                                                        }
                                                                      }
                                                                    })(
                                                                      v_$inl246$e
                                                                    )
                                                                  );
                                                                  switch (__s[0]) {
                                                                    case 3: {
                                                                      const v_$inl247$$do__e__2 = __s[1];
                                                                      return [
                                                                        3,
                                                                        v_$inl247$$do__e__2
                                                                      ];
                                                                    }
                                                                    case 4: {
                                                                      const v_$inl248$line = __s[1];
                                                                      v_$inl325$scrut = __concat(
                                                                        v_$inl323$scrut[1],
                                                                        v_$inl248$line
                                                                      );
                                                                      break $join324;
                                                                    }
                                                                  }
                                                                }
                                                                switch (v_$inl325$scrut[0]) {
                                                                  case 3: {
                                                                    return v_$inl325$scrut;
                                                                  }
                                                                  case 4: {
                                                                    let v_$inl327$scrut;
                                                                    $join326: {
                                                                      const v_$inl251$e = v_idemE2;
                                                                      const __s = v_tagged(
                                                                        "idemE2",
                                                                        (s => {
                                                                          switch (s[0]) {
                                                                            case 3: {
                                                                              return "ErrA";
                                                                            }
                                                                            case 4: {
                                                                              return String(
                                                                                v_$inl251$e[1]
                                                                              );
                                                                            }
                                                                          }
                                                                        })(
                                                                          v_$inl251$e
                                                                        )
                                                                      );
                                                                      switch (__s[0]) {
                                                                        case 3: {
                                                                          const v_$inl252$$do__e__2 = __s[1];
                                                                          return [
                                                                            3,
                                                                            v_$inl252$$do__e__2
                                                                          ];
                                                                        }
                                                                        case 4: {
                                                                          const v_$inl253$line = __s[1];
                                                                          v_$inl327$scrut = __concat(
                                                                            v_$inl325$scrut[1],
                                                                            v_$inl253$line
                                                                          );
                                                                          break $join326;
                                                                        }
                                                                      }
                                                                    }
                                                                    switch (v_$inl327$scrut[0]) {
                                                                      case 3: {
                                                                        return v_$inl327$scrut;
                                                                      }
                                                                      case 4: {
                                                                        let v_$inl329$scrut;
                                                                        $join328: {
                                                                          const v_$inl256$e = v_idem2First;
                                                                          const __s = v_tagged(
                                                                            "idem2First",
                                                                            (s => {
                                                                              switch (s[0]) {
                                                                                case 3: {
                                                                                  {
                                                                                    const __s = v_$inl256$e[1];
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
                                                                                    v_$inl256$e[1]
                                                                                  );
                                                                                }
                                                                              }
                                                                            })(
                                                                              v_$inl256$e
                                                                            )
                                                                          );
                                                                          switch (__s[0]) {
                                                                            case 3: {
                                                                              const v_$inl257$$do__e__2 = __s[1];
                                                                              return [
                                                                                3,
                                                                                v_$inl257$$do__e__2
                                                                              ];
                                                                            }
                                                                            case 4: {
                                                                              const v_$inl258$line = __s[1];
                                                                              v_$inl329$scrut = __concat(
                                                                                v_$inl327$scrut[1],
                                                                                v_$inl258$line
                                                                              );
                                                                              break $join328;
                                                                            }
                                                                          }
                                                                        }
                                                                        switch (v_$inl329$scrut[0]) {
                                                                          case 3: {
                                                                            return v_$inl329$scrut;
                                                                          }
                                                                          case 4: {
                                                                            let v_$inl331$scrut;
                                                                            $join330: {
                                                                              const v_$inl261$e = v_idem2Second;
                                                                              const __s = v_tagged(
                                                                                "idem2Second",
                                                                                (s => {
                                                                                  switch (s[0]) {
                                                                                    case 3: {
                                                                                      {
                                                                                        const __s = v_$inl261$e[1];
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
                                                                                        v_$inl261$e[1]
                                                                                      );
                                                                                    }
                                                                                  }
                                                                                })(
                                                                                  v_$inl261$e
                                                                                )
                                                                              );
                                                                              switch (__s[0]) {
                                                                                case 3: {
                                                                                  const v_$inl262$$do__e__2 = __s[1];
                                                                                  return [
                                                                                    3,
                                                                                    v_$inl262$$do__e__2
                                                                                  ];
                                                                                }
                                                                                case 4: {
                                                                                  const v_$inl263$line = __s[1];
                                                                                  v_$inl331$scrut = __concat(
                                                                                    v_$inl329$scrut[1],
                                                                                    v_$inl263$line
                                                                                  );
                                                                                  break $join330;
                                                                                }
                                                                              }
                                                                            }
                                                                            switch (v_$inl331$scrut[0]) {
                                                                              case 3: {
                                                                                return v_$inl331$scrut;
                                                                              }
                                                                              case 4: {
                                                                                let v_$inl333$scrut;
                                                                                $join332: {
                                                                                  const v_$inl269$e = v_wE1;
                                                                                  const __s = v_tagged(
                                                                                    "wE1",
                                                                                    (s => {
                                                                                      switch (s[0]) {
                                                                                        case 3: {
                                                                                          const v_$inl264$____pa0 = s[1];
                                                                                          switch (v_$inl264$____pa0[0]) {
                                                                                            case 925038822: {
                                                                                              {
                                                                                                const __s = v_$inl264$____pa0[1];
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
                                                                                              return v_$inl264$____pa0[1];
                                                                                            }
                                                                                            case 2252990199: {
                                                                                              return "ErrA";
                                                                                            }
                                                                                          }
                                                                                        }
                                                                                        case 4: {
                                                                                          return String(
                                                                                            v_$inl269$e[1]
                                                                                          );
                                                                                        }
                                                                                      }
                                                                                    })(
                                                                                      v_$inl269$e
                                                                                    )
                                                                                  );
                                                                                  switch (__s[0]) {
                                                                                    case 3: {
                                                                                      const v_$inl270$$do__e__2 = __s[1];
                                                                                      return [
                                                                                        3,
                                                                                        v_$inl270$$do__e__2
                                                                                      ];
                                                                                    }
                                                                                    case 4: {
                                                                                      const v_$inl271$line = __s[1];
                                                                                      v_$inl333$scrut = __concat(
                                                                                        v_$inl331$scrut[1],
                                                                                        v_$inl271$line
                                                                                      );
                                                                                      break $join332;
                                                                                    }
                                                                                  }
                                                                                }
                                                                                switch (v_$inl333$scrut[0]) {
                                                                                  case 3: {
                                                                                    return v_$inl333$scrut;
                                                                                  }
                                                                                  case 4: {
                                                                                    let v_$inl335$scrut;
                                                                                    $join334: {
                                                                                      const v_$inl277$e = v_wE2str;
                                                                                      const __s = v_tagged(
                                                                                        "wE2str",
                                                                                        (s => {
                                                                                          switch (s[0]) {
                                                                                            case 3: {
                                                                                              const v_$inl272$____pa0 = s[1];
                                                                                              switch (v_$inl272$____pa0[0]) {
                                                                                                case 925038822: {
                                                                                                  {
                                                                                                    const __s = v_$inl272$____pa0[1];
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
                                                                                                  return v_$inl272$____pa0[1];
                                                                                                }
                                                                                                case 2252990199: {
                                                                                                  return "ErrA";
                                                                                                }
                                                                                              }
                                                                                            }
                                                                                            case 4: {
                                                                                              return String(
                                                                                                v_$inl277$e[1]
                                                                                              );
                                                                                            }
                                                                                          }
                                                                                        })(
                                                                                          v_$inl277$e
                                                                                        )
                                                                                      );
                                                                                      switch (__s[0]) {
                                                                                        case 3: {
                                                                                          const v_$inl278$$do__e__2 = __s[1];
                                                                                          return [
                                                                                            3,
                                                                                            v_$inl278$$do__e__2
                                                                                          ];
                                                                                        }
                                                                                        case 4: {
                                                                                          const v_$inl279$line = __s[1];
                                                                                          v_$inl335$scrut = __concat(
                                                                                            v_$inl333$scrut[1],
                                                                                            v_$inl279$line
                                                                                          );
                                                                                          break $join334;
                                                                                        }
                                                                                      }
                                                                                    }
                                                                                    switch (v_$inl335$scrut[0]) {
                                                                                      case 3: {
                                                                                        return v_$inl335$scrut;
                                                                                      }
                                                                                      case 4: {
                                                                                        let v_$inl337$scrut;
                                                                                        $join336: {
                                                                                          const v_$inl285$e = v_wE3;
                                                                                          const __s = v_tagged(
                                                                                            "wE3",
                                                                                            (s => {
                                                                                              switch (s[0]) {
                                                                                                case 3: {
                                                                                                  const v_$inl280$____pa0 = s[1];
                                                                                                  switch (v_$inl280$____pa0[0]) {
                                                                                                    case 925038822: {
                                                                                                      {
                                                                                                        const __s = v_$inl280$____pa0[1];
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
                                                                                                      return v_$inl280$____pa0[1];
                                                                                                    }
                                                                                                    case 2252990199: {
                                                                                                      return "ErrA";
                                                                                                    }
                                                                                                  }
                                                                                                }
                                                                                                case 4: {
                                                                                                  return String(
                                                                                                    v_$inl285$e[1]
                                                                                                  );
                                                                                                }
                                                                                              }
                                                                                            })(
                                                                                              v_$inl285$e
                                                                                            )
                                                                                          );
                                                                                          switch (__s[0]) {
                                                                                            case 3: {
                                                                                              const v_$inl286$$do__e__2 = __s[1];
                                                                                              return [
                                                                                                3,
                                                                                                v_$inl286$$do__e__2
                                                                                              ];
                                                                                            }
                                                                                            case 4: {
                                                                                              const v_$inl287$line = __s[1];
                                                                                              v_$inl337$scrut = __concat(
                                                                                                v_$inl335$scrut[1],
                                                                                                v_$inl287$line
                                                                                              );
                                                                                              break $join336;
                                                                                            }
                                                                                          }
                                                                                        }
                                                                                        switch (v_$inl337$scrut[0]) {
                                                                                          case 3: {
                                                                                            return v_$inl337$scrut;
                                                                                          }
                                                                                          case 4: {
                                                                                            {
                                                                                              const v_$inl293$e = v_wOk;
                                                                                              const __s = v_tagged(
                                                                                                "wOk",
                                                                                                (s => {
                                                                                                  switch (s[0]) {
                                                                                                    case 3: {
                                                                                                      const v_$inl288$____pa0 = s[1];
                                                                                                      switch (v_$inl288$____pa0[0]) {
                                                                                                        case 925038822: {
                                                                                                          {
                                                                                                            const __s = v_$inl288$____pa0[1];
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
                                                                                                          return v_$inl288$____pa0[1];
                                                                                                        }
                                                                                                        case 2252990199: {
                                                                                                          return "ErrA";
                                                                                                        }
                                                                                                      }
                                                                                                    }
                                                                                                    case 4: {
                                                                                                      return String(
                                                                                                        v_$inl293$e[1]
                                                                                                      );
                                                                                                    }
                                                                                                  }
                                                                                                })(
                                                                                                  v_$inl293$e
                                                                                                )
                                                                                              );
                                                                                              switch (__s[0]) {
                                                                                                case 3: {
                                                                                                  const v_$inl294$$do__e__2 = __s[1];
                                                                                                  return [
                                                                                                    3,
                                                                                                    v_$inl294$$do__e__2
                                                                                                  ];
                                                                                                }
                                                                                                case 4: {
                                                                                                  const v_$inl295$line = __s[1];
                                                                                                  return __concat(
                                                                                                    v_$inl337$scrut[1],
                                                                                                    v_$inl295$line
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
            return String(v_$inl157$e[1]);
          }
        }
      })(v_$inl157$e)
    )
  );

  const v_$apply$$df$handleErrorIO$14 = (v_$k, v_$x) => {
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

  const v_$cps$$df$handleErrorIO$14 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$14(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$14(
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

  const v_$apply$$df$andThenIO$18 = (v_$k, v_$x) => {
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

  const v_$cps$$df$andThenIO$18 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$18(v_$k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$18(v_$k, v_io);
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

  const v_$inl340$x = v_render;
  const main = v_$cps$$df$handleErrorIO$14(
    v_$cps$$df$andThenIO$18(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl340$x[1]];
          }
          case 4: {
            return [5, v_$inl340$x[1]];
          }
        }
      })(v_$inl340$x),
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
