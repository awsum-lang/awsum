"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const v_treePreserveH = v__e => [7, "[R]", [5, [0]]];

  const v_treeNoErrorH = v__e => [7, "[!]", [5, [0]]];

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

  const v_recoverH = v__e => v_pureIO(11 | 0);

  const v_nestedRecoverH = v__e => v_pureIO(55 | 0);

  const v_handlerBC = v_e => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 2269767818: {
          const v__b = __s[1];
          return [7, "ErrB", [5, [0]]];
        }
        case 2286545437: {
          const v__c = __s[1];
          return [7, "ErrC", [5, [0]]];
        }
      }
    }
  };

  const v_handlerB = v_e => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 25: {
          return [7, "ErrB", [5, [0]]];
        }
      }
    }
  };

  const v_failIO = v_e => [6, v_e];

  const v_inErrA = v_failIO([2252990199, [24]]);

  const v_inErrB = v_failIO([2269767818, [25]]);

  const v_reFailC = v_failIO([2286545437, [26]]);

  const v_refailRowH = v__e => v_reFailC;

  const v_refailNarrowH = v__e => v_failIO([25]);

  const v_dispatchH = v_e => {
    {
      const __s = v_e;
      switch (__s[0]) {
        case 2252990199: {
          const v__a = __s[1];
          return v_pureIO(21 | 0);
        }
        case 2269767818: {
          const v__b = __s[1];
          return v_pureIO(22 | 0);
        }
      }
    }
  };

  const v__lam_16 = v__u => [7, "=", [5, [0]]];

  const v__lam_15 = (v_act, v__u) => v_act;

  const v__lam_14 = v__u => [7, "\n", [5, [0]]];

  const v__lam_13 = v__u => v_failIO([24]);

  const v__bi_showInt32 = v__x0 => String(v__x0);

  const v__bi_IO_Stdout_print = v__x0 => [7, v__x0, [5, [0]]];

  const v__apply__df_mapIO_36 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 45: {
            return v__x;
          }
          case 46: {
            const v__pk_46 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_46;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_mapIO_36 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_mapIO_36(v__k, [5, v__bi_showInt32(v_a)]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_mapIO_36(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 46, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_mapIO_36 = v_io => v__cps__df_mapIO_36(v_io, [45]);

  const v__apply__df_handleErrorIO_8 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 31: {
            return v__x;
          }
          case 32: {
            const v__pk_32 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_32;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_8 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_8(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_8(v__k, v_nestedRecoverH(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 32, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_8 = v_io => v__cps__df_handleErrorIO_8(v_io, [31]);

  const v__apply__df_handleErrorIO_44 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 49: {
            return v__x;
          }
          case 50: {
            const v__pk_50 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_50;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_44 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_44(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_44(v__k, v_handlerBC(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 50, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_44 = v_io =>
    v__cps__df_handleErrorIO_44(v_io, [49]);

  const v__apply__df_handleErrorIO_40 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 47: {
            return v__x;
          }
          case 48: {
            const v__pk_48 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_48;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_40 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_40(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_40(v__k, v_handlerB(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 48, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_40 = v_io =>
    v__cps__df_handleErrorIO_40(v_io, [47]);

  const v__apply__df_handleErrorIO_4 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 29: {
            return v__x;
          }
          case 30: {
            const v__pk_30 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_30;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_4 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_4(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_4(v__k, v_dispatchH(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 30, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_4 = v_io => v__cps__df_handleErrorIO_4(v_io, [29]);

  const v_dispatchA = v__df_handleErrorIO_4(v_inErrA);

  const v_dispatchB = v__df_handleErrorIO_4(v_inErrB);

  const v__apply__df_handleErrorIO_28 = (v__k, v__x) => {
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

  const v__cps__df_handleErrorIO_28 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_28(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_28(v__k, v_treeNoErrorH(v_e));
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
        }
      }
    }
  };

  const v__df_handleErrorIO_28 = v_io =>
    v__cps__df_handleErrorIO_28(v_io, [41]);

  const v_treeNoError = v__df_handleErrorIO_28([7, "[Y]", [5, [0]]]);

  const v__apply__df_handleErrorIO_20 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 37: {
            return v__x;
          }
          case 38: {
            const v__pk_38 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_38;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_20 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_20(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_20(v__k, v_treePreserveH(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 38, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_20 = v_io =>
    v__cps__df_handleErrorIO_20(v_io, [37]);

  const v__apply__df_handleErrorIO_16 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 35: {
            return v__x;
          }
          case 36: {
            const v__pk_36 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_36;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_16 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_16(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_16(v__k, v_refailRowH(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 36, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_16 = v_io =>
    v__cps__df_handleErrorIO_16(v_io, [35]);

  const v_refailRow = v__df_handleErrorIO_16(v_failIO([24]));

  const v__apply__df_handleErrorIO_12 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 33: {
            return v__x;
          }
          case 34: {
            const v__pk_34 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_34;
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
            return v__apply__df_handleErrorIO_12(v__k, v_refailNarrowH(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 34, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_12 = v_io =>
    v__cps__df_handleErrorIO_12(v_io, [33]);

  const v_nested = v__df_handleErrorIO_8(
    v__df_handleErrorIO_12(v_failIO([24]))
  );

  const v_refailNarrow = v__df_handleErrorIO_12(v_failIO([24]));

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 27: {
            return v__x;
          }
          case 28: {
            const v__pk_28 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_28;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_0 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, [5, v_a]);
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_handleErrorIO_0(v__k, v_recoverH(v_e));
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 28, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_handleErrorIO_0 = v_io => v__cps__df_handleErrorIO_0(v_io, [27]);

  const v_passthrough = v__df_handleErrorIO_0(v_pureIO(33 | 0));

  const v_recover = v__df_handleErrorIO_0(v_failIO([24]));

  const v__apply__df_andThenIO_92 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 73: {
            return v__x;
          }
          case 74: {
            const v__pk_74 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_74;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_88 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 71: {
            return v__x;
          }
          case 72: {
            const v__pk_72 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_72;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_84 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 69: {
            return v__x;
          }
          case 70: {
            const v__pk_70 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_70;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_80 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 67: {
            return v__x;
          }
          case 68: {
            const v__pk_68 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_68;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_76 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 65: {
            return v__x;
          }
          case 66: {
            const v__pk_66 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_66;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_72 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 63: {
            return v__x;
          }
          case 64: {
            const v__pk_64 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_64;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_68 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 61: {
            return v__x;
          }
          case 62: {
            const v__pk_62 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_62;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_64 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 59: {
            return v__x;
          }
          case 60: {
            const v__pk_60 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_60;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__apply__df_andThenIO_60 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 57: {
            return v__x;
          }
          case 58: {
            const v__pk_58 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_58;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_60 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_60(v__k, v__lam_16(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_60(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 58, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_60 = v_io => v__cps__df_andThenIO_60(v_io, [57]);

  const v__apply__df_andThenIO_56 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 55: {
            return v__x;
          }
          case 56: {
            const v__pk_56 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_56;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_56 = (v_io, v__df_andThenIO_56_cap0_0, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_56(
              v__k,
              v__lam_15(v__df_andThenIO_56_cap0_0, v_a)
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_56(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = v__df_andThenIO_56_cap0_0;
            const __t2 = (v_io[0] = 56, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__df_andThenIO_56_cap0_0 = __t1;
            v__k = __t2;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_56 = (v_io, v__df_andThenIO_56_cap0_0) =>
    v__cps__df_andThenIO_56(v_io, v__df_andThenIO_56_cap0_0, [55]);

  const v__apply__df_andThenIO_52 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 53: {
            return v__x;
          }
          case 54: {
            const v__pk_54 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_54;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_52 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_52(v__k, v__lam_14(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_52(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 54, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_52 = v_io => v__cps__df_andThenIO_52(v_io, [53]);

  const v_line = (v_label, v_act) =>
    v__df_andThenIO_52(
      v__df_andThenIO_56(v__df_andThenIO_60([7, v_label, [5, [0]]]), v_act)
    );

  const v__lam_17 = v__u => v_line("treeNoError", v_treeNoError);

  const v__cps__df_andThenIO_64 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_64(v__k, v__lam_17(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_64(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 60, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_64 = v_io => v__cps__df_andThenIO_64(v_io, [59]);

  const v__apply__df_andThenIO_32 = (v__k, v__x) => {
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

  const v__cps__df_andThenIO_32 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_32(v__k, v__bi_IO_Stdout_print(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_32(v__k, [6, v_e]);
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
        }
      }
    }
  };

  const v__df_andThenIO_32 = v_io => v__cps__df_andThenIO_32(v_io, [43]);

  const v_observeB = v_io =>
    v__df_handleErrorIO_40(v__df_andThenIO_32(v__df_mapIO_36(v_io)));

  const v__lam_20 = v__u => v_line("refailNarrow", v_observeB(v_refailNarrow));

  const v__cps__df_andThenIO_76 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_76(v__k, v__lam_20(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_76(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 66, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_76 = v_io => v__cps__df_andThenIO_76(v_io, [65]);

  const v_observeNever = v_io => v__df_andThenIO_32(v__df_mapIO_36(v_io));

  const v__lam_21 = v__u => v_line("nested", v_observeNever(v_nested));

  const v__cps__df_andThenIO_80 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_80(v__k, v__lam_21(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_80(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 68, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_80 = v_io => v__cps__df_andThenIO_80(v_io, [67]);

  const v__lam_22 = v__u =>
    v_line("passthrough", v_observeNever(v_passthrough));

  const v__cps__df_andThenIO_84 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_84(v__k, v__lam_22(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_84(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 70, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_84 = v_io => v__cps__df_andThenIO_84(v_io, [69]);

  const v__lam_23 = v__u => v_line("dispatchB", v_observeNever(v_dispatchB));

  const v__cps__df_andThenIO_88 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_88(v__k, v__lam_23(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_88(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 72, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_88 = v_io => v__cps__df_andThenIO_88(v_io, [71]);

  const v__lam_24 = v__u => v_line("dispatchA", v_observeNever(v_dispatchA));

  const v__cps__df_andThenIO_92 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_92(v__k, v__lam_24(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_92(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 74, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_92 = v_io => v__cps__df_andThenIO_92(v_io, [73]);

  const v__apply__df_andThenIO_24 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 39: {
            return v__x;
          }
          case 40: {
            const v__pk_40 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_40;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df_andThenIO_24 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_24(v__k, v__lam_13(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_24(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 40, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_24 = v_io => v__cps__df_andThenIO_24(v_io, [39]);

  const v_treePreserve = v__df_handleErrorIO_20(
    v__df_andThenIO_24([7, "[X]", [5, [0]]])
  );

  const v__lam_18 = v__u => v_line("treePreserve", v_treePreserve);

  const v__cps__df_andThenIO_68 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_68(v__k, v__lam_18(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_68(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 62, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_68 = v_io => v__cps__df_andThenIO_68(v_io, [61]);

  const v__apply__df__rowmono_0_andThenIO_48 = (v__k, v__x) => {
    while (true) {
      {
        const __s = v__k;
        switch (__s[0]) {
          case 51: {
            return v__x;
          }
          case 52: {
            const v__pk_52 = __s[1];
            const v_s = __s[2];
            const __t0 = v__pk_52;
            const __t1 = (v__k[0] = 7, v__k[1] = v_s, v__k[2] = v__x, v__k);
            v__k = __t0;
            v__x = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__cps__df__rowmono_0_andThenIO_48 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df__rowmono_0_andThenIO_48(
              v__k,
              v__bi_IO_Stdout_print(v_a)
            );
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df__rowmono_0_andThenIO_48(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 52, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df__rowmono_0_andThenIO_48 = v_io =>
    v__cps__df__rowmono_0_andThenIO_48(v_io, [51]);

  const v_observeBC = v_io =>
    v__df_handleErrorIO_44(v__df__rowmono_0_andThenIO_48(v__df_mapIO_36(v_io)));

  const v__lam_19 = v__u => v_line("refailRow", v_observeBC(v_refailRow));

  const v__cps__df_andThenIO_72 = (v_io, v__k) => {
    while (true) {
      {
        const __s = v_io;
        switch (__s[0]) {
          case 5: {
            const v_a = __s[1];
            return v__apply__df_andThenIO_72(v__k, v__lam_19(v_a));
          }
          case 6: {
            const v_e = __s[1];
            return v__apply__df_andThenIO_72(v__k, [6, v_e]);
          }
          case 7: {
            const v_s = __s[1];
            const v_next = __s[2];
            const __t0 = v_next;
            const __t1 = (v_io[0] = 64, v_io[1] = v__k, v_io[2] = v_s, v_io);
            v_io = __t0;
            v__k = __t1;
            continue;
          }
        }
      }
    }
  };

  const v__df_andThenIO_72 = v_io => v__cps__df_andThenIO_72(v_io, [63]);

  const main = v__df_andThenIO_64(
    v__df_andThenIO_68(
      v__df_andThenIO_72(
        v__df_andThenIO_76(
          v__df_andThenIO_80(
            v__df_andThenIO_84(
              v__df_andThenIO_88(
                v__df_andThenIO_92(v_line("recover", v_observeNever(v_recover)))
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
