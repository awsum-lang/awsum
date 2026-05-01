"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return undefined; }

function v_showUnit(v__wild0){
    return "Unit";
}

const v_defaultJust = [1, [0]];

const v_defaultBools = [1, [0], [1, [1], [0]]];

const v_defaultRight = [1, [1, [1]]];

function v_dispatchInner(v_x){
    {
      const __s = v_x;
      switch (__s[0]) {
        case 796142685: {
          const v_b = __s[1];
          {
            const __s = v_b;
            switch (__s[0]) {
              case 0: {
                return "T";
              }
              case 1: {
                return "F";
              }
            }
          }
        }
        case 1759602215: {
          const v_u = __s[1];
          return (v_showUnit)(v_u);
        }
      }
    }
}

function v_describeMaybe(v_m){
    {
      const __s = v_m;
      switch (__s[0]) {
        case 0: {
          return "N";
        }
        case 1: {
          const v_inner = __s[1];
          return ("J" + (v_dispatchInner)(v_inner));
        }
      }
    }
}

function v_describeLst(v_xs){
    return (v__cps_describeLst)(v_xs, [0]);
}

function v__cps_describeLst(v_xs, v__k){
  while (true) {
    {
      const __s = v_xs;
      switch (__s[0]) {
        case 0: {
          return (v__apply_describeLst)(v__k, "");
        }
        case 1: {
          const v_h = __s[1];
          const v_t = __s[2];
          const __t0 = v_t;
          const __t1 = [1, v__k, v_h];
          v_xs = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply_describeLst(v__k, v__x){
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
          const __t1 = ((v_dispatchInner)(v_h) + v__x);
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v_describeEither(v_r){
    {
      const __s = v_r;
      switch (__s[0]) {
        case 0: {
          const v__e = __s[1];
          return "ErrA";
        }
        case 1: {
          const v_m = __s[1];
          return (v_describeMaybe)(v_m);
        }
      }
    }
}

const v_summary = (((((v_describeMaybe)((v__lift_0)(v_defaultJust)) + " / ") + (v_describeLst)((v__lift_1)(v_defaultBools))) + " / ") + (v_describeEither)((v__lift_2)(v_defaultRight)));

function main(v__input){
    return __print(v_summary);
}

function v__lift_0(v___input){
    {
      const __s = v___input;
      switch (__s[0]) {
        case 0: {
          return [0];
        }
        case 1: {
          const v___f0 = __s[1];
          return [1, [796142685, v___f0]];
        }
      }
    }
}

function v__lift_1(v___input){
    return (v__cps__lift_1)(v___input, [0]);
}

function v__cps__lift_1(v___input, v__k){
  while (true) {
    {
      const __s = v___input;
      switch (__s[0]) {
        case 0: {
          return (v__apply__lift_1)(v__k, [0]);
        }
        case 1: {
          const v___f0 = __s[1];
          const v___f1 = __s[2];
          const __t0 = v___f1;
          const __t1 = [1, v__k, v___f0];
          v___input = __t0;
          v__k = __t1;
          continue;
        }
      }
    }
  }
}

function v__apply__lift_1(v__k, v__x){
  while (true) {
    {
      const __s = v__k;
      switch (__s[0]) {
        case 0: {
          return v__x;
        }
        case 1: {
          const v__pk_1 = __s[1];
          const v___f0 = __s[2];
          const __t0 = v__pk_1;
          const __t1 = [1, [796142685, v___f0], v__x];
          v__k = __t0;
          v__x = __t1;
          continue;
        }
      }
    }
  }
}

function v__lift_2(v___input){
    {
      const __s = v___input;
      switch (__s[0]) {
        case 0: {
          const v___f0 = __s[1];
          return [0, v___f0];
        }
        case 1: {
          const v___f0 = __s[1];
          return [1, (v__lift_0)(v___f0)];
        }
      }
    }
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') main(arg);
}

})();