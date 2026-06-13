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

  const v_okSrc = [5, 5 | 0];

  const v_failY = [6, [3640903312, [26]]];

  const v_failX = [6, [3657680931, [25]]];

  const v_failSrc = [6, [24]];

  const v__apply__df_mapIOError_8 = (v__k, v__x) => {
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

  const v__cps__df_mapIOError_8 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_mapIOError_8(v__k, v_io);
        }
        case 6: {
          const v_e = v_io[1];
          return v__apply__df_mapIOError_8(
            v__k,
            [
              6,
              (s => {
                switch (s[0]) {
                  case 3640903312: {
                    return [2269767818, [28]];
                  }
                  case 3657680931: {
                    return [2252990199, [27]];
                  }
                }
              })(v_e)
            ]
          );
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

  const v_remappedX = v__cps__df_mapIOError_8(v_failX, [33]);

  const v_remappedY = v__cps__df_mapIOError_8(v_failY, [33]);

  const v__apply__df_mapIOError_4 = (v__k, v__x) => {
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

  const v__cps__df_mapIOError_4 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_mapIOError_4(v__k, v_io);
        }
        case 6: {
          return v__apply__df_mapIOError_4(v__k, [6, [2269767818, [28]]]);
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

  const v_mappedB = v__cps__df_mapIOError_4(v_failSrc, [31]);

  const v__apply__df_mapIOError_0 = (v__k, v__x) => {
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

  const v__cps__df_mapIOError_0 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_mapIOError_0(v__k, v_io);
        }
        case 6: {
          return v__apply__df_mapIOError_0(v__k, [6, [2252990199, [27]]]);
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

  const v_mappedA = v__cps__df_mapIOError_0(v_failSrc, [29]);

  const v_mappedOk = v__cps__df_mapIOError_0(v_okSrc, [29]);

  const v__apply__df_mapIO_20 = (v__k, v__x) => {
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

  const v__cps__df_mapIO_20 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          const v_a = v_io[1];
          return v__apply__df_mapIO_20(v__k, [5, String(v_a)]);
        }
        case 6: {
          return v__apply__df_mapIO_20(v__k, v_io);
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

  const v__apply__df_handleErrorIO_24 = (v__k, v__x) => {
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

  const v__cps__df_handleErrorIO_24 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_24(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_24(
            v__k,
            (s => {
              switch (s[0]) {
                case 2252990199: {
                  return [7, "ErrA", [5, [0]]];
                }
                case 2269767818: {
                  return [7, "ErrB", [5, [0]]];
                }
              }
            })(v_io[1])
          );
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

  const v__apply__df_handleErrorIO_12 = (v__k, v__x) => {
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

  const v__cps__df_handleErrorIO_12 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_handleErrorIO_12(v__k, v_io);
        }
        case 6: {
          return v__apply__df_handleErrorIO_12(
            v__k,
            (s => {
              switch (s[0]) {
                case 2252990199: {
                  return [7, "ErrA", [5, [0]]];
                }
                case 2269767818: {
                  return [7, "ErrB", [5, [0]]];
                }
              }
            })(v_io[1])
          );
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

  const v__apply__df_andThenIO_56 = (v__k, v__x) => {
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

  const v__apply__df_andThenIO_52 = (v__k, v__x) => {
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

  const v__apply__df_andThenIO_48 = (v__k, v__x) => {
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

  const v__apply__df_andThenIO_44 = (v__k, v__x) => {
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

  const v__apply__df_andThenIO_40 = (v__k, v__x) => {
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

  const v__cps__df_andThenIO_40 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_40(v__k, [7, "=", [5, [0]]]);
        }
        case 6: {
          return v__apply__df_andThenIO_40(v__k, v_io);
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

  const v__apply__df_andThenIO_36 = (v__k, v__x) => {
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

  const v__cps__df_andThenIO_36 = (v_io, v__df_andThenIO_36_cap0_0, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_36(v__k, v__df_andThenIO_36_cap0_0);
        }
        case 6: {
          return v__apply__df_andThenIO_36(v__k, v_io);
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

  const v__apply__df_andThenIO_32 = (v__k, v__x) => {
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

  const v__cps__df_andThenIO_32 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_32(v__k, [7, "\n", [5, [0]]]);
        }
        case 6: {
          return v__apply__df_andThenIO_32(v__k, v_io);
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

  const v__apply__df__rowmono_1_andThenIO_28 = (v__k, v__x) => {
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

  const v__cps__df__rowmono_1_andThenIO_28 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df__rowmono_1_andThenIO_28(
            v__k,
            [7, v_io[1], [5, [0]]]
          );
        }
        case 6: {
          return v__apply__df__rowmono_1_andThenIO_28(v__k, v_io);
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

  const v__cps__df_andThenIO_44 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_44(
            v__k,
            v__cps__df_andThenIO_32(
              v__cps__df_andThenIO_36(
                v__cps__df_andThenIO_40([7, "remappedY", [5, [0]]], [49]),
                v__cps__df_handleErrorIO_24(
                  v__cps__df__rowmono_1_andThenIO_28(
                    v__cps__df_mapIO_20(v_remappedY, [39]),
                    [43]
                  ),
                  [41]
                ),
                [47]
              ),
              [45]
            )
          );
        }
        case 6: {
          return v__apply__df_andThenIO_44(v__k, v_io);
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

  const v__cps__df_andThenIO_48 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_48(
            v__k,
            v__cps__df_andThenIO_32(
              v__cps__df_andThenIO_36(
                v__cps__df_andThenIO_40([7, "remappedX", [5, [0]]], [49]),
                v__cps__df_handleErrorIO_24(
                  v__cps__df__rowmono_1_andThenIO_28(
                    v__cps__df_mapIO_20(v_remappedX, [39]),
                    [43]
                  ),
                  [41]
                ),
                [47]
              ),
              [45]
            )
          );
        }
        case 6: {
          return v__apply__df_andThenIO_48(v__k, v_io);
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

  const v__apply__df__rowmono_0_andThenIO_16 = (v__k, v__x) => {
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

  const v__cps__df__rowmono_0_andThenIO_16 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df__rowmono_0_andThenIO_16(
            v__k,
            [7, v_io[1], [5, [0]]]
          );
        }
        case 6: {
          return v__apply__df__rowmono_0_andThenIO_16(v__k, v_io);
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

  const v__cps__df_andThenIO_52 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_52(
            v__k,
            v__cps__df_andThenIO_32(
              v__cps__df_andThenIO_36(
                v__cps__df_andThenIO_40([7, "mappedOk", [5, [0]]], [49]),
                v__cps__df_handleErrorIO_12(
                  v__cps__df__rowmono_0_andThenIO_16(
                    v__cps__df_mapIO_20(v_mappedOk, [39]),
                    [37]
                  ),
                  [35]
                ),
                [47]
              ),
              [45]
            )
          );
        }
        case 6: {
          return v__apply__df_andThenIO_52(v__k, v_io);
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

  const v__cps__df_andThenIO_56 = (v_io, v__k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v__apply__df_andThenIO_56(
            v__k,
            v__cps__df_andThenIO_32(
              v__cps__df_andThenIO_36(
                v__cps__df_andThenIO_40([7, "mappedB", [5, [0]]], [49]),
                v__cps__df_handleErrorIO_12(
                  v__cps__df__rowmono_0_andThenIO_16(
                    v__cps__df_mapIO_20(v_mappedB, [39]),
                    [37]
                  ),
                  [35]
                ),
                [47]
              ),
              [45]
            )
          );
        }
        case 6: {
          return v__apply__df_andThenIO_56(v__k, v_io);
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

  const main = v__cps__df_andThenIO_44(
    v__cps__df_andThenIO_48(
      v__cps__df_andThenIO_52(
        v__cps__df_andThenIO_56(
          v__cps__df_andThenIO_32(
            v__cps__df_andThenIO_36(
              v__cps__df_andThenIO_40([7, "mappedA", [5, [0]]], [49]),
              v__cps__df_handleErrorIO_12(
                v__cps__df__rowmono_0_andThenIO_16(
                  v__cps__df_mapIO_20(v_mappedA, [39]),
                  [37]
                ),
                [35]
              ),
              [47]
            ),
            [45]
          ),
          [57]
        ),
        [55]
      ),
      [53]
    ),
    [51]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
