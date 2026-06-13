"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
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

  const v_reFailC = [6, [2286545437, [26]]];

  const v_inErrB = [6, [2269767818, [25]]];

  const v_inErrA = [6, [2252990199, [24]]];

  const v__apply__df_mapIO_36 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 45: {
          return v__x;
        }
        case 46: {
          const v__pk_46 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_46;
          continue;
        }
      }
    }
  };

  const v__cps__df_mapIO_36 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_a = v_io[1];
          return v__apply__df_mapIO_36(v__k, [5, String(v_a)]);
        }
        case 6: {
          return v__apply__df_mapIO_36(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [46, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_handleErrorIO_8 = (v__k, v__x) => {
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

  const v__cps__df_handleErrorIO_8 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_8(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_8(v__k, [5, 55 | 0]);
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

  const v__apply__df_handleErrorIO_44 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 49: {
          return v__x;
        }
        case 50: {
          const v__pk_50 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_50;
          continue;
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_44 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_44(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_44(
            v__k,
            (s => {
              switch (s[0]) {
                case 2269767818: {
                  return [7, "ErrB", [5, [0]]];
                }
                case 2286545437: {
                  return [7, "ErrC", [5, [0]]];
                }
              }
            })(v_io[1])
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [50, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_handleErrorIO_40 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 47: {
          return v__x;
        }
        case 48: {
          const v__pk_48 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_48;
          continue;
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_40 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_40(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_40(v__k, [7, "ErrB", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [48, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_handleErrorIO_4 = (v__k, v__x) => {
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

  const v__cps__df_handleErrorIO_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_4(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_4(
            v__k,
            (s => {
              switch (s[0]) {
                case 2252990199: {
                  return [5, 21 | 0];
                }
                case 2269767818: {
                  return [5, 22 | 0];
                }
              }
            })(v_io[1])
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

  const v_dispatchA = v__cps__df_handleErrorIO_4(v_inErrA, [29]);

  const v_dispatchB = v__cps__df_handleErrorIO_4(v_inErrB, [29]);

  const v__apply__df_handleErrorIO_28 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 41: {
          return v__x;
        }
        case 42: {
          const v__pk_42 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_42;
          continue;
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_28 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_28(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_28(v__k, [7, "[!]", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [42, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_treeNoError = v__cps__df_handleErrorIO_28([7, "[Y]", [5, [0]]], [41]);

  const v__apply__df_handleErrorIO_20 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 37: {
          return v__x;
        }
        case 38: {
          const v__pk_38 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_38;
          continue;
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_20 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_20(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_20(v__k, [7, "[R]", [5, [0]]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [38, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_handleErrorIO_16 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 35: {
          return v__x;
        }
        case 36: {
          const v__pk_36 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_36;
          continue;
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_16 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_16(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_16(v__k, v_reFailC);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [36, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_refailRow = v__cps__df_handleErrorIO_16([6, [24]], [35]);

  const v__apply__df_handleErrorIO_12 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 33: {
          return v__x;
        }
        case 34: {
          const v__pk_34 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_34;
          continue;
        }
      }
    }
  };

  const v__cps__df_handleErrorIO_12 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_12(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_12(v__k, [6, [25]]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [34, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_nested = v__cps__df_handleErrorIO_8(
    v__cps__df_handleErrorIO_12([6, [24]], [33]),
    [31]
  );

  const v_refailNarrow = v__cps__df_handleErrorIO_12([6, [24]], [33]);

  const v__apply__df_handleErrorIO_0 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 27: {
          return v__x;
        }
        case 28: {
          const v__pk_28 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_28;
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
          return v__apply__df_handleErrorIO_0(v__k, [5, 11 | 0]);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [28, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_passthrough = v__cps__df_handleErrorIO_0([5, 33 | 0], [27]);

  const v_recover = v__cps__df_handleErrorIO_0([6, [24]], [27]);

  const v__apply__df_andThenIO_92 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 73: {
          return v__x;
        }
        case 74: {
          const v__pk_74 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_74;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_88 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 71: {
          return v__x;
        }
        case 72: {
          const v__pk_72 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_72;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_84 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 69: {
          return v__x;
        }
        case 70: {
          const v__pk_70 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_70;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_80 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 67: {
          return v__x;
        }
        case 68: {
          const v__pk_68 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_68;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_76 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 65: {
          return v__x;
        }
        case 66: {
          const v__pk_66 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_66;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_72 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 63: {
          return v__x;
        }
        case 64: {
          const v__pk_64 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_64;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_68 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 61: {
          return v__x;
        }
        case 62: {
          const v__pk_62 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_62;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_64 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 59: {
          return v__x;
        }
        case 60: {
          const v__pk_60 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_60;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_60 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 57: {
          return v__x;
        }
        case 58: {
          const v__pk_58 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_58;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_60 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_60(v__k, [7, "=", [5, [0]]]);
        }
        case 6: {
          return v__apply__df_andThenIO_60(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [58, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_56 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 55: {
          return v__x;
        }
        case 56: {
          const v__pk_56 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_56;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_56 = (v_io, v__df_andThenIO_56_cap0_0, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_56(v__k, v__df_andThenIO_56_cap0_0);
        }
        case 6: {
          return v__apply__df_andThenIO_56(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [56, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_52 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 53: {
          return v__x;
        }
        case 54: {
          const v__pk_54 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_54;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_52 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_52(v__k, [7, "\n", [5, [0]]]);
        }
        case 6: {
          return v__apply__df_andThenIO_52(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [54, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_64 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_64(
            v__k,
            v__cps__df_andThenIO_52(
              v__cps__df_andThenIO_56(
                v__cps__df_andThenIO_60([7, "treeNoError", [5, [0]]], [57]),
                v_treeNoError,
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v__apply__df_andThenIO_64(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [60, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_32 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 43: {
          return v__x;
        }
        case 44: {
          const v__pk_44 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_44;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_32 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_32(v__k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v__apply__df_andThenIO_32(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [44, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_76 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_76(
            v__k,
            v__cps__df_andThenIO_52(
              v__cps__df_andThenIO_56(
                v__cps__df_andThenIO_60([7, "refailNarrow", [5, [0]]], [57]),
                v__cps__df_handleErrorIO_40(
                  v__cps__df_andThenIO_32(
                    v__cps__df_mapIO_36(v_refailNarrow, [45]),
                    [43]
                  ),
                  [47]
                ),
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v__apply__df_andThenIO_76(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [66, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_80 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_80(
            v__k,
            v__cps__df_andThenIO_52(
              v__cps__df_andThenIO_56(
                v__cps__df_andThenIO_60([7, "nested", [5, [0]]], [57]),
                v__cps__df_andThenIO_32(
                  v__cps__df_mapIO_36(v_nested, [45]),
                  [43]
                ),
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v__apply__df_andThenIO_80(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [68, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_84 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_84(
            v__k,
            v__cps__df_andThenIO_52(
              v__cps__df_andThenIO_56(
                v__cps__df_andThenIO_60([7, "passthrough", [5, [0]]], [57]),
                v__cps__df_andThenIO_32(
                  v__cps__df_mapIO_36(v_passthrough, [45]),
                  [43]
                ),
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v__apply__df_andThenIO_84(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [70, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_88 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_88(
            v__k,
            v__cps__df_andThenIO_52(
              v__cps__df_andThenIO_56(
                v__cps__df_andThenIO_60([7, "dispatchB", [5, [0]]], [57]),
                v__cps__df_andThenIO_32(
                  v__cps__df_mapIO_36(v_dispatchB, [45]),
                  [43]
                ),
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v__apply__df_andThenIO_88(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [72, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_92 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_92(
            v__k,
            v__cps__df_andThenIO_52(
              v__cps__df_andThenIO_56(
                v__cps__df_andThenIO_60([7, "dispatchA", [5, [0]]], [57]),
                v__cps__df_andThenIO_32(
                  v__cps__df_mapIO_36(v_dispatchA, [45]),
                  [43]
                ),
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v__apply__df_andThenIO_92(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [74, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df_andThenIO_24 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 39: {
          return v__x;
        }
        case 40: {
          const v__pk_40 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_40;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_24 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_24(v__k, [6, [24]]);
        }
        case 6: {
          return v__apply__df_andThenIO_24(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [40, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_treePreserve = v__cps__df_handleErrorIO_20(
    v__cps__df_andThenIO_24([7, "[X]", [5, [0]]], [39]),
    [37]
  );

  const v__cps__df_andThenIO_68 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_68(
            v__k,
            v__cps__df_andThenIO_52(
              v__cps__df_andThenIO_56(
                v__cps__df_andThenIO_60([7, "treePreserve", [5, [0]]], [57]),
                v_treePreserve,
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v__apply__df_andThenIO_68(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [62, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__apply__df__rowmono_0_andThenIO_48 = (v__k, v__x) => {
    while (true) {
      switch (v__k[0]) {
        case 51: {
          return v__x;
        }
        case 52: {
          const v__pk_52 = v__k[1];
          v__x = (v__k[0] = 7, v__k[1] = v__k[2], v__k[2] = v__x, v__k);
          v__k = v__pk_52;
          continue;
        }
      }
    }
  };

  const v__cps__df__rowmono_0_andThenIO_48 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df__rowmono_0_andThenIO_48(
            v__k,
            [7, v_io[1], [5, [0]]]
          );
        }
        case 6: {
          return v__apply__df__rowmono_0_andThenIO_48(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [52, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v__cps__df_andThenIO_72 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_72(
            v__k,
            v__cps__df_andThenIO_52(
              v__cps__df_andThenIO_56(
                v__cps__df_andThenIO_60([7, "refailRow", [5, [0]]], [57]),
                v__cps__df_handleErrorIO_44(
                  v__cps__df__rowmono_0_andThenIO_48(
                    v__cps__df_mapIO_36(v_refailRow, [45]),
                    [51]
                  ),
                  [49]
                ),
                [55]
              ),
              [53]
            )
          );
        }
        case 6: {
          return v__apply__df_andThenIO_72(v__k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v__k = [64, v__k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const main = v__cps__df_andThenIO_64(
    v__cps__df_andThenIO_68(
      v__cps__df_andThenIO_72(
        v__cps__df_andThenIO_76(
          v__cps__df_andThenIO_80(
            v__cps__df_andThenIO_84(
              v__cps__df_andThenIO_88(
                v__cps__df_andThenIO_92(
                  v__cps__df_andThenIO_52(
                    v__cps__df_andThenIO_56(
                      v__cps__df_andThenIO_60([7, "recover", [5, [0]]], [57]),
                      v__cps__df_andThenIO_32(
                        v__cps__df_mapIO_36(v_recover, [45]),
                        [43]
                      ),
                      [55]
                    ),
                    [53]
                  ),
                  [73]
                ),
                [71]
              ),
              [69]
            ),
            [67]
          ),
          [65]
        ),
        [63]
      ),
      [61]
    ),
    [59]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
