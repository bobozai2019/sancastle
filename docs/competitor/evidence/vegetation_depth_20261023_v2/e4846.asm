Shader hash 00a7f9ea-c0381dd0-525ee116-07a05a3c

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[140], immediateIndexed
      dcl_resource_structured t0, 16
      dcl_input_ps linear v1.y
      dcl_input_ps linear v2.xy
      dcl_output o0.xyzw
      dcl_temps 3
   0: itof r0.xy, cb0[139].xyxx
   1: mad r0.xy, v2.xyxx, r0.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
   2: round_ni r0.zw, r0.xxxy
   3: frc r0.xy, r0.xyxx
   4: ftoi r0.zw, r0.zzzw
   5: iadd r1.xy, r0.zwzz, l(1, 1, 0, 0)
   6: imax r1.xy, r1.xyxx, l(0, 0, 0, 0)
   7: iadd r1.zw, cb0[139].xxxy, l(0, 0, -1, -1)
   8: imin r1.xy, r1.zwzz, r1.xyxx
   9: imad r1.x, r1.y, cb0[139].x, r1.x
  10: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xy, r1.x, l(8), t0.xyxx
  11: ushr r2.x, r1.x, l(12)
  12: bfi r1.y, l(12), l(20), r1.y, r2.x
  13: and r1.xy, r1.xyxx, l(0.000000, 0.000000, 0.000000, 0.000000)
  14: utof r1.xy, r1.xyxx
  15: iadd r2.xyzw, r0.zwzw, l(1, 0, 0, 1)
  16: imax r0.zw, r0.zzzw, l(0, 0, 0, 0)
  17: imin r0.zw, r1.zzzw, r0.zzzw
  18: imad r0.z, r0.w, cb0[139].x, r0.z
  19: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.zw, r0.z, l(8), t0.xxxy
  20: imax r2.xyzw, r2.xyzw, l(0, 0, 0, 0)
  21: imin r2.xyzw, r1.zwzw, r2.xyzw
  22: imad r1.zw, r2.yyyw, cb0[139].xxxx, r2.xxxz
  23: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xy, r1.w, l(8), t0.xyxx
  24: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.zw, r1.z, l(8), t0.xxxy
  25: ushr r2.z, r2.x, l(12)
  26: bfi r2.y, l(12), l(20), r2.y, r2.z
  27: and r2.xy, r2.xyxx, l(0.000000, 0.000000, 0.000000, 0.000000)
  28: utof r2.xy, r2.xyxx
  29: mul r2.xy, r2.xyxx, l(0.002466, 0.000001, 0.000000, 0.000000)
  30: mad r1.y, r1.y, l(0.000001), -r2.y
  31: mad r1.y, r0.x, r1.y, r2.y
  32: ushr r2.y, r1.z, l(12)
  33: bfi r1.w, l(12), l(20), r1.w, r2.y
  34: and r1.zw, r1.zzzw, l(0.000000, 0.000000, 0.000000, 0.000000)
  35: utof r1.zw, r1.zzzw
  36: ushr r2.y, r0.z, l(12)
  37: bfi r0.w, l(12), l(20), r0.w, r2.y
  38: and r0.zw, r0.zzzw, l(0.000000, 0.000000, 0.000000, 0.000000)
  39: utof r0.zw, r0.zzzw
  40: mul r0.zw, r0.zzzw, l(0.000000, 0.000000, 0.002466, 0.000001)
  41: mad r1.w, r1.w, l(0.000001), -r0.w
  42: mad r0.w, r0.x, r1.w, r0.w
  43: add r1.y, -r0.w, r1.y
  44: mad r0.w, r0.y, r1.y, r0.w
  45: mad r1.x, r1.x, l(0.002466), -r2.x
  46: mad r1.x, r0.x, r1.x, r2.x
  47: mad r1.y, r1.z, l(0.002466), -r0.z
  48: mad r0.x, r0.x, r1.y, r0.z
  49: add r0.z, -r0.x, r1.x
  50: mad r0.x, r0.y, r0.z, r0.x
  51: max r0.x, r0.x, r0.w
  52: lt r0.x, r0.x, v1.y
  53: discard_nz r0.x
  54: mov o0.xyzw, l(0, 0, 0, 0)
  55: ret
