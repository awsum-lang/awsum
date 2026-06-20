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

  const v__inl17__cl = [10];
  const v__inl18__arg0 = 7 | 0;
  const v__inl28_g = (s => {
    switch (s[0]) {
      case 8: {
        return v__inl17__cl[1];
      }
      case 9: {
        return [8, v__inl17__cl[1], v__inl18__arg0];
      }
      case 10: {
        return [9, v__inl18__arg0];
      }
    }
  })(v__inl17__cl);
  const v__inl19__arg0 = 8 | 0;
  const v__inl23_h = (s => {
    switch (s[0]) {
      case 8: {
        return v__inl28_g[1];
      }
      case 9: {
        return [8, v__inl28_g[1], v__inl19__arg0];
      }
      case 10: {
        return [9, v__inl19__arg0];
      }
    }
  })(v__inl28_g);
  const v__inl24__arg0 = 9 | 0;
  const main = [
    7,
    String(
      (s => {
        switch (s[0]) {
          case 8: {
            return v__inl23_h[1];
          }
          case 9: {
            return [8, v__inl23_h[1], v__inl24__arg0];
          }
          case 10: {
            return [9, v__inl24__arg0];
          }
        }
      })(v__inl23_h)
    ),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
