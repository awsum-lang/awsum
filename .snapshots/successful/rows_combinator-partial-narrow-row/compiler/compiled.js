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

  const v_oa = [4, 2 | 0];

  const main = [
    7,
    (v__inl26_r =>
      (s => {
        switch (s[0]) {
          case 3: {
            {
              const __s = v__inl26_r[1];
              switch (__s[0]) {
                case 332136403: {
                  return "A";
                }
                case 348914022: {
                  return "B";
                }
              }
            }
          }
          case 4: {
            return String(v__inl26_r[1]);
          }
        }
      })(v__inl26_r))(
      (v__inl16_x =>
        (s => {
          switch (s[0]) {
            case 3: {
              return v__inl16_x;
            }
            case 4: {
              const v__inl19___input = [3, [25]];
              switch (v__inl19___input[0]) {
                case 3: {
                  return [3, [348914022, v__inl19___input[1]]];
                }
                case 4: {
                  return v__inl19___input;
                }
              }
            }
          }
        })(v__inl16_x))(
        (v__inl13___input =>
          (s => {
            switch (s[0]) {
              case 3: {
                return [3, [332136403, v__inl13___input[1]]];
              }
              case 4: {
                return v__inl13___input;
              }
            }
          })(v__inl13___input))(v_oa)
      )
    ),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
