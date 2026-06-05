"use strict";

(() => {
  const __print = (s) => {
    process.stdout.write(String(s));
    return [0];
  };

  const __predInt32 = (x) => {
    return x === -2147483648 ? [3, [17]] : [4, x - 1 | 0];
  };

  const __eqInt32 = (a, b) => {
    return a === b ? [1] : [2];
  };

  const v_showUnderflowError = (v__wild0) => {
    return "UnderflowError";
  };

  const v_runIO = (v_io) => {
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

  const v__scc_deepestLeftA_deepestLeftB_deepestLeftC = (v__args) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 26: {
            const v_lastV = __s[1];
            const v_t = __s[2];
            {
              const __s = v_t;
              switch (__s[0]) {
                case 24: {
                  return v_lastV;
                }
                case 25: {
                  const v_l = __s[1];
                  const v_v = __s[2];
                  const v__r = __s[3];
                  const __t0 = (v__args[0] = 27, v__args[1] = v_v, v__args[2] = v_l, v__args);
                  v__args = __t0;
                  continue;
                }
              }
            }
          }
          case 27: {
            const v_lastV = __s[1];
            const v_t = __s[2];
            {
              const __s = v_t;
              switch (__s[0]) {
                case 24: {
                  return v_lastV;
                }
                case 25: {
                  const v_l = __s[1];
                  const v_v = __s[2];
                  const v__r = __s[3];
                  const __t0 = (v__args[0] = 28, v__args[1] = v_v, v__args[2] = v_l, v__args);
                  v__args = __t0;
                  continue;
                }
              }
            }
          }
          case 28: {
            const v_lastV = __s[1];
            const v_t = __s[2];
            {
              const __s = v_t;
              switch (__s[0]) {
                case 24: {
                  return v_lastV;
                }
                case 25: {
                  const v_l = __s[1];
                  const v_v = __s[2];
                  const v__r = __s[3];
                  const __t0 = (v__args[0] = 26, v__args[1] = v_v, v__args[2] = v_l, v__args);
                  v__args = __t0;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_deepestLeftA = (v_lastV, v_t) => {
    return v__scc_deepestLeftA_deepestLeftB_deepestLeftC([26, v_lastV, v_t]);
  };

  const v__scc__apply_mirror__cps_mirror = (v__args) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 38: {
            const v__k = __s[1];
            const v__x = __s[2];
            {
              const __s = v__k;
              switch (__s[0]) {
                case 29: {
                  return v__x;
                }
                case 31: {
                  const v__pk_31 = __s[1];
                  const v__rcv_0 = __s[2];
                  const v_v = __s[3];
                  const __t0 = (v__args[0] = 38, v__args[1] = v__pk_31, v__args[2] = [
                    25,
                    v__rcv_0,
                    v_v,
                    v__x
                  ], v__args);
                  v__args = __t0;
                  continue;
                }
                case 30: {
                  const v__pk_30 = __s[1];
                  const v_l = __s[2];
                  const v_v = __s[3];
                  const __t0 = (v__args[0] = 39, v__args[1] = v_l, v__args[2] = [
                    31,
                    v__pk_30,
                    v__x,
                    v_v
                  ], v__args);
                  v__args = __t0;
                  continue;
                }
              }
            }
          }
          case 39: {
            const v_t = __s[1];
            const v__k = __s[2];
            {
              const __s = v_t;
              switch (__s[0]) {
                case 24: {
                  const __t0 = (v__args[0] = 38, v__args[1] = v__k, v__args[2] = [
                    24
                  ], v__args);
                  v__args = __t0;
                  continue;
                }
                case 25: {
                  const v_l = __s[1];
                  const v_v = __s[2];
                  const v_r = __s[3];
                  const __t0 = (v__args[0] = 39, v__args[1] = v_r, v__args[2] = [
                    30,
                    v__k,
                    v_l,
                    v_v
                  ], v__args);
                  v__args = __t0;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__scc__apply__lift_24__cps__lift_24 = (v__args) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 40: {
            const v__k = __s[1];
            const v__x = __s[2];
            {
              const __s = v__k;
              switch (__s[0]) {
                case 35: {
                  return v__x;
                }
                case 37: {
                  const v__pk_37 = __s[1];
                  const v__rcv_0 = __s[2];
                  const v___f1 = __s[3];
                  const __t0 = (v__args[0] = 40, v__args[1] = v__pk_37, v__args[2] = [
                    25,
                    v__rcv_0,
                    v___f1,
                    v__x
                  ], v__args);
                  v__args = __t0;
                  continue;
                }
                case 36: {
                  const v__pk_36 = __s[1];
                  const v___f1 = __s[2];
                  const v___f2 = __s[3];
                  const __t0 = (v__args[0] = 41, v__args[1] = v___f2, v__args[2] = [
                    37,
                    v__pk_36,
                    v__x,
                    v___f1
                  ], v__args);
                  v__args = __t0;
                  continue;
                }
              }
            }
          }
          case 41: {
            const v___input = __s[1];
            const v__k = __s[2];
            {
              const __s = v___input;
              switch (__s[0]) {
                case 24: {
                  const __t0 = (v__args[0] = 40, v__args[1] = v__k, v__args[2] = [
                    24
                  ], v__args);
                  v__args = __t0;
                  continue;
                }
                case 25: {
                  const v___f0 = __s[1];
                  const v___f1 = __s[2];
                  const v___f2 = __s[3];
                  const __t0 = (v__args[0] = 41, v__args[1] = v___f0, v__args[2] = [
                    36,
                    v__k,
                    v___f1,
                    v___f2
                  ], v__args);
                  v__args = __t0;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__scc__apply__lift_23__cps__lift_23 = (v__args) => {
    while (true) {
      {
        const __s = v__args;
        switch (__s[0]) {
          case 42: {
            const v__k = __s[1];
            const v__x = __s[2];
            {
              const __s = v__k;
              switch (__s[0]) {
                case 32: {
                  return v__x;
                }
                case 34: {
                  const v__pk_34 = __s[1];
                  const v__rcv_0 = __s[2];
                  const v___f1 = __s[3];
                  const __t0 = (v__args[0] = 42, v__args[1] = v__pk_34, v__args[2] = [
                    25,
                    v__rcv_0,
                    v___f1,
                    v__x
                  ], v__args);
                  v__args = __t0;
                  continue;
                }
                case 33: {
                  const v__pk_33 = __s[1];
                  const v___f1 = __s[2];
                  const v___f2 = __s[3];
                  const __t0 = (v__args[0] = 43, v__args[1] = v___f2, v__args[2] = [
                    34,
                    v__pk_33,
                    v__x,
                    v___f1
                  ], v__args);
                  v__args = __t0;
                  continue;
                }
              }
            }
          }
          case 43: {
            const v___input = __s[1];
            const v__k = __s[2];
            {
              const __s = v___input;
              switch (__s[0]) {
                case 24: {
                  const __t0 = (v__args[0] = 42, v__args[1] = v__k, v__args[2] = [
                    24
                  ], v__args);
                  v__args = __t0;
                  continue;
                }
                case 25: {
                  const v___f0 = __s[1];
                  const v___f1 = __s[2];
                  const v___f2 = __s[3];
                  const __t0 = (v__args[0] = 43, v__args[1] = v___f0, v__args[2] = [
                    33,
                    v__k,
                    v___f1,
                    v___f2
                  ], v__args);
                  v__args = __t0;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__cps_mirror = (v_t, v__k) => {
    return v__scc__apply_mirror__cps_mirror([39, v_t, v__k]);
  };

  const v_mirror = (v_t) => {
    return v__cps_mirror(v_t, [29]);
  };

  const v__cps__lift_24 = (v___input, v__k) => {
    return v__scc__apply__lift_24__cps__lift_24([41, v___input, v__k]);
  };

  const v__lift_24 = (v___input) => {
    return v__cps__lift_24(v___input, [35]);
  };

  const v_mirrorN = (v_times, v_t) => {
    while (true) {
      {
        const __s = __eqInt32(v_times, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [4, v__lift_24(v_t)];
          }
          case 2: {
            {
              const __s = __predInt32(v_times);
              switch (__s[0]) {
                case 3: {
                  const v__do_e_6 = __s[1];
                  return [3, v__do_e_6];
                }
                case 4: {
                  const v_m = __s[1];
                  const __t0 = v_m;
                  const __t1 = v_mirror(v_t);
                  v_times = __t0;
                  v_t = __t1;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v__cps__lift_23 = (v___input, v__k) => {
    return v__scc__apply__lift_23__cps__lift_23([43, v___input, v__k]);
  };

  const v__lift_23 = (v___input) => {
    return v__cps__lift_23(v___input, [32]);
  };

  const v_buildLeft = (v_depth, v_acc) => {
    while (true) {
      {
        const __s = __eqInt32(v_depth, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [4, v_acc];
          }
          case 2: {
            {
              const __s = __predInt32(v_depth);
              switch (__s[0]) {
                case 3: {
                  const v__do_e_4 = __s[1];
                  return [3, v__do_e_4];
                }
                case 4: {
                  const v_d = __s[1];
                  const __t0 = v_d;
                  const __t1 = [25, v_acc, v_depth, v__lift_23([24])];
                  v_depth = __t0;
                  v_acc = __t1;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_buildRight = (v_depth, v_acc) => {
    while (true) {
      {
        const __s = __eqInt32(v_depth, 0 | 0);
        switch (__s[0]) {
          case 1: {
            return [4, v_acc];
          }
          case 2: {
            {
              const __s = __predInt32(v_depth);
              switch (__s[0]) {
                case 3: {
                  const v__do_e_5 = __s[1];
                  return [3, v__do_e_5];
                }
                case 4: {
                  const v_d = __s[1];
                  const __t0 = v_d;
                  const __t1 = [25, v__lift_23([24]), v_depth, v_acc];
                  v_depth = __t0;
                  v_acc = __t1;
                  continue;
                }
              }
            }
          }
        }
      }
    }
  };

  const v_buildTree = (v_depth) => {
    {
      const __s = v_buildLeft(v_depth, v__lift_23([24]));
      switch (__s[0]) {
        case 3: {
          const v__do_e_3 = __s[1];
          return [3, v__do_e_3];
        }
        case 4: {
          const v_l = __s[1];
          {
            const __s = v_buildRight(v_depth, v__lift_23([24]));
            switch (__s[0]) {
              case 3: {
                const v__do_e_2 = __s[1];
                return [3, v__do_e_2];
              }
              case 4: {
                const v_r = __s[1];
                return [4, [25, v_l, 0 | 0, v_r]];
              }
            }
          }
        }
      }
    }
  };

  const v_runDemo = ((s) => {
    switch (s[0]) {
      case 3: {
        const v__do_e_1 = s[1];
        return [3, v__do_e_1];
      }
      case 4: {
        const v_tree = s[1];
        return ((s) => {
          switch (s[0]) {
            case 3: {
              const v__do_e_0 = s[1];
              return [3, v__do_e_0];
            }
            case 4: {
              const v_mirrored = s[1];
              return [4, v_deepestLeftA(0 | 0, v_mirrored)];
            }
          }
        })(v_mirrorN(500 | 0, v_tree));
      }
    }
  })(v_buildTree(10000 | 0));

  const main = ((s) => {
    switch (s[0]) {
      case 3: {
        const v_e = s[1];
        return [7, v_showUnderflowError(v_e), [5, [0]]];
      }
      case 4: {
        const v_n = s[1];
        return [7, String(v_n), [5, [0]]];
      }
    }
  })(v_runDemo);

  if (typeof require !== "undefined" && require.main === module) {
    if (typeof main !== "undefined") {
      v_runIO(main);
    }
  }
})();
