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
          const v_$inl0$eff = __print(v_io[1]);
          v_io = v_io[2];
          continue;
        }
      }
    }
  };

  const v_$inl17$$cl = [10];
  const v_$inl18$$arg0 = 7 | 0;
  const v_$inl28$g = (s => {
    switch (s[0]) {
      case 8: {
        return v_$inl17$$cl[1];
      }
      case 9: {
        return [8, v_$inl17$$cl[1], v_$inl18$$arg0];
      }
      case 10: {
        return [9, v_$inl18$$arg0];
      }
    }
  })(v_$inl17$$cl);
  const v_$inl19$$arg0 = 8 | 0;
  const v_$inl23$h = (s => {
    switch (s[0]) {
      case 8: {
        return v_$inl28$g[1];
      }
      case 9: {
        return [8, v_$inl28$g[1], v_$inl19$$arg0];
      }
      case 10: {
        return [9, v_$inl19$$arg0];
      }
    }
  })(v_$inl28$g);
  const v_$inl24$$arg0 = 9 | 0;
  const main = [
    7,
    String(
      (s => {
        switch (s[0]) {
          case 8: {
            return v_$inl23$h[1];
          }
          case 9: {
            return [8, v_$inl23$h[1], v_$inl24$$arg0];
          }
          case 10: {
            return [9, v_$inl24$$arg0];
          }
        }
      })(v_$inl23$h)
    ),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
