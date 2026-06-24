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

  const v_ob = [3, [25]];

  const v_$inl3$x = v_ob;
  const v_cOrder = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [348914022, v_$inl3$x[1]]];
      }
      case 4: {
        return [4, v_$inl3$x[1]];
      }
    }
  })(v_$inl3$x);

  const v_$inl6$r = v_cOrder;
  const main = [
    7,
    (s => {
      switch (s[0]) {
        case 3: {
          return "B";
        }
        case 4: {
          return String(v_$inl6$r[1]);
        }
      }
    })(v_$inl6$r),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
