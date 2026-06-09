"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __addInt32 = (a, b) => {
    const r = a + b;
    if (r > 2147483647) {
      return [3, [882564211, [18]]];
    }
    if (r < -2147483648) {
      return [3, [3768445577, [17]]];
    }
    return [4, r | 0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

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

  const v_negativeBig = -1000000 | 0;

  const v_big = 1234567 | 0;

  const v_sum = __addInt32(v_big, v_negativeBig);

  const v__lift_13 = v___input => {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 3: {
          const v___f0 = __s[1];
          return [3, [589989748, v___f0]];
        }
        case 4: {
          const v___f0 = __s[1];
          return [4, v___f0];
        }
      }
    }
  };

  const v_line = (s => {
    switch (s[0]) {
      case 3: {
        const v__do_e_0 = s[1];
        return [3, v__do_e_0];
      }
      case 4: {
        const v_s = s[1];
        return v__lift_13(__concat("sum=", String(v_s)));
      }
    }
  })(v_sum);

  const main = (s => {
    switch (s[0]) {
      case 3: {
        const v___w0 = s[1];
        return [7, "FAIL", [5, [0]]];
      }
      case 4: {
        const v_s = s[1];
        return [7, v_s, [5, [0]]];
      }
    }
  })(v_line);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
