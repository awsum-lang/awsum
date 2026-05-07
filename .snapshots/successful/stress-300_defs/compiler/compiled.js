"use strict";
(function () {
function __print(s){ process.stdout.write(String(s)); return [0]; }
function __entryArgEither(arg){ if (arg.length > 134217728) return [0, [589989748, [0]]]; for (let i = 0; i < arg.length; i++) { const c = arg.charCodeAt(i); if (c >= 0xD800 && c <= 0xDBFF) { if (i + 1 >= arg.length) return [0, [502975519, [0]]]; const next = arg.charCodeAt(i + 1); if (next < 0xDC00 || next > 0xDFFF) return [0, [502975519, [0]]]; i++; } else if (c >= 0xDC00 && c <= 0xDFFF) return [0, [502975519, [0]]]; } return [1, arg]; }

function v_and(v_a, v_b){
    {
      const __s = v_a;
      switch (__s[0]) {
        case 0: {
          return v_b;
        }
        case 1: {
          return [1];
        }
      }
    }
}

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

const v_b1 = [0];

const v_b2 = [0];

const v_b3 = [0];

const v_b4 = [0];

const v_b5 = [0];

const v_b6 = [0];

const v_b7 = [0];

const v_b8 = [0];

const v_b9 = [0];

const v_b10 = [0];

const v_b11 = [0];

const v_b12 = [0];

const v_b13 = [0];

const v_b14 = [0];

const v_b15 = [0];

const v_b16 = [0];

const v_b17 = [0];

const v_b18 = [0];

const v_b19 = [0];

const v_b20 = [0];

const v_b21 = [0];

const v_b22 = [0];

const v_b23 = [0];

const v_b24 = [0];

const v_b25 = [0];

const v_b26 = [0];

const v_b27 = [0];

const v_b28 = [0];

const v_b29 = [0];

const v_b30 = [0];

const v_b31 = [0];

const v_b32 = [0];

const v_b33 = [0];

const v_b34 = [0];

const v_b35 = [0];

const v_b36 = [0];

const v_b37 = [0];

const v_b38 = [0];

const v_b39 = [0];

const v_b40 = [0];

const v_b41 = [0];

const v_b42 = [0];

const v_b43 = [0];

const v_b44 = [0];

const v_b45 = [0];

const v_b46 = [0];

const v_b47 = [0];

const v_b48 = [0];

const v_b49 = [0];

const v_b50 = [0];

const v_b51 = [0];

const v_b52 = [0];

const v_b53 = [0];

const v_b54 = [0];

const v_b55 = [0];

const v_b56 = [0];

const v_b57 = [0];

const v_b58 = [0];

const v_b59 = [0];

const v_b60 = [0];

const v_b61 = [0];

const v_b62 = [0];

const v_b63 = [0];

const v_b64 = [0];

const v_b65 = [0];

const v_b66 = [0];

const v_b67 = [0];

const v_b68 = [0];

const v_b69 = [0];

const v_b70 = [0];

const v_b71 = [0];

const v_b72 = [0];

const v_b73 = [0];

const v_b74 = [0];

const v_b75 = [0];

const v_b76 = [0];

const v_b77 = [0];

const v_b78 = [0];

const v_b79 = [0];

const v_b80 = [0];

const v_b81 = [0];

const v_b82 = [0];

const v_b83 = [0];

const v_b84 = [0];

const v_b85 = [0];

const v_b86 = [0];

const v_b87 = [0];

const v_b88 = [0];

const v_b89 = [0];

const v_b90 = [0];

const v_b91 = [0];

const v_b92 = [0];

const v_b93 = [0];

const v_b94 = [0];

const v_b95 = [0];

const v_b96 = [0];

const v_b97 = [0];

const v_b98 = [0];

const v_b99 = [0];

const v_b100 = [0];

const v_b101 = [0];

const v_b102 = [0];

const v_b103 = [0];

const v_b104 = [0];

const v_b105 = [0];

const v_b106 = [0];

const v_b107 = [0];

const v_b108 = [0];

const v_b109 = [0];

const v_b110 = [0];

const v_b111 = [0];

const v_b112 = [0];

const v_b113 = [0];

const v_b114 = [0];

const v_b115 = [0];

const v_b116 = [0];

const v_b117 = [0];

const v_b118 = [0];

const v_b119 = [0];

const v_b120 = [0];

const v_b121 = [0];

const v_b122 = [0];

const v_b123 = [0];

const v_b124 = [0];

const v_b125 = [0];

const v_b126 = [0];

const v_b127 = [0];

const v_b128 = [0];

const v_b129 = [0];

const v_b130 = [0];

const v_b131 = [0];

const v_b132 = [0];

const v_b133 = [0];

const v_b134 = [0];

const v_b135 = [0];

const v_b136 = [0];

const v_b137 = [0];

const v_b138 = [0];

const v_b139 = [0];

const v_b140 = [0];

const v_b141 = [0];

const v_b142 = [0];

const v_b143 = [0];

const v_b144 = [0];

const v_b145 = [0];

const v_b146 = [0];

const v_b147 = [0];

const v_b148 = [0];

const v_b149 = [0];

const v_b150 = [0];

const v_b151 = [0];

const v_b152 = [0];

const v_b153 = [0];

const v_b154 = [0];

const v_b155 = [0];

const v_b156 = [0];

const v_b157 = [0];

const v_b158 = [0];

const v_b159 = [0];

const v_b160 = [0];

const v_b161 = [0];

const v_b162 = [0];

const v_b163 = [0];

const v_b164 = [0];

const v_b165 = [0];

const v_b166 = [0];

const v_b167 = [0];

const v_b168 = [0];

const v_b169 = [0];

const v_b170 = [0];

const v_b171 = [0];

const v_b172 = [0];

const v_b173 = [0];

const v_b174 = [0];

const v_b175 = [0];

const v_b176 = [0];

const v_b177 = [0];

const v_b178 = [0];

const v_b179 = [0];

const v_b180 = [0];

const v_b181 = [0];

const v_b182 = [0];

const v_b183 = [0];

const v_b184 = [0];

const v_b185 = [0];

const v_b186 = [0];

const v_b187 = [0];

const v_b188 = [0];

const v_b189 = [0];

const v_b190 = [0];

const v_b191 = [0];

const v_b192 = [0];

const v_b193 = [0];

const v_b194 = [0];

const v_b195 = [0];

const v_b196 = [0];

const v_b197 = [0];

const v_b198 = [0];

const v_b199 = [0];

const v_b200 = [0];

const v_b201 = [0];

const v_b202 = [0];

const v_b203 = [0];

const v_b204 = [0];

const v_b205 = [0];

const v_b206 = [0];

const v_b207 = [0];

const v_b208 = [0];

const v_b209 = [0];

const v_b210 = [0];

const v_b211 = [0];

const v_b212 = [0];

const v_b213 = [0];

const v_b214 = [0];

const v_b215 = [0];

const v_b216 = [0];

const v_b217 = [0];

const v_b218 = [0];

const v_b219 = [0];

const v_b220 = [0];

const v_b221 = [0];

const v_b222 = [0];

const v_b223 = [0];

const v_b224 = [0];

const v_b225 = [0];

const v_b226 = [0];

const v_b227 = [0];

const v_b228 = [0];

const v_b229 = [0];

const v_b230 = [0];

const v_b231 = [0];

const v_b232 = [0];

const v_b233 = [0];

const v_b234 = [0];

const v_b235 = [0];

const v_b236 = [0];

const v_b237 = [0];

const v_b238 = [0];

const v_b239 = [0];

const v_b240 = [0];

const v_b241 = [0];

const v_b242 = [0];

const v_b243 = [0];

const v_b244 = [0];

const v_b245 = [0];

const v_b246 = [0];

const v_b247 = [0];

const v_b248 = [0];

const v_b249 = [0];

const v_b250 = [0];

const v_b251 = [0];

const v_b252 = [0];

const v_b253 = [0];

const v_b254 = [0];

const v_b255 = [0];

const v_b256 = [0];

const v_b257 = [0];

const v_b258 = [0];

const v_b259 = [0];

const v_b260 = [0];

const v_b261 = [0];

const v_b262 = [0];

const v_b263 = [0];

const v_b264 = [0];

const v_b265 = [0];

const v_b266 = [0];

const v_b267 = [0];

const v_b268 = [0];

const v_b269 = [0];

const v_b270 = [0];

const v_b271 = [0];

const v_b272 = [0];

const v_b273 = [0];

const v_b274 = [0];

const v_b275 = [0];

const v_b276 = [0];

const v_b277 = [0];

const v_b278 = [0];

const v_b279 = [0];

const v_b280 = [0];

const v_b281 = [0];

const v_b282 = [0];

const v_b283 = [0];

const v_b284 = [0];

const v_b285 = [0];

const v_b286 = [0];

const v_b287 = [0];

const v_b288 = [0];

const v_b289 = [0];

const v_b290 = [0];

const v_b291 = [0];

const v_b292 = [0];

const v_b293 = [0];

const v_b294 = [0];

const v_b295 = [0];

const v_b296 = [0];

const v_b297 = [0];

const v_b298 = [0];

const v_b299 = [0];

const v_b300 = [0];

function v_showBool(v_b){
    {
      const __s = v_b;
      switch (__s[0]) {
        case 0: {
          return "True";
        }
        case 1: {
          return "False";
        }
      }
    }
}

const v_res = (v_and)(v_b1, (v_and)(v_b2, (v_and)(v_b3, (v_and)(v_b4, (v_and)(v_b5, (v_and)(v_b6, (v_and)(v_b7, (v_and)(v_b8, (v_and)(v_b9, (v_and)(v_b10, (v_and)(v_b11, (v_and)(v_b12, (v_and)(v_b13, (v_and)(v_b14, (v_and)(v_b15, (v_and)(v_b16, (v_and)(v_b17, (v_and)(v_b18, (v_and)(v_b19, (v_and)(v_b20, (v_and)(v_b21, (v_and)(v_b22, (v_and)(v_b23, (v_and)(v_b24, (v_and)(v_b25, (v_and)(v_b26, (v_and)(v_b27, (v_and)(v_b28, (v_and)(v_b29, (v_and)(v_b30, (v_and)(v_b31, (v_and)(v_b32, (v_and)(v_b33, (v_and)(v_b34, (v_and)(v_b35, (v_and)(v_b36, (v_and)(v_b37, (v_and)(v_b38, (v_and)(v_b39, (v_and)(v_b40, (v_and)(v_b41, (v_and)(v_b42, (v_and)(v_b43, (v_and)(v_b44, (v_and)(v_b45, (v_and)(v_b46, (v_and)(v_b47, (v_and)(v_b48, (v_and)(v_b49, (v_and)(v_b50, (v_and)(v_b51, (v_and)(v_b52, (v_and)(v_b53, (v_and)(v_b54, (v_and)(v_b55, (v_and)(v_b56, (v_and)(v_b57, (v_and)(v_b58, (v_and)(v_b59, (v_and)(v_b60, (v_and)(v_b61, (v_and)(v_b62, (v_and)(v_b63, (v_and)(v_b64, (v_and)(v_b65, (v_and)(v_b66, (v_and)(v_b67, (v_and)(v_b68, (v_and)(v_b69, (v_and)(v_b70, (v_and)(v_b71, (v_and)(v_b72, (v_and)(v_b73, (v_and)(v_b74, (v_and)(v_b75, (v_and)(v_b76, (v_and)(v_b77, (v_and)(v_b78, (v_and)(v_b79, (v_and)(v_b80, (v_and)(v_b81, (v_and)(v_b82, (v_and)(v_b83, (v_and)(v_b84, (v_and)(v_b85, (v_and)(v_b86, (v_and)(v_b87, (v_and)(v_b88, (v_and)(v_b89, (v_and)(v_b90, (v_and)(v_b91, (v_and)(v_b92, (v_and)(v_b93, (v_and)(v_b94, (v_and)(v_b95, (v_and)(v_b96, (v_and)(v_b97, (v_and)(v_b98, (v_and)(v_b99, (v_and)(v_b100, (v_and)(v_b101, (v_and)(v_b102, (v_and)(v_b103, (v_and)(v_b104, (v_and)(v_b105, (v_and)(v_b106, (v_and)(v_b107, (v_and)(v_b108, (v_and)(v_b109, (v_and)(v_b110, (v_and)(v_b111, (v_and)(v_b112, (v_and)(v_b113, (v_and)(v_b114, (v_and)(v_b115, (v_and)(v_b116, (v_and)(v_b117, (v_and)(v_b118, (v_and)(v_b119, (v_and)(v_b120, (v_and)(v_b121, (v_and)(v_b122, (v_and)(v_b123, (v_and)(v_b124, (v_and)(v_b125, (v_and)(v_b126, (v_and)(v_b127, (v_and)(v_b128, (v_and)(v_b129, (v_and)(v_b130, (v_and)(v_b131, (v_and)(v_b132, (v_and)(v_b133, (v_and)(v_b134, (v_and)(v_b135, (v_and)(v_b136, (v_and)(v_b137, (v_and)(v_b138, (v_and)(v_b139, (v_and)(v_b140, (v_and)(v_b141, (v_and)(v_b142, (v_and)(v_b143, (v_and)(v_b144, (v_and)(v_b145, (v_and)(v_b146, (v_and)(v_b147, (v_and)(v_b148, (v_and)(v_b149, (v_and)(v_b150, (v_and)(v_b151, (v_and)(v_b152, (v_and)(v_b153, (v_and)(v_b154, (v_and)(v_b155, (v_and)(v_b156, (v_and)(v_b157, (v_and)(v_b158, (v_and)(v_b159, (v_and)(v_b160, (v_and)(v_b161, (v_and)(v_b162, (v_and)(v_b163, (v_and)(v_b164, (v_and)(v_b165, (v_and)(v_b166, (v_and)(v_b167, (v_and)(v_b168, (v_and)(v_b169, (v_and)(v_b170, (v_and)(v_b171, (v_and)(v_b172, (v_and)(v_b173, (v_and)(v_b174, (v_and)(v_b175, (v_and)(v_b176, (v_and)(v_b177, (v_and)(v_b178, (v_and)(v_b179, (v_and)(v_b180, (v_and)(v_b181, (v_and)(v_b182, (v_and)(v_b183, (v_and)(v_b184, (v_and)(v_b185, (v_and)(v_b186, (v_and)(v_b187, (v_and)(v_b188, (v_and)(v_b189, (v_and)(v_b190, (v_and)(v_b191, (v_and)(v_b192, (v_and)(v_b193, (v_and)(v_b194, (v_and)(v_b195, (v_and)(v_b196, (v_and)(v_b197, (v_and)(v_b198, (v_and)(v_b199, (v_and)(v_b200, (v_and)(v_b201, (v_and)(v_b202, (v_and)(v_b203, (v_and)(v_b204, (v_and)(v_b205, (v_and)(v_b206, (v_and)(v_b207, (v_and)(v_b208, (v_and)(v_b209, (v_and)(v_b210, (v_and)(v_b211, (v_and)(v_b212, (v_and)(v_b213, (v_and)(v_b214, (v_and)(v_b215, (v_and)(v_b216, (v_and)(v_b217, (v_and)(v_b218, (v_and)(v_b219, (v_and)(v_b220, (v_and)(v_b221, (v_and)(v_b222, (v_and)(v_b223, (v_and)(v_b224, (v_and)(v_b225, (v_and)(v_b226, (v_and)(v_b227, (v_and)(v_b228, (v_and)(v_b229, (v_and)(v_b230, (v_and)(v_b231, (v_and)(v_b232, (v_and)(v_b233, (v_and)(v_b234, (v_and)(v_b235, (v_and)(v_b236, (v_and)(v_b237, (v_and)(v_b238, (v_and)(v_b239, (v_and)(v_b240, (v_and)(v_b241, (v_and)(v_b242, (v_and)(v_b243, (v_and)(v_b244, (v_and)(v_b245, (v_and)(v_b246, (v_and)(v_b247, (v_and)(v_b248, (v_and)(v_b249, (v_and)(v_b250, (v_and)(v_b251, (v_and)(v_b252, (v_and)(v_b253, (v_and)(v_b254, (v_and)(v_b255, (v_and)(v_b256, (v_and)(v_b257, (v_and)(v_b258, (v_and)(v_b259, (v_and)(v_b260, (v_and)(v_b261, (v_and)(v_b262, (v_and)(v_b263, (v_and)(v_b264, (v_and)(v_b265, (v_and)(v_b266, (v_and)(v_b267, (v_and)(v_b268, (v_and)(v_b269, (v_and)(v_b270, (v_and)(v_b271, (v_and)(v_b272, (v_and)(v_b273, (v_and)(v_b274, (v_and)(v_b275, (v_and)(v_b276, (v_and)(v_b277, (v_and)(v_b278, (v_and)(v_b279, (v_and)(v_b280, (v_and)(v_b281, (v_and)(v_b282, (v_and)(v_b283, (v_and)(v_b284, (v_and)(v_b285, (v_and)(v_b286, (v_and)(v_b287, (v_and)(v_b288, (v_and)(v_b289, (v_and)(v_b290, (v_and)(v_b291, (v_and)(v_b292, (v_and)(v_b293, (v_and)(v_b294, (v_and)(v_b295, (v_and)(v_b296, (v_and)(v_b297, (v_and)(v_b298, (v_and)(v_b299, v_b300)))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))));

function main(v__input){
    return [2, (v_showBool)(v_res), [0, [0]]];
}

if (typeof require !== 'undefined' && require.main === module) {
  const arg = process.argv[2] ?? "";
  if (typeof main === 'function') v_runIO(main(__entryArgEither(arg)));
}

})();