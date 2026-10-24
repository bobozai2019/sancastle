Shader hash 90601971-3dc75d07-8a6d66b6-d166f3b6

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[142], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_sampler s1, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_texture2d (float,float,float,float) t1
      dcl_resource_structured t2, 16
      dcl_input_ps_siv linear noperspective v0.xy, position
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v3.xy
      dcl_output o0.xyzw
      dcl_temps 3
   0: itof r0.xy, cb0[141].xyxx
   1: mad r0.xy, v3.xyxx, r0.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
   2: round_ni r0.zw, r0.xxxy
   3: frc r0.xy, r0.xyxx
   4: ftoi r0.zw, r0.zzzw
   5: iadd r1.xy, r0.zwzz, l(1, 1, 0, 0)
   6: imax r1.xy, r1.xyxx, l(0, 0, 0, 0)
   7: iadd r1.zw, cb0[141].xxxy, l(0, 0, -1, -1)
   8: imin r1.xy, r1.zwzz, r1.xyxx
   9: imad r1.x, r1.y, cb0[141].x, r1.x
  10: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xy, r1.x, l(8), t2.xyxx
  11: ushr r2.x, r1.x, l(24)
  12: bfi r1.y, l(24), l(8), r1.y, r2.x
  13: and r1.xy, r1.xyxx, l(0.000000, 0.000000, 0.000000, 0.000000)
  14: utof r1.xy, r1.xyxx
  15: iadd r2.xyzw, r0.zwzw, l(1, 0, 0, 1)
  16: imax r0.zw, r0.zzzw, l(0, 0, 0, 0)
  17: imin r0.zw, r1.zzzw, r0.zzzw
  18: imad r0.z, r0.w, cb0[141].x, r0.z
  19: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.zw, r0.z, l(8), t2.xxxy
  20: imax r2.xyzw, r2.xyzw, l(0, 0, 0, 0)
  21: imin r2.xyzw, r1.zwzw, r2.xyzw
  22: imad r1.zw, r2.yyyw, cb0[141].xxxx, r2.xxxz
  23: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xy, r1.w, l(8), t2.xyxx
  24: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.zw, r1.z, l(8), t2.xxxy
  25: ushr r2.z, r2.x, l(24)
  26: bfi r2.y, l(24), l(8), r2.y, r2.z
  27: and r2.xy, r2.xyxx, l(0.000000, 0.000000, 0.000000, 0.000000)
  28: utof r2.xy, r2.xyxx
  29: mul r2.xy, r2.xyxx, l(0.000001, 0.000001, 0.000000, 0.000000)
  30: mad r1.y, r1.y, l(0.000001), -r2.y
  31: mad r1.y, r0.x, r1.y, r2.y
  32: ushr r2.y, r1.z, l(24)
  33: bfi r1.w, l(24), l(8), r1.w, r2.y
  34: and r1.zw, r1.zzzw, l(0.000000, 0.000000, 0.000000, 0.000000)
  35: utof r1.zw, r1.zzzw
  36: ushr r2.y, r0.z, l(24)
  37: bfi r0.w, l(24), l(8), r0.w, r2.y
  38: and r0.zw, r0.zzzw, l(0.000000, 0.000000, 0.000000, 0.000000)
  39: utof r0.zw, r0.zzzw
  40: mul r0.zw, r0.zzzw, l(0.000000, 0.000000, 0.000001, 0.000001)
  41: mad r1.w, r1.w, l(0.000001), -r0.w
  42: mad r0.w, r0.x, r1.w, r0.w
  43: add r1.y, -r0.w, r1.y
  44: mad r0.w, r0.y, r1.y, r0.w
  45: mad r1.x, r1.x, l(0.000001), -r2.x
  46: mad r1.x, r0.x, r1.x, r2.x
  47: mad r1.y, r1.z, l(0.000001), -r0.z
  48: mad r0.x, r0.x, r1.y, r0.z
  49: add r0.z, -r0.x, r1.x
  50: mad r0.x, r0.y, r0.z, r0.x
  51: add r0.x, r0.x, l(-0.050000)
  52: max r0.x, r0.x, l(0)
  53: add r0.x, r0.x, r0.w
  54: lt r0.y, v1.y, r0.w
  55: lt r0.x, r0.x, v1.y
  56: or r0.x, r0.y, r0.x
  57: discard_nz r0.x
  58: rcp r0.xy, cb0[5].xyxx
  59: mul r0.xy, r0.xyxx, v0.xyxx
  60: mad r0.y, r0.y, cb0[12].x, cb0[12].y
  61: add r0.z, -r0.y, l(1.000000)
  62: mad r0.yw, r0.xxxz, l(0.000000, 2.000000, 0.000000, 2.000000), l(0.000000, -1.000000, 0.000000, -1.000000)
  63: mul r1.xyzw, -r0.wwww, cb0[67].xyzw
  64: mad r1.xyzw, cb0[66].xyzw, r0.yyyy, r1.xyzw
  65: sample_indexable(texture2d)(float,float,float,float) r0.y, r0.xzxx, t1.yxzw, s1
  66: sample_indexable(texture2d)(float,float,float,float) r0.xzw, r0.xzxx, t0.xwyz, s0
  67: mad r1.xyzw, cb0[68].xyzw, r0.yyyy, r1.xyzw
  68: add r1.xyzw, r1.xyzw, cb0[69].xyzw
  69: div r1.xyz, r1.xyzx, r1.wwww
  70: add r1.xyz, r1.xyzx, -v1.xyzx
  71: dp3 r0.y, r1.xyzx, r1.xyzx
  72: sqrt r0.y, r0.y
  73: mul r1.xyz, -r0.yyyy, cb0[132].xyzx
  74: mul r1.xyz, r1.xyzx, l(8.656170, 8.656170, 8.656170, 0.000000)
  75: exp r1.xyz, r1.xyzx
  76: mul r1.xyz, r1.xyzx, cb0[131].xyzx
  77: mul o0.xyz, r0.xzwx, r1.xyzx
  78: mov o0.w, l(1.000000)
  79: ret
