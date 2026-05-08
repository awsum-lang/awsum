"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __concat(a, b){ return (a.length + b.length > 134217728) ? [0, [0]] : [1, a + b]; }

function v_runIO(v_io){
  while (true) {
    {
      const __s = v_io;
      switch (__s[0]) {
        case 0: {
          const v_u = __s[1];
          return v_u;
        }
        case 2: {
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
}

function v_shout(v_s){
    return __concat(v_s, "!");
}

const main = (v__let_7)((v_show)((v__df_map_0)([0, "a", [0, "b", [0, "c", [1]]]])));

function v__let_7(v_res){
    {
      const __s = v_res;
      switch (__s[0]) {
        case 0: {
          const v___w0 = __s[1];
          return [2, "STRING_TOO_LONG", [0, [0]]];
        }
        case 1: {
          const v_s = __s[1];
          return [2, v_s, [0, [0]]];
        }
      }
    }
}

function v__df_map_0(v_list){
    return (v__cps__df_map_0)(v_list, [0]);
}

function v__cps__df_map_0(v_list, v__k){
  while (true) {
    {
      const __s = v_list;
      switch (__s[0]) {
        case 0: {
          const v_head = __s[1];
          const v_tail = __s[2];
          const __t0 = v_tail;
          const __t1 = [1, v__k, v_head];
          v_list = __t0;
          v__k = __t1;
          continue;
        }
        case 1: {
          return (v__apply__df_map_0)(v__k, [1]);
        }
      }
    }
  }
}

function v__apply__df_map_0(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          const v_head = __s[2];
          const __t0 = v__pk_1;
          const __t1 = [0, (v_shout)(v_head), v__x];
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__scc_show_showCons(v__args){
    return (v__cps__scc_show_showCons)(v__args, [0]);
}

function v__cps__scc_show_showCons(v__args, v__k){
  while (true) {
    {
      const __s = v__args;
      switch (__s[0]) {
        case 0: {
          const v_xs = __s[1];
          {
            const __s = v_xs;
            switch (__s[0]) {
              case 0: {
                const v_h = __s[1];
                const v_t = __s[2];
                const __t0 = [1, v_h, v_t];
                const __t1 = v__k;
                v__args = __t0;
                v__k = __t1;
                continue;
              }
              case 1: {
                return (v__apply__scc_show_showCons)(v__k, [1, ""]);
              }
            }
          }
        }
        case 1: {
          const v_h = __s[1];
          const v_t = __s[2];
          {
            const __s = v_h;
            switch (__s[0]) {
              case 0: {
                const v__do_e_18_3 = __s[1];
                return (v__apply__scc_show_showCons)(v__k, [0, v__do_e_18_3]);
              }
              case 1: {
                const v_hStr = __s[1];
                const __t0 = [0, v_t];
                const __t1 = [1, v__k, v_hStr];
                v__args = __t0;
                v__k = __t1;
                continue;
              }
            }
          }
        }
      }
    }
  }
}

function v__apply__scc_show_showCons(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          const v_hStr = __s[2];
          {
            const __s = v__x;
            switch (__s[0]) {
              case 0: {
                const v__do_e_19_3 = __s[1];
                const __t0 = v__pk_1;
                const __t1 = [0, v__do_e_19_3];
                v__k = __t0;
                v__x = __t1;
                continue;
              }
              case 1: {
                const v_rest = __s[1];
                {
                  const __s = __concat(v_hStr, ",");
                  switch (__s[0]) {
                    case 0: {
                      const v__do_e_20_3 = __s[1];
                      const __t0 = v__pk_1;
                      const __t1 = [0, v__do_e_20_3];
                      v__k = __t0;
                      v__x = __t1;
                      continue;
                    }
                    case 1: {
                      const v_comma = __s[1];
                      const __t0 = v__pk_1;
                      const __t1 = __concat(v_comma, v_rest);
                      v__k = __t0;
                      v__x = __t1;
                      continue;
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

function v_show(v_xs){
    return (v__scc_show_showCons)([0, v_xs]);
}

if (typeof require !== 'undefined' && require.main === module) {
  if (typeof main !== 'undefined') v_runIO(main);
}

})();