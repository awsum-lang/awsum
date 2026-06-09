"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const v_seedT = [4, 4 | 0];

  const v_seedSecond = [3, [27]];

  const v_seedS = [4, 3 | 0];

  const v_seedNever = [4, 1 | 0];

  const v_seedLeftS = [3, "seedS"];

  const v_seedLeftA = [3, [24]];

  const v_seedFirst = [3, [26]];

  const v_seedA = [4, 2 | 0];

  const v_runIO = v_io => {
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
        }
      }
    }
  };

  const v_pureIO = v_x => [5, v_x];

  const v_kSecond = v__n => [3, [27]];

  const v_kSOk = v_n => [4, v_n];

  const v_kSFail = v__n => [3, "kS"];

  const v_kNever = v_n => [4, v_n];

  const v_kBFail = v__n => [3, [25]];

  const v_kAOk = v_n => [4, v_n];

  const v_kAFail = v__n => [3, [24]];

  const v_handlerTwoA = v_e => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 925038822: {
          const v_t = __s[1];
          {
            const __s = v_t;
            switch (__s[0]) {
              case 26: {
                return [7, "First", [5, [0]]];
              }
              case 27: {
                return [7, "Second", [5, [0]]];
              }
            }
          }
        }
        case 2252990199: {
          const v__a = __s[1];
          return [7, "ErrA", [5, [0]]];
        }
      }
    }
  };

  const v_handlerTwo = v_e => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 26: {
          return [7, "First", [5, [0]]];
        }
        case 27: {
          return [7, "Second", [5, [0]]];
        }
      }
    }
  };

  const v_handlerThree = v_e => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 925038822: {
          const v_t = __s[1];
          {
            const __s = v_t;
            switch (__s[0]) {
              case 26: {
                return [7, "First", [5, [0]]];
              }
              case 27: {
                return [7, "Second", [5, [0]]];
              }
            }
          }
        }
        case 1615808600: {
          const v_s = __s[1];
          return [7, v_s, [5, [0]]];
        }
        case 2252990199: {
          const v__a = __s[1];
          return [7, "ErrA", [5, [0]]];
        }
      }
    }
  };

  const v_handlerStrA = v_e => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 1615808600: {
          const v_s = __s[1];
          return [7, v_s, [5, [0]]];
        }
        case 2252990199: {
          const v__a = __s[1];
          return [7, "ErrA", [5, [0]]];
        }
      }
    }
  };

  const v_handlerStr = v_e => [7, v_e, [5, [0]]];

  const v_handlerAB = v_e => {
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

  const v_handlerA = v_e => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 24: {
          return [7, "ErrA", [5, [0]]];
        }
      }
    }
  };

  const v_failIO = v_e => [6, v_e];

  const v_eitherToIO = v_x => {
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

  const v__lift_42 = v___input => {
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

  const v__lift_41 = v___input => {
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

  const v__lift_40 = v___input => {
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

  const v__lift_39 = v___input => {
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

  const v__lift_38 = v___input => {
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

  const v__lam_15 = v__u => [7, "=", [5, [0]]];

  const v__lam_14 = (v_act, v__u) => v_act;

  const v__lam_13 = v__u => [7, "\n", [5, [0]]];

  const v__df_bindEither_9 = v_x => {
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

  const v__df_bindEither_5 = v_x => {
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

  const v__df_bindEither_2 = v_x => {
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

  const v__df_bindEither_1 = v_x => {
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

  const v__df_bindEither_0 = v_x => {
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

  const v__df__rowmono_4_bindEither_12 = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [925038822, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_42(v_kSFail(v_a));
        }
      }
    }
  };

  const v__df__rowmono_4_bindEither_11 = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [925038822, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_42(v_kSOk(v_a));
        }
      }
    }
  };

  const v__df__rowmono_3_bindEither_13 = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_e];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_41(v_kAFail(v_a));
        }
      }
    }
  };

  const v_wE3 = v__df__rowmono_3_bindEither_13(
    v__df__rowmono_4_bindEither_11(v_seedT)
  );

  const v__df__rowmono_3_bindEither_10 = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, v_e];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_41(v_kAOk(v_a));
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

  const v__df__rowmono_2_bindEither_8 = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [925038822, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_40(v_kAFail(v_a));
        }
      }
    }
  };

  const v_twoE2 = v__df__rowmono_2_bindEither_8(v_seedT);

  const v__df__rowmono_2_bindEither_7 = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [925038822, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_40(v_kAOk(v_a));
        }
      }
    }
  };

  const v_twoFirst = v__df__rowmono_2_bindEither_7(v_seedFirst);

  const v_twoOk = v__df__rowmono_2_bindEither_7(v_seedT);

  const v_twoSecond = v__df__rowmono_2_bindEither_7(v_seedSecond);

  const v__df__rowmono_1_bindEither_6 = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [2252990199, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_39(v_kBFail(v_a));
        }
      }
    }
  };

  const v_abE1 = v__df__rowmono_1_bindEither_6(v_seedLeftA);

  const v_abE2 = v__df__rowmono_1_bindEither_6(v_seedA);

  const v__df__rowmono_0_bindEither_4 = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [1615808600, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_38(v_kAFail(v_a));
        }
      }
    }
  };

  const v_strE2 = v__df__rowmono_0_bindEither_4(v_seedS);

  const v__df__rowmono_0_bindEither_3 = v_x => {
    {
      const __s = v_x;
      switch (__s[0]) {
        case 3: {
          const v_e = __s[1];
          return [3, [1615808600, v_e]];
        }
        case 4: {
          const v_a = __s[1];
          return v__lift_38(v_kAOk(v_a));
        }
      }
    }
  };

  const v_strE1 = v__df__rowmono_0_bindEither_3(v_seedLeftS);

  const v_strOk = v__df__rowmono_0_bindEither_3(v_seedS);

  const v__bi_showInt32 = v__x0 => String(v__x0);

  const v__bi_IO_Stdout_print = v__x0 => [7, v__x0, [5, [0]]];

  const v__apply__df_mapIO_22 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 32: {
            return v__x;
          }
          case 33: {
            const v__pk_33 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_33;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_mapIO_22 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_mapIO_22(v__k, [5, v__bi_showInt32(v_a)]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_mapIO_22(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 33, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_mapIO_22 = v_io => v__cps__df_mapIO_22(v_io, [32]);

  const v__apply__df_handleErrorIO_58 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 50: {
            return v__x;
          }
          case 51: {
            const v__pk_51 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_51;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_58 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_58(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_58(v__k, v_handlerThree(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 51, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_58 = v_io =>
    v__cps__df_handleErrorIO_58(v_io, [50]);

  const v__apply__df_handleErrorIO_50 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 46: {
            return v__x;
          }
          case 47: {
            const v__pk_47 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_47;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_50 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_50(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_50(v__k, v_handlerTwoA(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 47, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_50 = v_io =>
    v__cps__df_handleErrorIO_50(v_io, [46]);

  const v__apply__df_handleErrorIO_42 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 42: {
            return v__x;
          }
          case 43: {
            const v__pk_43 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_43;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_42 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_42(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_42(v__k, v_handlerAB(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 43, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_42 = v_io =>
    v__cps__df_handleErrorIO_42(v_io, [42]);

  const v__apply__df_handleErrorIO_34 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 38: {
            return v__x;
          }
          case 39: {
            const v__pk_39 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_39;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_34 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_34(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_34(v__k, v_handlerStrA(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 39, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_34 = v_io =>
    v__cps__df_handleErrorIO_34(v_io, [38]);

  const v__apply__df_handleErrorIO_30 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 36: {
            return v__x;
          }
          case 37: {
            const v__pk_37 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_37;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_30 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_30(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_30(v__k, v_handlerStr(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 37, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_30 = v_io =>
    v__cps__df_handleErrorIO_30(v_io, [36]);

  const v__apply__df_handleErrorIO_26 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 34: {
            return v__x;
          }
          case 35: {
            const v__pk_35 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_35;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_26 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_26(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_26(v__k, v_handlerTwo(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 35, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_26 = v_io =>
    v__cps__df_handleErrorIO_26(v_io, [34]);

  const v__apply__df_handleErrorIO_14 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 28: {
            return v__x;
          }
          case 29: {
            const v__pk_29 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_29;
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
            return v__apply__df_handleErrorIO_14(v__k, v_handlerA(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 29, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_14 = v_io =>
    v__cps__df_handleErrorIO_14(v_io, [28]);

  const v__apply__df_andThenIO_98 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 70: {
            return v__x;
          }
          case 71: {
            const v__pk_71 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_71;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_94 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 68: {
            return v__x;
          }
          case 69: {
            const v__pk_69 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_69;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_90 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 66: {
            return v__x;
          }
          case 67: {
            const v__pk_67 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_67;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_86 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 64: {
            return v__x;
          }
          case 65: {
            const v__pk_65 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_65;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_82 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 62: {
            return v__x;
          }
          case 63: {
            const v__pk_63 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_63;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_78 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 60: {
            return v__x;
          }
          case 61: {
            const v__pk_61 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_61;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_74 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 58: {
            return v__x;
          }
          case 59: {
            const v__pk_59 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_59;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_74 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_74(v__k, v__lam_15(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_74(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 59, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_74 = v_io => v__cps__df_andThenIO_74(v_io, [58]);

  const v__apply__df_andThenIO_70 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 56: {
            return v__x;
          }
          case 57: {
            const v__pk_57 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_57;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_70 = (v_io, v__df_andThenIO_70_cap0_0, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_70(
              v__k,
              v__lam_14(v__df_andThenIO_70_cap0_0, v_a)
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_70(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = v__df_andThenIO_70_cap0_0;
            const __t2 = (v_io[0] = 57, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__df_andThenIO_70_cap0_0 = __t1;
            v__k = __t2;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_70 = (v_io, v__df_andThenIO_70_cap0_0) =>
    v__cps__df_andThenIO_70(v_io, v__df_andThenIO_70_cap0_0, [56]);

  const v__apply__df_andThenIO_66 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 54: {
            return v__x;
          }
          case 55: {
            const v__pk_55 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_55;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_66 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_66(v__k, v__lam_13(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_66(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 55, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_66 = v_io => v__cps__df_andThenIO_66(v_io, [54]);

  const v_line = (v_label, v_act) =>
    v__df_andThenIO_66(
      v__df_andThenIO_70(v__df_andThenIO_74([7, v_label, [5, [0]]]), v_act)
    );

  const v__apply__df_andThenIO_18 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 30: {
            return v__x;
          }
          case 31: {
            const v__pk_31 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_31;
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
            const __t1 = (v_io[0] = 31, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_18 = v_io => v__cps__df_andThenIO_18(v_io, [30]);

  const v_observeA = v_e =>
    v__df_handleErrorIO_14(
      v__df_andThenIO_18(v__df_mapIO_22(v_eitherToIO(v_e)))
    );

  const v__lam_22 = v__u => v_line("idemE2", v_observeA(v_idemE2));

  const v__lam_23 = v__u => v_line("idemE1", v_observeA(v_idemE1));

  const v__lam_35 = v__u => v_line("nevRightE1", v_observeA(v_nevRightE1));

  const v__lam_36 = v__u => v_line("nevRightOk", v_observeA(v_nevRightOk));

  const v__lam_37 = v__u => v_line("nevFail", v_observeA(v_nevFail));

  const v_observeNever = v_e =>
    v__df_andThenIO_18(v__df_mapIO_22(v_eitherToIO(v_e)));

  const v__lam_34 = v__u => v_line("pureNever", v_observeNever(v_pureNever));

  const v_observeStr = v_e =>
    v__df_handleErrorIO_30(
      v__df_andThenIO_18(v__df_mapIO_22(v_eitherToIO(v_e)))
    );

  const v__lam_30 = v__u => v_line("strIdem", v_observeStr(v_strIdem));

  const v_observeTwo = v_e =>
    v__df_handleErrorIO_26(
      v__df_andThenIO_18(v__df_mapIO_22(v_eitherToIO(v_e)))
    );

  const v__lam_20 = v__u => v_line("idem2Second", v_observeTwo(v_idem2Second));

  const v__cps__df_andThenIO_94 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_94(v__k, v__lam_20(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_94(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 69, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_94 = v_io => v__cps__df_andThenIO_94(v_io, [68]);

  const v__lam_21 = v__u => v_line("idem2First", v_observeTwo(v_idem2First));

  const v__cps__df_andThenIO_98 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_98(v__k, v__lam_21(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_98(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 71, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_98 = v_io => v__cps__df_andThenIO_98(v_io, [70]);

  const v__apply__df_andThenIO_162 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 102: {
            return v__x;
          }
          case 103: {
            const v__pk_103 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_103;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_162 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_162(v__k, v__lam_37(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_162(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 103, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_162 = v_io => v__cps__df_andThenIO_162(v_io, [102]);

  const v__apply__df_andThenIO_158 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 100: {
            return v__x;
          }
          case 101: {
            const v__pk_101 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_101;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_158 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_158(v__k, v__lam_36(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_158(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 101, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_158 = v_io => v__cps__df_andThenIO_158(v_io, [100]);

  const v__apply__df_andThenIO_154 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 98: {
            return v__x;
          }
          case 99: {
            const v__pk_99 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_99;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_154 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_154(v__k, v__lam_35(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_154(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 99, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_154 = v_io => v__cps__df_andThenIO_154(v_io, [98]);

  const v__apply__df_andThenIO_150 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 96: {
            return v__x;
          }
          case 97: {
            const v__pk_97 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_97;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_150 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_150(v__k, v__lam_34(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_150(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 97, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_150 = v_io => v__cps__df_andThenIO_150(v_io, [96]);

  const v__apply__df_andThenIO_146 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 94: {
            return v__x;
          }
          case 95: {
            const v__pk_95 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_95;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_142 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 92: {
            return v__x;
          }
          case 93: {
            const v__pk_93 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_93;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_138 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 90: {
            return v__x;
          }
          case 91: {
            const v__pk_91 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_91;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_134 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 88: {
            return v__x;
          }
          case 89: {
            const v__pk_89 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_89;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_134 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_134(v__k, v__lam_30(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_134(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 89, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_134 = v_io => v__cps__df_andThenIO_134(v_io, [88]);

  const v__apply__df_andThenIO_130 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 86: {
            return v__x;
          }
          case 87: {
            const v__pk_87 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_87;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_126 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 84: {
            return v__x;
          }
          case 85: {
            const v__pk_85 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_85;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_122 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 82: {
            return v__x;
          }
          case 83: {
            const v__pk_83 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_83;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_118 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 80: {
            return v__x;
          }
          case 81: {
            const v__pk_81 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_81;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_114 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 78: {
            return v__x;
          }
          case 79: {
            const v__pk_79 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_79;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_110 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 76: {
            return v__x;
          }
          case 77: {
            const v__pk_77 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_77;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_106 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 74: {
            return v__x;
          }
          case 75: {
            const v__pk_75 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_75;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_106 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_106(v__k, v__lam_23(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_106(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 75, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_106 = v_io => v__cps__df_andThenIO_106(v_io, [74]);

  const v__apply__df_andThenIO_102 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 72: {
            return v__x;
          }
          case 73: {
            const v__pk_73 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_73;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_102 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_102(v__k, v__lam_22(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_102(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 73, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_102 = v_io => v__cps__df_andThenIO_102(v_io, [72]);

  const v__apply__df__rowmono_8_andThenIO_62 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 52: {
            return v__x;
          }
          case 53: {
            const v__pk_53 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_53;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df__rowmono_8_andThenIO_62 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df__rowmono_8_andThenIO_62(
              v__k,
              v__bi_IO_Stdout_print(v_a)
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_8_andThenIO_62(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 53, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df__rowmono_8_andThenIO_62 = v_io =>
    v__cps__df__rowmono_8_andThenIO_62(v_io, [52]);

  const v_observeThree = v_e =>
    v__df_handleErrorIO_58(
      v__df__rowmono_8_andThenIO_62(v__df_mapIO_22(v_eitherToIO(v_e)))
    );

  const v__lam_16 = v__u => v_line("wOk", v_observeThree(v_wOk));

  const v__cps__df_andThenIO_78 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_78(v__k, v__lam_16(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_78(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 61, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_78 = v_io => v__cps__df_andThenIO_78(v_io, [60]);

  const v__lam_17 = v__u => v_line("wE3", v_observeThree(v_wE3));

  const v__cps__df_andThenIO_82 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_82(v__k, v__lam_17(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_82(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 63, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_82 = v_io => v__cps__df_andThenIO_82(v_io, [62]);

  const v__lam_18 = v__u => v_line("wE2str", v_observeThree(v_wE2str));

  const v__cps__df_andThenIO_86 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_86(v__k, v__lam_18(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_86(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 65, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_86 = v_io => v__cps__df_andThenIO_86(v_io, [64]);

  const v__lam_19 = v__u => v_line("wE1", v_observeThree(v_wE1));

  const v__cps__df_andThenIO_90 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_90(v__k, v__lam_19(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_90(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 67, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_90 = v_io => v__cps__df_andThenIO_90(v_io, [66]);

  const v__apply__df__rowmono_7_andThenIO_54 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 48: {
            return v__x;
          }
          case 49: {
            const v__pk_49 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_49;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df__rowmono_7_andThenIO_54 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df__rowmono_7_andThenIO_54(
              v__k,
              v__bi_IO_Stdout_print(v_a)
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_7_andThenIO_54(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 49, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df__rowmono_7_andThenIO_54 = v_io =>
    v__cps__df__rowmono_7_andThenIO_54(v_io, [48]);

  const v_observeTwoA = v_e =>
    v__df_handleErrorIO_50(
      v__df__rowmono_7_andThenIO_54(v__df_mapIO_22(v_eitherToIO(v_e)))
    );

  const v__lam_24 = v__u => v_line("twoOk", v_observeTwoA(v_twoOk));

  const v__cps__df_andThenIO_110 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_110(v__k, v__lam_24(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_110(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 77, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_110 = v_io => v__cps__df_andThenIO_110(v_io, [76]);

  const v__lam_25 = v__u => v_line("twoE2", v_observeTwoA(v_twoE2));

  const v__cps__df_andThenIO_114 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_114(v__k, v__lam_25(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_114(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 79, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_114 = v_io => v__cps__df_andThenIO_114(v_io, [78]);

  const v__lam_26 = v__u => v_line("twoSecond", v_observeTwoA(v_twoSecond));

  const v__cps__df_andThenIO_118 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_118(v__k, v__lam_26(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_118(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 81, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_118 = v_io => v__cps__df_andThenIO_118(v_io, [80]);

  const v__lam_27 = v__u => v_line("twoFirst", v_observeTwoA(v_twoFirst));

  const v__cps__df_andThenIO_122 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_122(v__k, v__lam_27(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_122(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 83, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_122 = v_io => v__cps__df_andThenIO_122(v_io, [82]);

  const v__apply__df__rowmono_6_andThenIO_46 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 44: {
            return v__x;
          }
          case 45: {
            const v__pk_45 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_45;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df__rowmono_6_andThenIO_46 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df__rowmono_6_andThenIO_46(
              v__k,
              v__bi_IO_Stdout_print(v_a)
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_6_andThenIO_46(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 45, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df__rowmono_6_andThenIO_46 = v_io =>
    v__cps__df__rowmono_6_andThenIO_46(v_io, [44]);

  const v_observeAB = v_e =>
    v__df_handleErrorIO_42(
      v__df__rowmono_6_andThenIO_46(v__df_mapIO_22(v_eitherToIO(v_e)))
    );

  const v__lam_28 = v__u => v_line("abE2", v_observeAB(v_abE2));

  const v__cps__df_andThenIO_126 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_126(v__k, v__lam_28(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_126(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 85, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_126 = v_io => v__cps__df_andThenIO_126(v_io, [84]);

  const v__lam_29 = v__u => v_line("abE1", v_observeAB(v_abE1));

  const v__cps__df_andThenIO_130 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_130(v__k, v__lam_29(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_130(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 87, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_130 = v_io => v__cps__df_andThenIO_130(v_io, [86]);

  const v__apply__df__rowmono_5_andThenIO_38 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 40: {
            return v__x;
          }
          case 41: {
            const v__pk_41 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_41;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df__rowmono_5_andThenIO_38 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df__rowmono_5_andThenIO_38(
              v__k,
              v__bi_IO_Stdout_print(v_a)
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_5_andThenIO_38(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 41, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df__rowmono_5_andThenIO_38 = v_io =>
    v__cps__df__rowmono_5_andThenIO_38(v_io, [40]);

  const v_observeStrA = v_e =>
    v__df_handleErrorIO_34(
      v__df__rowmono_5_andThenIO_38(v__df_mapIO_22(v_eitherToIO(v_e)))
    );

  const v__lam_31 = v__u => v_line("strE2", v_observeStrA(v_strE2));

  const v__cps__df_andThenIO_138 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_138(v__k, v__lam_31(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_138(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 91, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_138 = v_io => v__cps__df_andThenIO_138(v_io, [90]);

  const v__lam_32 = v__u => v_line("strE1", v_observeStrA(v_strE1));

  const v__cps__df_andThenIO_142 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_142(v__k, v__lam_32(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_142(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 93, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_142 = v_io => v__cps__df_andThenIO_142(v_io, [92]);

  const v__lam_33 = v__u => v_line("strOk", v_observeStrA(v_strOk));

  const v__cps__df_andThenIO_146 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_146(v__k, v__lam_33(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_146(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 95, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_146 = v_io => v__cps__df_andThenIO_146(v_io, [94]);

  const main = v__df_andThenIO_78(
    v__df_andThenIO_82(
      v__df_andThenIO_86(
        v__df_andThenIO_90(
          v__df_andThenIO_94(
            v__df_andThenIO_98(
              v__df_andThenIO_102(
                v__df_andThenIO_106(
                  v__df_andThenIO_110(
                    v__df_andThenIO_114(
                      v__df_andThenIO_118(
                        v__df_andThenIO_122(
                          v__df_andThenIO_126(
                            v__df_andThenIO_130(
                              v__df_andThenIO_134(
                                v__df_andThenIO_138(
                                  v__df_andThenIO_142(
                                    v__df_andThenIO_146(
                                      v__df_andThenIO_150(
                                        v__df_andThenIO_154(
                                          v__df_andThenIO_158(
                                            v__df_andThenIO_162(
                                              v_line(
                                                "nevOk",
                                                v_observeA(v_nevOk)
                                              )
                                            )
                                          )
                                        )
                                      )
                                    )
                                  )
                                )
                              )
                            )
                          )
                        )
                      )
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
