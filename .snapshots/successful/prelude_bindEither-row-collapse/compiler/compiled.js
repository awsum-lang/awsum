"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) => {
    return a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];
  };

  const __entryArgEither = (arg) => {
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

  const __stdinReadAll = () => {
    let s;
    try {
      s = new TextDecoder("utf-8", {fatal: true, ignoreBOM: true}).decode(
        require("fs").readFileSync(0)
      );
    } catch (e) {
      return [3, [3239958583, [21]]];
    }
    if (s.length > 134217728) {
      return [3, [589989748, [19]]];
    }
    return [4, s];
  };

  const __stdinReadAllBytes = () => {
    const buf = require("fs").readFileSync(0);
    let list = [13];
    for (let i = buf.length - 1; i >= 0; i--) {
      list = [14, buf[i], list];
    }
    return list;
  };

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

  const v_showTwoA = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 925038822: {
                const v_t = __s[1];
                {
                  const __s = v_t;
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
                const v__a = __s[1];
                return "ErrA";
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
  };

  const v_showTwo = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3: {
          const v___p0 = __s[1];
          {
            const __s = v___p0;
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
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
  };

  const v_showThree = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 925038822: {
                const v_t = __s[1];
                {
                  const __s = v_t;
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
                const v_s = __s[1];
                return v_s;
              }
              case 2252990199: {
                const v__a = __s[1];
                return "ErrA";
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
  };

  const v_showStrA = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 1615808600: {
                const v_s = __s[1];
                return v_s;
              }
              case 2252990199: {
                const v__a = __s[1];
                return "ErrA";
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
  };

  const v_showStr = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3: {
          const v_s = __s[1];
          return v_s;
        }
        case 4: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
  };

  const v_showNever = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 4: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
  };

  const v_showAB = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3: {
          const v___pa0 = __s[1];
          {
            const __s = v___pa0;
            switch (__s[0]) {
              case 2252990199: {
                const v__a = __s[1];
                return "ErrA";
              }
              case 2269767818: {
                const v__b = __s[1];
                return "ErrB";
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
  };

  const v_showA = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3: {
          const v___p0 = __s[1];
          {
            const __s = v___p0;
            switch (__s[0]) {
              case 24: {
                return "ErrA";
              }
            }
          }
        }
        case 4: {
          const v_n = __s[1];
          return String(v_n);
        }
      }
    }
  };

  const v_seedT = [4, 4 | 0];

  const v_seedSecond = [3, [27]];

  const v_seedS = [4, 3 | 0];

  const v_seedNever = [4, 1 | 0];

  const v_seedLeftS = [3, "seedS"];

  const v_seedLeftA = [3, [24]];

  const v_seedFirst = [3, [26]];

  const v_seedA = [4, 2 | 0];

  const v_pureIO = (v_x) => {
    return [5, v_x];
  };

  const v_printErr = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 19: {
          return [7, "STRING_TOO_LONG", [5, [0]]];
        }
      }
    }
  };

  const v_kSecond = (v__n) => {
    return [3, [27]];
  };

  const v_kSOk = (v_n) => {
    return [4, v_n];
  };

  const v_kSFail = (v__n) => {
    return [3, "kS"];
  };

  const v_kNever = (v_n) => {
    return [4, v_n];
  };

  const v_kBFail = (v__n) => {
    return [3, [25]];
  };

  const v_kAOk = (v_n) => {
    return [4, v_n];
  };

  const v_kAFail = (v__n) => {
    return [3, [24]];
  };

  const v_failIO = (v_e) => {
    return [6, v_e];
  };

  const v_eitherToIO = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return v_failIO(v_e);
        }
        case 4: {
          const v_a = __s[1];
          return v_pureIO(v_a);
        }
      }
    }
  };

  const v_appendTagged = (v_acc, v_label, v_val) => {
    {
      const __s = v_tagged(v_label, v_val);
      switch (__s[0]) {
        case 3: {
          const v__do_e_2 = __s[1];
          return [3, v__do_e_2];
        }
        case 4: {
          const v_line = __s[1];
          return __concat(v_acc, v_line);
        }
      }
    }
  };

  const v__lift_17 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [1615808600, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v__lift_16 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [2252990199, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v__lift_15 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [2252990199, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v__lift_14 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [2269767818, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v__lift_13 = (v___input) => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [2252990199, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v__df_bindEither_9 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_e];
        }
        case 4: {
          const v_a = __s[1];
          return v_kSecond(v_a);
        }
      }
    }
  };

  const v_idem2First = v__df_bindEither_9(v_seedFirst);

  const v_idem2Second = v__df_bindEither_9(v_seedT);

  const v__df_bindEither_5 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_e];
        }
        case 4: {
          const v_a = __s[1];
          return v_kSFail(v_a);
        }
      }
    }
  };

  const v_strIdem = v__df_bindEither_5(v_seedS);

  const v__df_bindEither_2 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_e];
        }
        case 4: {
          const v_a = __s[1];
          return v_kNever(v_a);
        }
      }
    }
  };

  const v_nevRightE1 = v__df_bindEither_2(v_seedLeftA);

  const v_nevRightOk = v__df_bindEither_2(v_seedA);

  const v_pureNever = v__df_bindEither_2(v_seedNever);

  const v__df_bindEither_1 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_e];
        }
        case 4: {
          const v_a = __s[1];
          return v_kAFail(v_a);
        }
      }
    }
  };

  const v_idemE1 = v__df_bindEither_1(v_seedLeftA);

  const v_idemE2 = v__df_bindEither_1(v_seedA);

  const v_nevFail = v__df_bindEither_1(v_seedNever);

  const v__df_bindEither_0 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_e];
        }
        case 4: {
          const v_a = __s[1];
          return v_kAOk(v_a);
        }
      }
    }
  };

  const v_nevOk = v__df_bindEither_0(v_seedNever);

  const v__df__rowmono_4_bindEither_12 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [925038822, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_17(v_kSFail(v_a));
        }
      }
    }
  };

  const v__df__rowmono_4_bindEither_11 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [925038822, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_17(v_kSOk(v_a));
        }
      }
    }
  };

  const v__df__rowmono_3_bindEither_13 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_e];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_16(v_kAFail(v_a));
        }
      }
    }
  };

  const v_wE3 = v__df__rowmono_3_bindEither_13(
    v__df__rowmono_4_bindEither_11(v_seedT)
  );

  const v__df__rowmono_3_bindEither_10 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_e];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_16(v_kAOk(v_a));
        }
      }
    }
  };

  const v_wE1 = v__df__rowmono_3_bindEither_10(
    v__df__rowmono_4_bindEither_11(v_seedFirst)
  );

  const v_wE2str = v__df__rowmono_3_bindEither_10(
    v__df__rowmono_4_bindEither_12(v_seedT)
  );

  const v_wOk = v__df__rowmono_3_bindEither_10(
    v__df__rowmono_4_bindEither_11(v_seedT)
  );

  const v__df__rowmono_2_bindEither_8 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [925038822, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_15(v_kAFail(v_a));
        }
      }
    }
  };

  const v_twoE2 = v__df__rowmono_2_bindEither_8(v_seedT);

  const v__df__rowmono_2_bindEither_7 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [925038822, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_15(v_kAOk(v_a));
        }
      }
    }
  };

  const v_twoFirst = v__df__rowmono_2_bindEither_7(v_seedFirst);

  const v_twoOk = v__df__rowmono_2_bindEither_7(v_seedT);

  const v_twoSecond = v__df__rowmono_2_bindEither_7(v_seedSecond);

  const v__df__rowmono_1_bindEither_6 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [2252990199, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_14(v_kBFail(v_a));
        }
      }
    }
  };

  const v_abE1 = v__df__rowmono_1_bindEither_6(v_seedLeftA);

  const v_abE2 = v__df__rowmono_1_bindEither_6(v_seedA);

  const v__df__rowmono_0_bindEither_4 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [1615808600, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_13(v_kAFail(v_a));
        }
      }
    }
  };

  const v_strE2 = v__df__rowmono_0_bindEither_4(v_seedS);

  const v__df__rowmono_0_bindEither_3 = (v_x) => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [1615808600, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_13(v_kAOk(v_a));
        }
      }
    }
  };

  const v_strE1 = v__df__rowmono_0_bindEither_3(v_seedLeftS);

  const v_strOk = v__df__rowmono_0_bindEither_3(v_seedS);

  const v_render = ((s) => {
    switch (s[0]) {
      case 3: {
        const v__do_e_24 = s[1];
        return [3, v__do_e_24];
      }
      case 4: {
        const v_r01 = s[1];
        return ((s) => {
          switch (s[0]) {
            case 3: {
              const v__do_e_23 = s[1];
              return [3, v__do_e_23];
            }
            case 4: {
              const v_r02 = s[1];
              return ((s) => {
                switch (s[0]) {
                  case 3: {
                    const v__do_e_22 = s[1];
                    return [3, v__do_e_22];
                  }
                  case 4: {
                    const v_r03 = s[1];
                    return ((s) => {
                      switch (s[0]) {
                        case 3: {
                          const v__do_e_21 = s[1];
                          return [3, v__do_e_21];
                        }
                        case 4: {
                          const v_r04 = s[1];
                          return ((s) => {
                            switch (s[0]) {
                              case 3: {
                                const v__do_e_20 = s[1];
                                return [3, v__do_e_20];
                              }
                              case 4: {
                                const v_r05 = s[1];
                                return ((s) => {
                                  switch (s[0]) {
                                    case 3: {
                                      const v__do_e_19 = s[1];
                                      return [3, v__do_e_19];
                                    }
                                    case 4: {
                                      const v_r06 = s[1];
                                      return ((s) => {
                                        switch (s[0]) {
                                          case 3: {
                                            const v__do_e_18 = s[1];
                                            return [3, v__do_e_18];
                                          }
                                          case 4: {
                                            const v_r07 = s[1];
                                            return ((s) => {
                                              switch (s[0]) {
                                                case 3: {
                                                  const v__do_e_17 = s[1];
                                                  return [3, v__do_e_17];
                                                }
                                                case 4: {
                                                  const v_r08 = s[1];
                                                  return ((s) => {
                                                    switch (s[0]) {
                                                      case 3: {
                                                        const v__do_e_16 = s[1];
                                                        return [3, v__do_e_16];
                                                      }
                                                      case 4: {
                                                        const v_r09 = s[1];
                                                        return ((s) => {
                                                          switch (s[0]) {
                                                            case 3: {
                                                              const v__do_e_15 = s[1];
                                                              return [
                                                                3,
                                                                v__do_e_15
                                                              ];
                                                            }
                                                            case 4: {
                                                              const v_r10 = s[1];
                                                              return ((s) => {
                                                                switch (s[0]) {
                                                                  case 3: {
                                                                    const v__do_e_14 = s[1];
                                                                    return [
                                                                      3,
                                                                      v__do_e_14
                                                                    ];
                                                                  }
                                                                  case 4: {
                                                                    const v_r11 = s[1];
                                                                    return ((
                                                                      s
                                                                    ) => {
                                                                      switch (s[0]) {
                                                                        case 3: {
                                                                          const v__do_e_13 = s[1];
                                                                          return [
                                                                            3,
                                                                            v__do_e_13
                                                                          ];
                                                                        }
                                                                        case 4: {
                                                                          const v_r12 = s[1];
                                                                          return ((
                                                                            s
                                                                          ) => {
                                                                            switch (s[0]) {
                                                                              case 3: {
                                                                                const v__do_e_12 = s[1];
                                                                                return [
                                                                                  3,
                                                                                  v__do_e_12
                                                                                ];
                                                                              }
                                                                              case 4: {
                                                                                const v_r13 = s[1];
                                                                                return ((
                                                                                  s
                                                                                ) => {
                                                                                  switch (s[0]) {
                                                                                    case 3: {
                                                                                      const v__do_e_11 = s[1];
                                                                                      return [
                                                                                        3,
                                                                                        v__do_e_11
                                                                                      ];
                                                                                    }
                                                                                    case 4: {
                                                                                      const v_r14 = s[1];
                                                                                      return ((
                                                                                        s
                                                                                      ) => {
                                                                                        switch (s[0]) {
                                                                                          case 3: {
                                                                                            const v__do_e_10 = s[1];
                                                                                            return [
                                                                                              3,
                                                                                              v__do_e_10
                                                                                            ];
                                                                                          }
                                                                                          case 4: {
                                                                                            const v_r15 = s[1];
                                                                                            return ((
                                                                                              s
                                                                                            ) => {
                                                                                              switch (s[0]) {
                                                                                                case 3: {
                                                                                                  const v__do_e_9 = s[1];
                                                                                                  return [
                                                                                                    3,
                                                                                                    v__do_e_9
                                                                                                  ];
                                                                                                }
                                                                                                case 4: {
                                                                                                  const v_r16 = s[1];
                                                                                                  return ((
                                                                                                    s
                                                                                                  ) => {
                                                                                                    switch (s[0]) {
                                                                                                      case 3: {
                                                                                                        const v__do_e_8 = s[1];
                                                                                                        return [
                                                                                                          3,
                                                                                                          v__do_e_8
                                                                                                        ];
                                                                                                      }
                                                                                                      case 4: {
                                                                                                        const v_r17 = s[1];
                                                                                                        return ((
                                                                                                          s
                                                                                                        ) => {
                                                                                                          switch (s[0]) {
                                                                                                            case 3: {
                                                                                                              const v__do_e_7 = s[1];
                                                                                                              return [
                                                                                                                3,
                                                                                                                v__do_e_7
                                                                                                              ];
                                                                                                            }
                                                                                                            case 4: {
                                                                                                              const v_r18 = s[1];
                                                                                                              return ((
                                                                                                                s
                                                                                                              ) => {
                                                                                                                switch (s[0]) {
                                                                                                                  case 3: {
                                                                                                                    const v__do_e_6 = s[1];
                                                                                                                    return [
                                                                                                                      3,
                                                                                                                      v__do_e_6
                                                                                                                    ];
                                                                                                                  }
                                                                                                                  case 4: {
                                                                                                                    const v_r19 = s[1];
                                                                                                                    return ((
                                                                                                                      s
                                                                                                                    ) => {
                                                                                                                      switch (s[0]) {
                                                                                                                        case 3: {
                                                                                                                          const v__do_e_5 = s[1];
                                                                                                                          return [
                                                                                                                            3,
                                                                                                                            v__do_e_5
                                                                                                                          ];
                                                                                                                        }
                                                                                                                        case 4: {
                                                                                                                          const v_r20 = s[1];
                                                                                                                          return ((
                                                                                                                            s
                                                                                                                          ) => {
                                                                                                                            switch (s[0]) {
                                                                                                                              case 3: {
                                                                                                                                const v__do_e_4 = s[1];
                                                                                                                                return [
                                                                                                                                  3,
                                                                                                                                  v__do_e_4
                                                                                                                                ];
                                                                                                                              }
                                                                                                                              case 4: {
                                                                                                                                const v_r21 = s[1];
                                                                                                                                return ((
                                                                                                                                  s
                                                                                                                                ) => {
                                                                                                                                  switch (s[0]) {
                                                                                                                                    case 3: {
                                                                                                                                      const v__do_e_3 = s[1];
                                                                                                                                      return [
                                                                                                                                        3,
                                                                                                                                        v__do_e_3
                                                                                                                                      ];
                                                                                                                                    }
                                                                                                                                    case 4: {
                                                                                                                                      const v_r22 = s[1];
                                                                                                                                      return v_appendTagged(
                                                                                                                                        v_r22,
                                                                                                                                        "wOk",
                                                                                                                                        v_showThree(
                                                                                                                                          v_wOk
                                                                                                                                        )
                                                                                                                                      );
                                                                                                                                    }
                                                                                                                                  }
                                                                                                                                })(
                                                                                                                                  v_appendTagged(
                                                                                                                                    v_r21,
                                                                                                                                    "wE3",
                                                                                                                                    v_showThree(
                                                                                                                                      v_wE3
                                                                                                                                    )
                                                                                                                                  )
                                                                                                                                );
                                                                                                                              }
                                                                                                                            }
                                                                                                                          })(
                                                                                                                            v_appendTagged(
                                                                                                                              v_r20,
                                                                                                                              "wE2str",
                                                                                                                              v_showThree(
                                                                                                                                v_wE2str
                                                                                                                              )
                                                                                                                            )
                                                                                                                          );
                                                                                                                        }
                                                                                                                      }
                                                                                                                    })(
                                                                                                                      v_appendTagged(
                                                                                                                        v_r19,
                                                                                                                        "wE1",
                                                                                                                        v_showThree(
                                                                                                                          v_wE1
                                                                                                                        )
                                                                                                                      )
                                                                                                                    );
                                                                                                                  }
                                                                                                                }
                                                                                                              })(
                                                                                                                v_appendTagged(
                                                                                                                  v_r18,
                                                                                                                  "idem2Second",
                                                                                                                  v_showTwo(
                                                                                                                    v_idem2Second
                                                                                                                  )
                                                                                                                )
                                                                                                              );
                                                                                                            }
                                                                                                          }
                                                                                                        })(
                                                                                                          v_appendTagged(
                                                                                                            v_r17,
                                                                                                            "idem2First",
                                                                                                            v_showTwo(
                                                                                                              v_idem2First
                                                                                                            )
                                                                                                          )
                                                                                                        );
                                                                                                      }
                                                                                                    }
                                                                                                  })(
                                                                                                    v_appendTagged(
                                                                                                      v_r16,
                                                                                                      "idemE2",
                                                                                                      v_showA(
                                                                                                        v_idemE2
                                                                                                      )
                                                                                                    )
                                                                                                  );
                                                                                                }
                                                                                              }
                                                                                            })(
                                                                                              v_appendTagged(
                                                                                                v_r15,
                                                                                                "idemE1",
                                                                                                v_showA(
                                                                                                  v_idemE1
                                                                                                )
                                                                                              )
                                                                                            );
                                                                                          }
                                                                                        }
                                                                                      })(
                                                                                        v_appendTagged(
                                                                                          v_r14,
                                                                                          "twoOk",
                                                                                          v_showTwoA(
                                                                                            v_twoOk
                                                                                          )
                                                                                        )
                                                                                      );
                                                                                    }
                                                                                  }
                                                                                })(
                                                                                  v_appendTagged(
                                                                                    v_r13,
                                                                                    "twoE2",
                                                                                    v_showTwoA(
                                                                                      v_twoE2
                                                                                    )
                                                                                  )
                                                                                );
                                                                              }
                                                                            }
                                                                          })(
                                                                            v_appendTagged(
                                                                              v_r12,
                                                                              "twoSecond",
                                                                              v_showTwoA(
                                                                                v_twoSecond
                                                                              )
                                                                            )
                                                                          );
                                                                        }
                                                                      }
                                                                    })(
                                                                      v_appendTagged(
                                                                        v_r11,
                                                                        "twoFirst",
                                                                        v_showTwoA(
                                                                          v_twoFirst
                                                                        )
                                                                      )
                                                                    );
                                                                  }
                                                                }
                                                              })(
                                                                v_appendTagged(
                                                                  v_r10,
                                                                  "abE2",
                                                                  v_showAB(
                                                                    v_abE2
                                                                  )
                                                                )
                                                              );
                                                            }
                                                          }
                                                        })(
                                                          v_appendTagged(
                                                            v_r09,
                                                            "abE1",
                                                            v_showAB(v_abE1)
                                                          )
                                                        );
                                                      }
                                                    }
                                                  })(
                                                    v_appendTagged(
                                                      v_r08,
                                                      "strIdem",
                                                      v_showStr(v_strIdem)
                                                    )
                                                  );
                                                }
                                              }
                                            })(
                                              v_appendTagged(
                                                v_r07,
                                                "strE2",
                                                v_showStrA(v_strE2)
                                              )
                                            );
                                          }
                                        }
                                      })(
                                        v_appendTagged(
                                          v_r06,
                                          "strE1",
                                          v_showStrA(v_strE1)
                                        )
                                      );
                                    }
                                  }
                                })(
                                  v_appendTagged(
                                    v_r05,
                                    "strOk",
                                    v_showStrA(v_strOk)
                                  )
                                );
                              }
                            }
                          })(
                            v_appendTagged(
                              v_r04,
                              "pureNever",
                              v_showNever(v_pureNever)
                            )
                          );
                        }
                      }
                    })(
                      v_appendTagged(v_r03, "nevRightE1", v_showA(v_nevRightE1))
                    );
                  }
                }
              })(v_appendTagged(v_r02, "nevRightOk", v_showA(v_nevRightOk)));
            }
          }
        })(v_appendTagged(v_r01, "nevFail", v_showA(v_nevFail)));
      }
    }
  })(v_tagged("nevOk", v_showA(v_nevOk)));

  const v__cps__scc__apply1__df__lam_0_19__df__lam_1_20__df__lam_10_16__df__lam_11_17__df__lam_2_21__df__lam_9_15 = (
    v__args,
    v__k
  ) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 34: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 28: {
                  const v__cap28_0 = __s[1];
                  const __t0 = (v__args[0] = 35, v__args[1] = v__cap28_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 29: {
                  const v__cap29_0 = __s[1];
                  const __t0 = (v__args[0] = 36, v__args[1] = v__cap29_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 30: {
                  const v__cap30_0 = __s[1];
                  const __t0 = (v__args[0] = 37, v__args[1] = v__cap30_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 31: {
                  const v__cap31_0 = __s[1];
                  const __t0 = (v__args[0] = 38, v__args[1] = v__cap31_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 32: {
                  const v__cap32_0 = __s[1];
                  const __t0 = (v__args[0] = 39, v__args[1] = v__cap32_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 33: {
                  const v__cap33_0 = __s[1];
                  const __t0 = (v__args[0] = 40, v__args[1] = v__cap33_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
              }
            }
          }
          case 35: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 34, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [46, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 36: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 34, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [47, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 37: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 34, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [48, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 38: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 34, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [49, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 39: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 34, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [50, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 40: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 34, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [51, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_0_19__df__lam_1_20__df__lam_10_16__df__lam_11_17__df__lam_2_21__df__lam_9_15 = (
    v__args
  ) => {
    return v__cps__scc__apply1__df__lam_0_19__df__lam_1_20__df__lam_10_16__df__lam_11_17__df__lam_2_21__df__lam_9_15(
      v__args,
      [45]
    );
  };

  const v__bi_IO_Stdout_print = (v__x0) => {
    return [7, v__x0, [5, [0]]];
  };

  const v__apply1 = (v__cl, v__arg0) => {
    return v__scc__apply1__df__lam_0_19__df__lam_1_20__df__lam_10_16__df__lam_11_17__df__lam_2_21__df__lam_9_15(
      [34, v__cl, v__arg0]
    );
  };

  const v_runIO = (v_io) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_u = __s[1];
            return v_u;
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            {
              const __s = __print(v_s);
              switch (__s[0]) {
                case 0: {
                  const __t0 = v_next;
                  v_io = __t0;
                  continue;
                }
              }
            }
          }
          case 8: {
            const v_cont = __s[1];
            const __t0 = v__apply1(v_cont, __getArgs());
            v_io = __t0;
            continue;
          }
          case 9: {
            const v_cont = __s[1];
            const __t0 = v__apply1(v_cont, __stdinReadAll());
            v_io = __t0;
            continue;
          }
          case 10: {
            const v_cont = __s[1];
            const __t0 = v__apply1(v_cont, __stdinReadAllBytes());
            v_io = __t0;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_handleErrorIO_14 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 41: {
            return v__x;
          }
          case 42: {
            const v__pk_42 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_42;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_14 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_14(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_14(v__k, v_printErr(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 42, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_14(v__k, [8, [33, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_14(v__k, [9, [30, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_14(v__k, [10, [31, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_14 = (v_io) => {
    return v__cps__df_handleErrorIO_14(v_io, [41]);
  };

  const v__apply__df_andThenIO_18 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 43: {
            return v__x;
          }
          case 44: {
            const v__pk_44 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_44;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_18 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_18(v__k, v__bi_IO_Stdout_print(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_18(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 44, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_18(v__k, [8, [28, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_18(v__k, [9, [29, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_18(v__k, [10, [32, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_18 = (v_io) => {
    return v__cps__df_andThenIO_18(v_io, [43]);
  };

  const main = v__df_handleErrorIO_14(
    v__df_andThenIO_18(v_eitherToIO(v_render))
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
