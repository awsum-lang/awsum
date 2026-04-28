"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_map(v_f, v_list){
    return (v__cps_map)(v_f, v_list, [0]);
}

function v__cps_map(v_f, v_list, v__k){
  while (true) {
    {
      const __s = v_list;
      switch (__s[0]) {
        case 0: {
          const v_head = __s[1];
          const v_tail = __s[2];
          const __t0 = v_f;
          const __t1 = v_tail;
          const __t2 = [1, v__k, v_f, v_head];
          v_f = __t0;
          v_list = __t1;
          v__k = __t2;
          continue;
        }
        case 1: {
          return (v__apply_map)(v__k, [1]);
        }
      }
    }
  }
}

function v__apply_map(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          const v_f = __s[2];
          const v_head = __s[3];
          const __t0 = v__pk_1;
          const __t1 = [0, (v_f)(v_head), v__x];
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v_show(v_xs){
    return (v__cps_show)(v_xs, [0]);
}

function v__cps_show(v_xs, v__k){
  while (true) {
    {
      const __s = v_xs;
      switch (__s[0]) {
        case 0: {
          const v_h = __s[1];
          const v_t = __s[2];
          const __t0 = v_t;
          const __t1 = [1, v__k, v_h];
          v_xs = __t0;
          v__k = __t1;
          continue;
        }
        case 1: {
          return (v__apply_show)(v__k, "");
        }
      }
    }
  }
}

function v__apply_show(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          const v_h = __s[2];
          const __t0 = v__pk_1;
          const __t1 = ((v_h + ",") + v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v_shout(v_s){
    return (v_s + "!");
}

function main(v__input){
    return __print((v_show)((v_map)(v_shout, [0, "a", [0, "b", [0, "c", [1]]]])));
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();