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

  const v_oa = [4, 2 | 0];

  const v_$inl13$____input = v_oa;
  const v_$inl16$x = (s => {
    switch (s[0]) {
      case 3: {
        return [3, [332136403, v_$inl13$____input[1]]];
      }
      case 4: {
        return v_$inl13$____input;
      }
    }
  })(v_$inl13$____input);
  const v_$inl26$r = (s => {
    switch (s[0]) {
      case 3: {
        return v_$inl16$x;
      }
      case 4: {
        const v_$inl19$____input = [3, [25]];
        switch (v_$inl19$____input[0]) {
          case 3: {
            return [3, [348914022, v_$inl19$____input[1]]];
          }
          case 4: {
            return v_$inl19$____input;
          }
        }
      }
    }
  })(v_$inl16$x);
  const main = [
    7,
    (s => {
      switch (s[0]) {
        case 3: {
          {
            const __s = v_$inl26$r[1];
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
          return String(v_$inl26$r[1]);
        }
      }
    })(v_$inl26$r),
    [5, [0]]
  ];

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
