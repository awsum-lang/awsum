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

  const v_$apply$$scc$handleA__handleB = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 34: {
          return v_$x;
        }
        case 35: {
          const v_$pk__35 = v_$k[1];
          switch (v_$x[0]) {
            case 3: {
              v_$k = v_$pk__35;
              continue;
            }
            case 4: {
              v_$k = v_$pk__35;
              v_$x = __concat("A", v_$x[1]);
              continue;
            }
          }
        }
        case 36: {
          const v_$pk__36 = v_$k[1];
          switch (v_$x[0]) {
            case 3: {
              v_$k = v_$pk__36;
              continue;
            }
            case 4: {
              v_$k = v_$pk__36;
              v_$x = __concat("B", v_$x[1]);
              continue;
            }
          }
        }
        case 37: {
          const v_$pk__37 = v_$k[1];
          switch (v_$x[0]) {
            case 3: {
              v_$k = v_$pk__37;
              continue;
            }
            case 4: {
              v_$k = v_$pk__37;
              v_$x = __concat("C", v_$x[1]);
              continue;
            }
          }
        }
      }
    }
  };

  const v_$cps$$scc$handleA__handleB = (v_$args, v_$k) => {
    while (true) {
      switch (v_$args[0]) {
        case 28: {
          const v_step = v_$args[1];
          switch (v_step[0]) {
            case 24: {
              v_$args = (v_$args[0] = 29, v_$args[1] = [25], v_$args);
              v_$k = [35, v_$k];
              continue;
            }
            case 25: {
              v_$args = (v_$args[0] = 29, v_$args);
              continue;
            }
            case 26: {
              v_$args = (v_$args[0] = 29, v_$args);
              continue;
            }
            case 27: {
              return v_$apply$$scc$handleA__handleB(v_$k, [4, ""]);
            }
          }
        }
        case 29: {
          const v_step = v_$args[1];
          switch (v_step[0]) {
            case 24: {
              v_$args = (v_$args[0] = 28, v_$args);
              continue;
            }
            case 25: {
              v_$args = (v_$args[0] = 28, v_$args[1] = [26], v_$args);
              v_$k = [36, v_$k];
              continue;
            }
            case 26: {
              v_$args = (v_$args[0] = 28, v_$args[1] = [27], v_$args);
              v_$k = [37, v_$k];
              continue;
            }
            case 27: {
              return v_$apply$$scc$handleA__handleB(v_$k, [4, ""]);
            }
          }
        }
      }
    }
  };

  const v_res = v_$cps$$scc$handleA__handleB([28, [24]], [34]);

  const v_$apply$$df$handleErrorIO$0 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 30: {
          return v_$x;
        }
        case 31: {
          const v_$pk__31 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__31;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$handleErrorIO$0 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$handleErrorIO$0(v_$k, v_io);
        }
        case 6: {
          return v_$apply$$df$handleErrorIO$0(
            v_$k,
            [7, "STRING_TOO_LONG", [5, [0]]]
          );
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [31, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$apply$$df$andThenIO$4 = (v_$k, v_$x) => {
    while (true) {
      switch (v_$k[0]) {
        case 32: {
          return v_$x;
        }
        case 33: {
          const v_$pk__33 = v_$k[1];
          v_$x = (v_$k[0] = 7, v_$k[1] = v_$k[2], v_$k[2] = v_$x, v_$k);
          v_$k = v_$pk__33;
          continue;
        }
      }
    }
  };

  const v_$cps$$df$andThenIO$4 = (v_io, v_$k) => {
    while (true) {
      switch (v_io[0]) {
        case 5: {
          return v_$apply$$df$andThenIO$4(v_$k, [7, v_io[1], [5, [0]]]);
        }
        case 6: {
          return v_$apply$$df$andThenIO$4(v_$k, v_io);
        }
        case 7: {
          const v_s = v_io[1];
          const v_next = v_io[2];
          v_$k = [33, v_$k, v_s];
          v_io = v_next;
          continue;
        }
      }
    }
  };

  const v_$inl3$x = v_res;
  const main = v_$cps$$df$handleErrorIO$0(
    v_$cps$$df$andThenIO$4(
      (s => {
        switch (s[0]) {
          case 3: {
            return [6, v_$inl3$x[1]];
          }
          case 4: {
            return [5, v_$inl3$x[1]];
          }
        }
      })(v_$inl3$x),
      [32]
    ),
    [30]
  );

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
