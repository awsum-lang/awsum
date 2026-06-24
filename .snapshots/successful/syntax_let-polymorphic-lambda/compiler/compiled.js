"use strict";

(() => {
  const __print = s => {
    process.stdout.write(String(s));
    return [0];
  };

  const __concat = (a, b) =>
    a.length + b.length > 134217728 ? [3, [19]] : [4, a + b];

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

  const v_res = (s => {
    switch (s[0]) {
      case 3: {
        const v_$inl7$$do__e__2 = s[1];
        return [3, v_$inl7$$do__e__2];
      }
      case 4: {
        const v_$inl8$s0 = s[1];
        {
          const __s = __concat(v_$inl8$s0, "hello");
          switch (__s[0]) {
            case 3: {
              const v_$inl9$$do__e__1 = __s[1];
              return [3, v_$inl9$$do__e__1];
            }
            case 4: {
              const v_$inl10$s1 = __s[1];
              {
                const __s = __concat(v_$inl10$s1, "/");
                switch (__s[0]) {
                  case 3: {
                    const v_$inl11$$do__e__0 = __s[1];
                    return [3, v_$inl11$$do__e__0];
                  }
                  case 4: {
                    const v_$inl12$s2 = __s[1];
                    return __concat(v_$inl12$s2, "A");
                  }
                }
              }
            }
          }
        }
      }
    }
  })(__concat(String(42 | 0), "/"));

  const v_$apply$$df$handleErrorIO$1 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 25: {
          return v_$x;
        }
        case 26: {
          const v_$pk__26 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__26;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$1 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$1(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$1(
            v_$k,
            [7, "STRING_TOO_LONG", [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [26, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$5 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 27: {
          return v_$x;
        }
        case 28: {
          const v_$pk__28 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__28;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$5 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$5(v_$k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$5(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [28, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl15$x = v_res;
  const main = v_$cps$$df$handleErrorIO$1(
    v_$cps$$df$andThenIO$5(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl15$x[1]];
          }
          case 4: {
            return [5, v_$inl15$x[1]];
          }
        }
      })(v_$inl15$x),
      [27]
    ),
    [25]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
