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

  const v_oa = [4, 3 | 0];

  const v_$inl24$x = v_oa;
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [332136403, v_$inl24$x[1]]];
      }
      case 4: {
        const v_$inl18$x = [4, v_$inl24$x[1]];
        switch (v_$inl18$x[0]) {
          case 3: {
            return v_$inl18$x;
          }
          case 4: {
            const v_$inl21$____input = [3, [26]];
            switch (v_$inl21$____input[0]) {
              case 3: {
                return [3, [365691641, v_$inl21$____input[1]]];
              }
              case 4: {
                return v_$inl21$____input;
              }
            }
          }
        }
      }
    }
  })(v_$inl24$x);

  const v_$inl29$r = v_res;
  const main = [
    7,
    (s => {
      switch (s[0]) {
        case 3: {
          {
            const __s = v_$inl29$r[1];
            switch (__s[0]) {
              case 332136403: {
                return "A";
              }
              case 365691641: {
                return "C";
              }
            }
          }
        }
        case 4: {
          return String(v_$inl29$r[1]);
        }
      }
    })(v_$inl29$r),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
