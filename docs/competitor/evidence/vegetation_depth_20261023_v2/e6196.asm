Shader hash f0a655e7-c6ff4d6c-1b1ff0aa-b2d05bf1

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[140], immediateIndexed
      dcl_sampler s0, mode_comparison
      dcl_sampler s1, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_structured t1, 16
      dcl_resource_texture2d (float,float,float,float) t2
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v2.xyz
      dcl_output o0.xyzw
      dcl_temps 4
   0: mul r0.xyzw, cb0[116].xzxz, l(0.500000, 0.500000, -0.500000, -0.500000)
   1: lt r1.xy, r0.xyxx, abs(v1.xzxx)
   2: discard_nz r1.x
   3: discard_nz r1.y
   4: lt r1.x, v1.y, l(0)
   5: discard_nz r1.x
   6: add r1.xy, v2.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
   7: dp2 r1.x, r1.xyxx, r1.xyxx
   8: sqrt r1.x, r1.x
   9: add r1.x, -r1.x, l(0.500000)
  10: lt r1.y, r1.x, l(0)
  11: max r1.x, r1.x, l(0)
  12: mul o0.w, r1.x, v2.z
  13: discard_nz r1.y
  14: lt r0.xy, v1.xzxx, r0.xyxx
  15: lt r0.zw, r0.zzzw, v1.xxxz
  16: and r0.x, r0.z, r0.x
  17: and r0.x, r0.y, r0.x
  18: and r0.x, r0.w, r0.x
  19: and r0.x, r0.x, l(1.000000)
  20: div r0.yz, v1.xxzx, cb0[116].xxzx
  21: add_sat r0.yz, r0.yyzy, l(0.000000, 0.500000, 0.500000, 0.000000)
  22: sample_l(texture2d)(float,float,float,float) r1.xyz, r0.yzyy, t2.xyzw, s1, l(0)
  23: add r1.xyz, r1.xyzx, -cb0[40].xyzx
  24: mad r1.xyz, r0.xxxx, r1.xyzx, cb0[40].xyzx
  25: mul r1.xyz, r1.xyzx, l(0.950000, 0.950000, 0.950000, 0.000000)
  26: itof r0.xw, cb0[139].xxxy
  27: mad r0.xy, r0.yzyy, r0.xwxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
  28: round_ni r0.zw, r0.xxxy
  29: frc r0.xy, r0.xyxx
  30: ftoi r0.zw, r0.zzzw
  31: iadd r2.xy, r0.zwzz, l(1, 1, 0, 0)
  32: imax r2.xy, r2.xyxx, l(0, 0, 0, 0)
  33: iadd r2.zw, cb0[139].xxxy, l(0, 0, -1, -1)
  34: imin r2.xy, r2.zwzz, r2.xyxx
  35: imad r1.w, r2.y, cb0[139].x, r2.x
  36: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xy, r1.w, l(4), t1.xyxx
  37: ushr r1.w, r2.x, l(12)
  38: bfi r1.w, l(12), l(20), r2.y, r1.w
  39: and r1.w, r1.w, l(0x003fffff)
  40: utof r1.w, r1.w
  41: iadd r3.xyzw, r0.zwzw, l(1, 0, 0, 1)
  42: imax r0.zw, r0.zzzw, l(0, 0, 0, 0)
  43: imin r0.zw, r2.zzzw, r0.zzzw
  44: imad r0.z, r0.w, cb0[139].x, r0.z
  45: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.zw, r0.z, l(4), t1.xxxy
  46: imax r3.xyzw, r3.xyzw, l(0, 0, 0, 0)
  47: imin r2.xyzw, r2.zwzw, r3.xyzw
  48: imad r2.xy, r2.ywyy, cb0[139].xxxx, r2.xzxx
  49: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.yz, r2.y, l(4), t1.xxyx
  50: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xw, r2.x, l(4), t1.xxxy
  51: ushr r2.xy, r2.xyxx, l(12, 12, 0, 0)
  52: bfi r2.xy, l(12, 12, 0, 0), l(20, 20, 0, 0), r2.wzww, r2.xyxx
  53: and r2.xy, r2.xyxx, l(0x003fffff, 0x003fffff, 0, 0)
  54: utof r2.xy, r2.xyxx
  55: mul r2.y, r2.y, l(0.000001)
  56: mad r1.w, r1.w, l(0.000001), -r2.y
  57: mad r1.w, r0.x, r1.w, r2.y
  58: ushr r0.z, r0.z, l(12)
  59: bfi r0.z, l(12), l(20), r0.w, r0.z
  60: and r0.z, r0.z, l(0x003fffff)
  61: utof r0.z, r0.z
  62: mul r0.z, r0.z, l(0.000001)
  63: mad r0.w, r2.x, l(0.000001), -r0.z
  64: mad r0.x, r0.x, r0.w, r0.z
  65: add r0.z, -r0.x, r1.w
  66: mad r0.x, r0.y, r0.z, r0.x
  67: mul r0.x, r0.x, l(-0.721348)
  68: exp r0.x, r0.x
  69: mul r0.yzw, v1.yyyy, cb0[135].xxyz
  70: mad r0.yzw, cb0[134].xxyz, v1.xxxx, r0.yyzw
  71: mad r0.yzw, cb0[136].xxyz, v1.zzzz, r0.yyzw
  72: add r0.yzw, r0.yyzw, cb0[137].xxyz
  73: ge r1.w, l(0), r0.w
  74: ge r2.x, r0.w, l(1.000000)
  75: sample_c_lz(texture2d)(float,float,float,float) r0.y, r0.yzyy, t0.xxxx, s0, r0.w
  76: or r0.z, r1.w, r2.x
  77: movc r0.y, r0.z, l(1.000000), r0.y
  78: mul r0.x, r0.x, r0.y
  79: max r0.y, -cb0[123].y, l(0)
  80: mul r0.yzw, r0.yyyy, cb0[125].xxyz
  81: max r1.w, -cb0[124].y, l(0)
  82: mul r2.xyz, r1.wwww, cb0[126].xyzx
  83: mad r0.xyz, r0.yzwy, r0.xxxx, r2.xyzx
  84: mad o0.xyz, r0.xyzx, l(0.950000, 0.950000, 0.950000, 0.000000), r1.xyzx
  85: ret
