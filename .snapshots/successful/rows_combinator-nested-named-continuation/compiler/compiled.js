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

  const v_oa = [4, 3 | 0];

  const v__inl24_x = v_oa;
  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [332136403, v__inl24_x[1]]];
      }
      case 4: {
        const v__inl18_x = [4, v__inl24_x[1]];
        switch (v__inl18_x[0]) {
          case 3: {
            return v__inl18_x;
          }
          case 4: {
            const v__inl21___input = [3, [26]];
            switch (v__inl21___input[0]) {
              case 3: {
                return [3, [365691641, v__inl21___input[1]]];
              }
              case 4: {
                return v__inl21___input;
              }
            }
          }
        }
      }
    }
  })(v__inl24_x);

  const v__inl29_r = v_res;
  const main = [
    7,
    (s => {
      switch (s[0]) {
        case 3: {
          {
            const __s = v__inl29_r[1];
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
          return String(v__inl29_r[1]);
        }
      }
    })(v__inl29_r),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
