"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
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

  const v_toRowB = (v__s) => {
    return [2269767818, [28]];
  };

  const v_toRowA = (v__s) => {
    return [2252990199, [27]];
  };

  const v_remap = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 3640903312: {
          const v__y = __s[1];
          return [2269767818, [28]];
        }
        case 3657680931: {
          const v__x = __s[1];
          return [2252990199, [27]];
        }
      }
    }
  };

  const v_pureIO = (v_x) => {
    return [5, v_x];
  };

  const v_okSrc = v_pureIO(5 | 0);

  const v_handlerABC = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 2252990199: {
          const v__a = __s[1];
          return [7, "ErrA", [5, [0]]];
        }
        case 2269767818: {
          const v__b = __s[1];
          return [7, "ErrB", [5, [0]]];
        }
      }
    }
  };

  const v_handlerAB = (v_e) => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 2252990199: {
          const v__a = __s[1];
          return [7, "ErrA", [5, [0]]];
        }
        case 2269767818: {
          const v__b = __s[1];
          return [7, "ErrB", [5, [0]]];
        }
      }
    }
  };

  const v_failIO = (v_e) => {
    return [6, v_e];
  };

  const v_failSrc = v_failIO([24]);

  const v_failX = v_failIO([3657680931, [25]]);

  const v_failY = v_failIO([3640903312, [26]]);

  const v__lam_20 = (v__u) => {
    return [7, "=", [5, [0]]];
  };

  const v__lam_19 = (v_act, v__u) => {
    return v_act;
  };

  const v__lam_18 = (v__u) => {
    return [7, "\n", [5, [0]]];
  };

  const v__cps__scc__apply1__df__lam_10_23__df__lam_11_1__df__lam_11_5__df__lam_11_9__df__lam_12_10__df__lam_12_2__df__lam_12_6__df__lam_13_11__df__lam_13_3__df__lam_13_7__df__lam_14_13__df__lam_14_25__df__lam_15_14__df__lam_15_26__df__lam_16_15__df__lam_16_27__df__lam_29_17__df__lam_30_18__df__lam_31_19__df__lam_36_29__df__lam_37_30__df__lam_38_31__df__lam_5_33__df__lam_5_37__df__lam_5_41__df__lam_5_45__df__lam_5_49__df__lam_5_53__df__lam_5_57__df__lam_6_34__df__lam_6_38__df__lam_6_42__df__lam_6_46__df__lam_6_50__df__lam_6_54__df__lam_6_58__df__lam_7_35__df__lam_7_39__df__lam_7_43__df__lam_7_47__df__lam_7_51__df__lam_7_55__df__lam_7_59__df__lam_8_21__df__lam_9_22__lift_2__lift_26__lift_27__lift_28__lift_3__lift_33__lift_34__lift_35__lift_4 = (
    v__args,
    v__k
  ) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 83: {
            const v__cl = __s[1];
            const v__arg0 = __s[2];
            {
              const __s = v__cl;
              switch (__s[0]) {
                case 29: {
                  const v__cap29_0 = __s[1];
                  const __t0 = (v__args[0] = 84, v__args[1] = v__cap29_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 30: {
                  const v__cap30_0 = __s[1];
                  const __t0 = (v__args[0] = 85, v__args[1] = v__cap30_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 31: {
                  const v__cap31_0 = __s[1];
                  const __t0 = (v__args[0] = 86, v__args[1] = v__cap31_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 32: {
                  const v__cap32_0 = __s[1];
                  const __t0 = (v__args[0] = 87, v__args[1] = v__cap32_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 33: {
                  const v__cap33_0 = __s[1];
                  const __t0 = (v__args[0] = 88, v__args[1] = v__cap33_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 34: {
                  const v__cap34_0 = __s[1];
                  const __t0 = (v__args[0] = 89, v__args[1] = v__cap34_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 35: {
                  const v__cap35_0 = __s[1];
                  const __t0 = (v__args[0] = 90, v__args[1] = v__cap35_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 36: {
                  const v__cap36_0 = __s[1];
                  const __t0 = (v__args[0] = 91, v__args[1] = v__cap36_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 37: {
                  const v__cap37_0 = __s[1];
                  const __t0 = (v__args[0] = 92, v__args[1] = v__cap37_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 38: {
                  const v__cap38_0 = __s[1];
                  const __t0 = (v__args[0] = 93, v__args[1] = v__cap38_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 39: {
                  const v__cap39_0 = __s[1];
                  const __t0 = (v__args[0] = 94, v__args[1] = v__cap39_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 40: {
                  const v__cap40_0 = __s[1];
                  const __t0 = (v__args[0] = 95, v__args[1] = v__cap40_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 41: {
                  const v__cap41_0 = __s[1];
                  const __t0 = (v__args[0] = 96, v__args[1] = v__cap41_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 42: {
                  const v__cap42_0 = __s[1];
                  const __t0 = (v__args[0] = 97, v__args[1] = v__cap42_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 43: {
                  const v__cap43_0 = __s[1];
                  const __t0 = (v__args[0] = 98, v__args[1] = v__cap43_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 44: {
                  const v__cap44_0 = __s[1];
                  const __t0 = (v__args[0] = 99, v__args[1] = v__cap44_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 45: {
                  const v__cap45_0 = __s[1];
                  const __t0 = (v__args[0] = 100, v__args[1] = v__cap45_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 46: {
                  const v__cap46_0 = __s[1];
                  const __t0 = (v__args[0] = 101, v__args[1] = v__cap46_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 47: {
                  const v__cap47_0 = __s[1];
                  const __t0 = (v__args[0] = 102, v__args[1] = v__cap47_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 48: {
                  const v__cap48_0 = __s[1];
                  const __t0 = (v__args[0] = 103, v__args[1] = v__cap48_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 49: {
                  const v__cap49_0 = __s[1];
                  const __t0 = (v__args[0] = 104, v__args[1] = v__cap49_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 50: {
                  const v__cap50_0 = __s[1];
                  const __t0 = (v__args[0] = 105, v__args[1] = v__cap50_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 51: {
                  const v__cap51_0 = __s[1];
                  const __t0 = (v__args[0] = 106, v__args[1] = v__cap51_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 52: {
                  const v__cap52_0 = __s[1];
                  const v__cap52_1 = __s[2];
                  const __t0 = [107, v__cap52_0, v__cap52_1, v__arg0];
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 53: {
                  const v__cap53_0 = __s[1];
                  const __t0 = (v__args[0] = 108, v__args[1] = v__cap53_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 54: {
                  const v__cap54_0 = __s[1];
                  const __t0 = (v__args[0] = 109, v__args[1] = v__cap54_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 55: {
                  const v__cap55_0 = __s[1];
                  const __t0 = (v__args[0] = 110, v__args[1] = v__cap55_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 56: {
                  const v__cap56_0 = __s[1];
                  const __t0 = (v__args[0] = 111, v__args[1] = v__cap56_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 57: {
                  const v__cap57_0 = __s[1];
                  const __t0 = (v__args[0] = 112, v__args[1] = v__cap57_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 58: {
                  const v__cap58_0 = __s[1];
                  const __t0 = (v__args[0] = 113, v__args[1] = v__cap58_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 59: {
                  const v__cap59_0 = __s[1];
                  const v__cap59_1 = __s[2];
                  const __t0 = [114, v__cap59_0, v__cap59_1, v__arg0];
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 60: {
                  const v__cap60_0 = __s[1];
                  const __t0 = (v__args[0] = 115, v__args[1] = v__cap60_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 61: {
                  const v__cap61_0 = __s[1];
                  const __t0 = (v__args[0] = 116, v__args[1] = v__cap61_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 62: {
                  const v__cap62_0 = __s[1];
                  const __t0 = (v__args[0] = 117, v__args[1] = v__cap62_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 63: {
                  const v__cap63_0 = __s[1];
                  const __t0 = (v__args[0] = 118, v__args[1] = v__cap63_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 64: {
                  const v__cap64_0 = __s[1];
                  const __t0 = (v__args[0] = 119, v__args[1] = v__cap64_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 65: {
                  const v__cap65_0 = __s[1];
                  const __t0 = (v__args[0] = 120, v__args[1] = v__cap65_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 66: {
                  const v__cap66_0 = __s[1];
                  const v__cap66_1 = __s[2];
                  const __t0 = [121, v__cap66_0, v__cap66_1, v__arg0];
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 67: {
                  const v__cap67_0 = __s[1];
                  const __t0 = (v__args[0] = 122, v__args[1] = v__cap67_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 68: {
                  const v__cap68_0 = __s[1];
                  const __t0 = (v__args[0] = 123, v__args[1] = v__cap68_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 69: {
                  const v__cap69_0 = __s[1];
                  const __t0 = (v__args[0] = 124, v__args[1] = v__cap69_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 70: {
                  const v__cap70_0 = __s[1];
                  const __t0 = (v__args[0] = 125, v__args[1] = v__cap70_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 71: {
                  const v__cap71_0 = __s[1];
                  const __t0 = (v__args[0] = 126, v__args[1] = v__cap71_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 72: {
                  const v__cap72_0 = __s[1];
                  const __t0 = (v__args[0] = 127, v__args[1] = v__cap72_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 73: {
                  const v__cap73_0 = __s[1];
                  const __t0 = (v__args[0] = 128, v__args[1] = v__cap73_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 74: {
                  const v__cap74_0 = __s[1];
                  const __t0 = (v__args[0] = 129, v__args[1] = v__cap74_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 75: {
                  const v__cap75_0 = __s[1];
                  const __t0 = (v__args[0] = 130, v__args[1] = v__cap75_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 76: {
                  const v__cap76_0 = __s[1];
                  const __t0 = (v__args[0] = 131, v__args[1] = v__cap76_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 77: {
                  const v__cap77_0 = __s[1];
                  const __t0 = (v__args[0] = 132, v__args[1] = v__cap77_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 78: {
                  const v__cap78_0 = __s[1];
                  const __t0 = (v__args[0] = 133, v__args[1] = v__cap78_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 79: {
                  const v__cap79_0 = __s[1];
                  const __t0 = (v__args[0] = 134, v__args[1] = v__cap79_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 80: {
                  const v__cap80_0 = __s[1];
                  const __t0 = (v__args[0] = 135, v__args[1] = v__cap80_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 81: {
                  const v__cap81_0 = __s[1];
                  const __t0 = (v__args[0] = 136, v__args[1] = v__cap81_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
                case 82: {
                  const v__cap82_0 = __s[1];
                  const __t0 = (v__args[0] = 137, v__args[1] = v__cap82_0, v__args[2] = v__arg0, v__args);
                  const __t1 = v__k;
                  v__args = __t0;
                  v__k = __t1;
                  continue;
                }
              }
            }
          }
          case 84: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [175, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 85: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [176, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 86: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [177, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 87: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [178, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 88: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [179, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 89: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [180, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 90: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [181, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 91: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [182, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 92: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [183, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 93: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [184, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 94: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [185, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 95: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [186, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 96: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [187, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 97: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [188, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 98: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [189, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 99: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [190, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 100: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [191, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 101: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [192, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 102: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [193, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 103: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [194, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 104: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [195, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 105: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [196, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 106: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [197, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 107: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const v__df__lam_5_37_cap1_0 = __s[3];
            const __t0 = [83, v_cont, v_result];
            const __t1 = [198, v__k, v__df__lam_5_37_cap1_0];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 108: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [199, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 109: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [200, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 110: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [201, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 111: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [202, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 112: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [203, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 113: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [204, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 114: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const v__df__lam_6_38_cap1_0 = __s[3];
            const __t0 = [83, v_cont, v_result];
            const __t1 = [205, v__k, v__df__lam_6_38_cap1_0];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 115: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [206, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 116: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [207, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 117: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [208, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 118: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [209, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 119: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [210, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 120: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [211, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 121: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const v__df__lam_7_39_cap1_0 = __s[3];
            const __t0 = [83, v_cont, v_bytes];
            const __t1 = [212, v__k, v__df__lam_7_39_cap1_0];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 122: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [213, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 123: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [214, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 124: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [215, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 125: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [216, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 126: {
            const v_cont = __s[1];
            const v_bytes = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_bytes, v__args);
            const __t1 = [217, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 127: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [218, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 128: {
            const v_cont = __s[1];
            const v_result = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v_cont, v__args[2] = v_result, v__args);
            const __t1 = [219, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 129: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [220, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 130: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [221, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 131: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [222, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 132: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [223, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 133: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [224, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 134: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [225, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 135: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [226, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 136: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [227, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
          case 137: {
            const v___f = __s[1];
            const v___arg = __s[2];
            const __t0 = (v__args[0] = 83, v__args[1] = v___f, v__args[2] = v___arg, v__args);
            const __t1 = [228, v__k];
            v__args = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__scc__apply1__df__lam_10_23__df__lam_11_1__df__lam_11_5__df__lam_11_9__df__lam_12_10__df__lam_12_2__df__lam_12_6__df__lam_13_11__df__lam_13_3__df__lam_13_7__df__lam_14_13__df__lam_14_25__df__lam_15_14__df__lam_15_26__df__lam_16_15__df__lam_16_27__df__lam_29_17__df__lam_30_18__df__lam_31_19__df__lam_36_29__df__lam_37_30__df__lam_38_31__df__lam_5_33__df__lam_5_37__df__lam_5_41__df__lam_5_45__df__lam_5_49__df__lam_5_53__df__lam_5_57__df__lam_6_34__df__lam_6_38__df__lam_6_42__df__lam_6_46__df__lam_6_50__df__lam_6_54__df__lam_6_58__df__lam_7_35__df__lam_7_39__df__lam_7_43__df__lam_7_47__df__lam_7_51__df__lam_7_55__df__lam_7_59__df__lam_8_21__df__lam_9_22__lift_2__lift_26__lift_27__lift_28__lift_3__lift_33__lift_34__lift_35__lift_4 = (
    v__args
  ) => {
    return v__cps__scc__apply1__df__lam_10_23__df__lam_11_1__df__lam_11_5__df__lam_11_9__df__lam_12_10__df__lam_12_2__df__lam_12_6__df__lam_13_11__df__lam_13_3__df__lam_13_7__df__lam_14_13__df__lam_14_25__df__lam_15_14__df__lam_15_26__df__lam_16_15__df__lam_16_27__df__lam_29_17__df__lam_30_18__df__lam_31_19__df__lam_36_29__df__lam_37_30__df__lam_38_31__df__lam_5_33__df__lam_5_37__df__lam_5_41__df__lam_5_45__df__lam_5_49__df__lam_5_53__df__lam_5_57__df__lam_6_34__df__lam_6_38__df__lam_6_42__df__lam_6_46__df__lam_6_50__df__lam_6_54__df__lam_6_58__df__lam_7_35__df__lam_7_39__df__lam_7_43__df__lam_7_47__df__lam_7_51__df__lam_7_55__df__lam_7_59__df__lam_8_21__df__lam_9_22__lift_2__lift_26__lift_27__lift_28__lift_3__lift_33__lift_34__lift_35__lift_4(
      v__args,
      [174]
    );
  };

  const v__bi_showInt32 = (v__x0) => {
    return String(v__x0);
  };

  const v__bi_IO_Stdout_print = (v__x0) => {
    return [7, v__x0, [5, [0]]];
  };

  const v__apply1 = (v__cl, v__arg0) => {
    return v__scc__apply1__df__lam_10_23__df__lam_11_1__df__lam_11_5__df__lam_11_9__df__lam_12_10__df__lam_12_2__df__lam_12_6__df__lam_13_11__df__lam_13_3__df__lam_13_7__df__lam_14_13__df__lam_14_25__df__lam_15_14__df__lam_15_26__df__lam_16_15__df__lam_16_27__df__lam_29_17__df__lam_30_18__df__lam_31_19__df__lam_36_29__df__lam_37_30__df__lam_38_31__df__lam_5_33__df__lam_5_37__df__lam_5_41__df__lam_5_45__df__lam_5_49__df__lam_5_53__df__lam_5_57__df__lam_6_34__df__lam_6_38__df__lam_6_42__df__lam_6_46__df__lam_6_50__df__lam_6_54__df__lam_6_58__df__lam_7_35__df__lam_7_39__df__lam_7_43__df__lam_7_47__df__lam_7_51__df__lam_7_55__df__lam_7_59__df__lam_8_21__df__lam_9_22__lift_2__lift_26__lift_27__lift_28__lift_3__lift_33__lift_34__lift_35__lift_4(
      [83, v__cl, v__arg0]
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

  const v__apply__lift_32 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 142: {
            return v__x;
          }
          case 143: {
            const v__pk_143 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_143;
            const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__lift_32 = (v___input, v__k) => {
    while (true) {
      {
        const __s = v___input;
        switch (__s[0]) {
          case 5: {
            const v___f0 = __s[1];
            return v__apply__lift_32(v__k, [5, v___f0]);
          }
          case 6: {
            const v___f0 = __s[1];
            return v__apply__lift_32(v__k, [6, v___f0]);
          }
          case 7: {
            const v___f0 = __s[1];
            const v___f1 = __s[2];
            const __t0 = v___f1;
            const __t1 = (v___input[0] = 143, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v___f0 = __s[1];
            return v__apply__lift_32(v__k, [8, [79, v___f0]]);
          }
          case 9: {
            const v___f0 = __s[1];
            return v__apply__lift_32(v__k, [9, [80, v___f0]]);
          }
          case 10: {
            const v___f0 = __s[1];
            return v__apply__lift_32(v__k, [10, [81, v___f0]]);
          }
        }
      }
    }
  };

  const v__lift_32 = (v___input) => {
    return v__cps__lift_32(v___input, [142]);
  };

  const v__apply__lift_25 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 140: {
            return v__x;
          }
          case 141: {
            const v__pk_141 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_141;
            const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__lift_25 = (v___input, v__k) => {
    while (true) {
      {
        const __s = v___input;
        switch (__s[0]) {
          case 5: {
            const v___f0 = __s[1];
            return v__apply__lift_25(v__k, [5, v___f0]);
          }
          case 6: {
            const v___f0 = __s[1];
            return v__apply__lift_25(v__k, [6, v___f0]);
          }
          case 7: {
            const v___f0 = __s[1];
            const v___f1 = __s[2];
            const __t0 = v___f1;
            const __t1 = (v___input[0] = 141, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v___f0 = __s[1];
            return v__apply__lift_25(v__k, [8, [75, v___f0]]);
          }
          case 9: {
            const v___f0 = __s[1];
            return v__apply__lift_25(v__k, [9, [76, v___f0]]);
          }
          case 10: {
            const v___f0 = __s[1];
            return v__apply__lift_25(v__k, [10, [77, v___f0]]);
          }
        }
      }
    }
  };

  const v__lift_25 = (v___input) => {
    return v__cps__lift_25(v___input, [140]);
  };

  const v__apply__lift_1 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 138: {
            return v__x;
          }
          case 139: {
            const v__pk_139 = __s[1];
            const v___f0 = __s[2];
            const __t0 = v__pk_139;
            const __t1 = (v__k[0] = 7, v__k[1] = v___f0, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__lift_1 = (v___input, v__k) => {
    while (true) {
      {
        const __s = v___input;
        switch (__s[0]) {
          case 5: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [5, v___f0]);
          }
          case 6: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [6, v___f0]);
          }
          case 7: {
            const v___f0 = __s[1];
            const v___f1 = __s[2];
            const __t0 = v___f1;
            const __t1 = (v___input[0] = 139, v___input[1] = v__k, v___input[2] = v___f0, v___input);
            v___input = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [8, [74, v___f0]]);
          }
          case 9: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [9, [78, v___f0]]);
          }
          case 10: {
            const v___f0 = __s[1];
            return v__apply__lift_1(v__k, [10, [82, v___f0]]);
          }
        }
      }
    }
  };

  const v__lift_1 = (v___input) => {
    return v__cps__lift_1(v___input, [138]);
  };

  const v__apply__df_mapIOError_8 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 148: {
            return v__x;
          }
          case 149: {
            const v__pk_149 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_149;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_mapIOError_8 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_mapIOError_8(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_mapIOError_8(v__k, [6, v_remap(v_e)]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 149, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_mapIOError_8(v__k, [8, [32, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_mapIOError_8(v__k, [9, [33, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_mapIOError_8(v__k, [10, [36, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_mapIOError_8 = (v_io) => {
    return v__cps__df_mapIOError_8(v_io, [148]);
  };

  const v_remappedX = v__df_mapIOError_8(v_failX);

  const v_remappedY = v__df_mapIOError_8(v_failY);

  const v__apply__df_mapIOError_4 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 146: {
            return v__x;
          }
          case 147: {
            const v__pk_147 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_147;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_mapIOError_4 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_mapIOError_4(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_mapIOError_4(v__k, [6, v_toRowB(v_e)]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 147, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_mapIOError_4(v__k, [8, [31, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_mapIOError_4(v__k, [9, [35, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_mapIOError_4(v__k, [10, [38, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_mapIOError_4 = (v_io) => {
    return v__cps__df_mapIOError_4(v_io, [146]);
  };

  const v_mappedB = v__df_mapIOError_4(v_failSrc);

  const v__apply__df_mapIOError_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 144: {
            return v__x;
          }
          case 145: {
            const v__pk_145 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_145;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_mapIOError_0 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_mapIOError_0(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_mapIOError_0(v__k, [6, v_toRowA(v_e)]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 145, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_mapIOError_0(v__k, [8, [30, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_mapIOError_0(v__k, [9, [34, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_mapIOError_0(v__k, [10, [37, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_mapIOError_0 = (v_io) => {
    return v__cps__df_mapIOError_0(v_io, [144]);
  };

  const v_mappedA = v__df_mapIOError_0(v_failSrc);

  const v_mappedOk = v__df_mapIOError_0(v_okSrc);

  const v__apply__df_mapIO_20 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 154: {
            return v__x;
          }
          case 155: {
            const v__pk_155 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_155;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_mapIO_20 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_mapIO_20(v__k, [5, v__bi_showInt32(v_a)]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_mapIO_20(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 155, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_mapIO_20(v__k, [8, [72, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_mapIO_20(v__k, [9, [73, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_mapIO_20(v__k, [10, [29, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_mapIO_20 = (v_io) => {
    return v__cps__df_mapIO_20(v_io, [154]);
  };

  const v__apply__df_handleErrorIO_24 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 156: {
            return v__x;
          }
          case 157: {
            const v__pk_157 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_157;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_24 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_24(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_24(v__k, v_handlerABC(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 157, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_24(v__k, [8, [40, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_24(v__k, [9, [42, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_24(v__k, [10, [44, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_24 = (v_io) => {
    return v__cps__df_handleErrorIO_24(v_io, [156]);
  };

  const v__apply__df_handleErrorIO_12 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 150: {
            return v__x;
          }
          case 151: {
            const v__pk_151 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_151;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_12 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_12(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_12(v__k, v_handlerAB(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 151, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_12(v__k, [8, [39, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_12(v__k, [9, [41, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_handleErrorIO_12(v__k, [10, [43, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_12 = (v_io) => {
    return v__cps__df_handleErrorIO_12(v_io, [150]);
  };

  const v__apply__df_andThenIO_56 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 172: {
            return v__x;
          }
          case 173: {
            const v__pk_173 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_173;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_52 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 170: {
            return v__x;
          }
          case 171: {
            const v__pk_171 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_171;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_48 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 168: {
            return v__x;
          }
          case 169: {
            const v__pk_169 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_169;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_44 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 166: {
            return v__x;
          }
          case 167: {
            const v__pk_167 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_167;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_40 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 164: {
            return v__x;
          }
          case 165: {
            const v__pk_165 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_165;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_40 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_40(v__k, v__lift_1(v__lam_20(v_a)));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_40(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 165, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_40(v__k, [8, [53, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_40(v__k, [9, [60, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_40(v__k, [10, [67, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_40 = (v_io) => {
    return v__cps__df_andThenIO_40(v_io, [164]);
  };

  const v__apply__df_andThenIO_36 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 162: {
            return v__x;
          }
          case 163: {
            const v__pk_163 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_163;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_36 = (v_io, v__df_andThenIO_36_cap0_0, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_36(
              v__k,
              v__lift_1(v__lam_19(v__df_andThenIO_36_cap0_0, v_a))
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_36(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = v__df_andThenIO_36_cap0_0;
            const __t2 = (v_io[0] = 163, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__df_andThenIO_36_cap0_0 = __t1;
            v__k = __t2;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_36(
              v__k,
              [8, [52, v_cont, v__df_andThenIO_36_cap0_0]]
            );
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_36(
              v__k,
              [9, [59, v_cont, v__df_andThenIO_36_cap0_0]]
            );
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_36(
              v__k,
              [10, [66, v_cont, v__df_andThenIO_36_cap0_0]]
            );
          }
        }
      }
    }
  };

  const v__df_andThenIO_36 = (v_io, v__df_andThenIO_36_cap0_0) => {
    return v__cps__df_andThenIO_36(v_io, v__df_andThenIO_36_cap0_0, [162]);
  };

  const v__apply__df_andThenIO_32 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 160: {
            return v__x;
          }
          case 161: {
            const v__pk_161 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_161;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_32 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_32(v__k, v__lift_1(v__lam_18(v_a)));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_32(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 161, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_32(v__k, [8, [51, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_32(v__k, [9, [58, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_32(v__k, [10, [65, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_32 = (v_io) => {
    return v__cps__df_andThenIO_32(v_io, [160]);
  };

  const v_line = (v_label, v_act) => {
    return v__df_andThenIO_32(
      v__df_andThenIO_36(v__df_andThenIO_40([7, v_label, [5, [0]]]), v_act)
    );
  };

  const v__apply__df__rowmono_1_andThenIO_28 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 158: {
            return v__x;
          }
          case 159: {
            const v__pk_159 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_159;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df__rowmono_1_andThenIO_28 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df__rowmono_1_andThenIO_28(
              v__k,
              v__lift_32(v__bi_IO_Stdout_print(v_a))
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_1_andThenIO_28(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 159, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_1_andThenIO_28(
              v__k,
              [8, [48, v_cont]]
            );
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_1_andThenIO_28(
              v__k,
              [9, [49, v_cont]]
            );
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_1_andThenIO_28(
              v__k,
              [10, [50, v_cont]]
            );
          }
        }
      }
    }
  };

  const v__df__rowmono_1_andThenIO_28 = (v_io) => {
    return v__cps__df__rowmono_1_andThenIO_28(v_io, [158]);
  };

  const v_observeABC = (v_io) => {
    return v__df_handleErrorIO_24(
      v__df__rowmono_1_andThenIO_28(v__df_mapIO_20(v_io))
    );
  };

  const v__lam_21 = (v__u) => {
    return v_line("remappedY", v_observeABC(v_remappedY));
  };

  const v__cps__df_andThenIO_44 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_44(v__k, v__lift_1(v__lam_21(v_a)));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_44(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 167, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_44(v__k, [8, [54, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_44(v__k, [9, [61, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_44(v__k, [10, [68, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_44 = (v_io) => {
    return v__cps__df_andThenIO_44(v_io, [166]);
  };

  const v__lam_22 = (v__u) => {
    return v_line("remappedX", v_observeABC(v_remappedX));
  };

  const v__cps__df_andThenIO_48 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_48(v__k, v__lift_1(v__lam_22(v_a)));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_48(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 169, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_48(v__k, [8, [55, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_48(v__k, [9, [62, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_48(v__k, [10, [69, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_48 = (v_io) => {
    return v__cps__df_andThenIO_48(v_io, [168]);
  };

  const v__apply__df__rowmono_0_andThenIO_16 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 152: {
            return v__x;
          }
          case 153: {
            const v__pk_153 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_153;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df__rowmono_0_andThenIO_16 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df__rowmono_0_andThenIO_16(
              v__k,
              v__lift_25(v__bi_IO_Stdout_print(v_a))
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_0_andThenIO_16(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 153, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_0_andThenIO_16(
              v__k,
              [8, [45, v_cont]]
            );
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_0_andThenIO_16(
              v__k,
              [9, [46, v_cont]]
            );
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df__rowmono_0_andThenIO_16(
              v__k,
              [10, [47, v_cont]]
            );
          }
        }
      }
    }
  };

  const v__df__rowmono_0_andThenIO_16 = (v_io) => {
    return v__cps__df__rowmono_0_andThenIO_16(v_io, [152]);
  };

  const v_observeAB = (v_io) => {
    return v__df_handleErrorIO_12(
      v__df__rowmono_0_andThenIO_16(v__df_mapIO_20(v_io))
    );
  };

  const v__lam_23 = (v__u) => {
    return v_line("mappedOk", v_observeAB(v_mappedOk));
  };

  const v__cps__df_andThenIO_52 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_52(v__k, v__lift_1(v__lam_23(v_a)));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_52(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 171, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_52(v__k, [8, [56, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_52(v__k, [9, [63, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_52(v__k, [10, [70, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_52 = (v_io) => {
    return v__cps__df_andThenIO_52(v_io, [170]);
  };

  const v__lam_24 = (v__u) => {
    return v_line("mappedB", v_observeAB(v_mappedB));
  };

  const v__cps__df_andThenIO_56 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_56(v__k, v__lift_1(v__lam_24(v_a)));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_56(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 173, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
          case 8: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_56(v__k, [8, [57, v_cont]]);
          }
          case 9: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_56(v__k, [9, [64, v_cont]]);
          }
          case 10: {
            const v_cont = __s[1];
            return v__apply__df_andThenIO_56(v__k, [10, [71, v_cont]]);
          }
        }
      }
    }
  };

  const v__df_andThenIO_56 = (v_io) => {
    return v__cps__df_andThenIO_56(v_io, [172]);
  };

  const main = v__df_andThenIO_44(
    v__df_andThenIO_48(
      v__df_andThenIO_52(
        v__df_andThenIO_56(v_line("mappedA", v_observeAB(v_mappedA)))
      )
    )
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
