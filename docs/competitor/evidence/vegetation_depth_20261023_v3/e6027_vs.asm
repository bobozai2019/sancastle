Shader hash 7648c294-ef55b11d-fc240d00-be9c3247

vs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[142], immediateIndexed
      dcl_constantbuffer cb1[4], immediateIndexed
      dcl_resource_structured t0, 16
      dcl_resource_structured t1, 16
      dcl_input v0.xyz
      dcl_output_siv o0.xyzw, position
      dcl_output o1.xyz
      dcl_output o2.xyzw
      dcl_output o3.xyzw
      dcl_output o4.xyzw
      dcl_temps 5
   0: itof r0.xyzw, cb0[141].xyxy
   1: mul r1.xy, v0.yyyy, cb1[1].xzxx
   2: mad r1.xy, cb1[0].xzxx, v0.xxxx, r1.xyxx
   3: mad r1.xy, cb1[2].xzxx, v0.zzzz, r1.xyxx
   4: add r1.xz, r1.xxyx, cb1[3].xxzx
   5: div r2.xy, r1.xzxx, cb0[116].xzxx
   6: add_sat r2.xy, r2.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
   7: mad r0.xyzw, r2.xyxy, r0.xyzw, l(-0.500000, -0.500000, -0.500000, -0.500000)
   8: max r0.xyzw, r0.xyzw, l(0, 0, 0, 0)
   9: iadd r3.xyzw, cb0[141].xyxy, l(-1, -1, -1, -1)
  10: itof r4.xyzw, r3.zwzw
  11: min r0.xyzw, r0.xyzw, r4.xyzw
  12: ftoi r0.xyzw, r0.xyzw
  13: iadd r4.xyzw, r0.zwzw, l(-1, 0, 1, 0)
  14: imax r4.xyzw, r4.xyzw, l(0, 0, 0, 0)
  15: imin r4.xyzw, r3.xyzw, r4.xyzw
  16: imad r2.zw, r4.yyyw, cb0[141].xxxx, r4.xxxz
  17: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r4.xy, r2.z, l(8), t1.xyxx
  18: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.zw, r2.w, l(8), t1.xxxy
  19: ushr r1.w, r4.x, l(24)
  20: bfi r1.w, l(24), l(8), r4.y, r1.w
  21: and r4.x, r4.x, l(0.000000)
  22: utof r4.x, r4.x
  23: mad r4.x, r4.x, l(0.000001), l(-0.050000)
  24: max r4.x, r4.x, l(0)
  25: and r1.w, r1.w, l(0.000000)
  26: utof r1.w, r1.w
  27: mad r1.w, r1.w, l(0.000001), r4.x
  28: ushr r4.x, r2.z, l(24)
  29: bfi r2.w, l(24), l(8), r2.w, r4.x
  30: and r2.zw, r2.zzzw, l(0.000000, 0.000000, 0.000000, 0.000000)
  31: utof r2.zw, r2.zzzw
  32: mad r2.z, r2.z, l(0.000001), l(-0.050000)
  33: max r2.z, r2.z, l(0)
  34: mad r2.z, r2.w, l(0.000001), r2.z
  35: add r1.w, r1.w, r2.z
  36: iadd r4.xyzw, r0.xyzw, l(0, -1, 0, 1)
  37: imad r0.x, r0.w, cb0[141].x, r0.z
  38: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.xyzw, r0.x, l(0), t1.xyzw
  39: imax r4.xyzw, r4.xyzw, l(0, 0, 0, 0)
  40: imin r3.xyzw, r3.xyzw, r4.xyzw
  41: imad r2.zw, r3.yyyw, cb0[141].xxxx, r3.xxxz
  42: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xy, r2.z, l(8), t1.xyxx
  43: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.zw, r2.w, l(8), t1.xxxy
  44: ushr r3.z, r3.x, l(24)
  45: bfi r3.y, l(24), l(8), r3.y, r3.z
  46: and r3.xy, r3.xyxx, l(0.000000, 0.000000, 0.000000, 0.000000)
  47: utof r3.xy, r3.xyxx
  48: mad r3.x, r3.x, l(0.000001), l(-0.050000)
  49: max r3.x, r3.x, l(0)
  50: mad r3.x, r3.y, l(0.000001), r3.x
  51: add r1.w, r1.w, r3.x
  52: ushr r3.x, r2.z, l(24)
  53: bfi r2.w, l(24), l(8), r2.w, r3.x
  54: and r2.zw, r2.zzzw, l(0.000000, 0.000000, 0.000000, 0.000000)
  55: utof r2.zw, r2.zzzw
  56: mad r2.z, r2.z, l(0.000001), l(-0.050000)
  57: max r2.z, r2.z, l(0)
  58: mad r2.z, r2.w, l(0.000001), r2.z
  59: add r1.w, r1.w, r2.z
  60: mul r1.y, r1.w, l(0.250000)
  61: mul r3.xyzw, r1.yyyy, cb0[63].xyzw
  62: mov o1.xyz, r1.xyzx
  63: mad r3.xyzw, cb0[62].xyzw, r1.xxxx, r3.xyzw
  64: mad r1.xyzw, cb0[64].xyzw, r1.zzzz, r3.xyzw
  65: add o0.xyzw, r1.xyzw, cb0[65].xyzw
  66: ubfe r1.xy, l(8, 8, 0, 0), l(8, 16, 0, 0), r0.xwxx
  67: utof r1.xy, r1.xyxx
  68: mad r3.z, r1.x, l(0.007843), l(-1.000000)
  69: mul o2.w, r1.y, l(0.003922)
  70: and r0.zw, r0.xxxz, l(0.000000, 0.000000, 0.000000, 0.000000)
  71: utof r0.zw, r0.zzzw
  72: mad r3.xy, r0.zwzz, l(0.007843, 0.000001, 0.000000, 0.000000), l(-1.000000, -0.050000, 0.000000, 0.000000)
  73: mul r0.z, r0.w, l(0.000001)
  74: mov o4.z, r0.z
  75: dp2 r0.z, r3.xzxx, r3.xzxx
  76: mul r1.xyz, r3.zzzz, l(0.000000, 0.000000, 1.000000, 0.000000)
  77: mad r1.xyz, r3.xxxx, l(1.000000, 0.000000, 0.000000, 0.000000), r1.xyzx
  78: max o4.w, r3.y, l(0)
  79: add r0.z, -r0.z, l(1.000000)
  80: sqrt r0.z, r0.z
  81: mad o2.xyz, r0.zzzz, l(0.000000, 1.000000, 0.000000, 0.000000), r1.xyzx
  82: itof r0.zw, cb0[139].xxxy
  83: mad r0.zw, r2.xxxy, r0.zzzw, l(0.000000, 0.000000, -0.500000, -0.500000)
  84: max r0.zw, r0.zzzw, l(0, 0, 0, 0)
  85: iadd r1.xy, cb0[139].xyxx, l(-1, -1, 0, 0)
  86: itof r1.xy, r1.xyxx
  87: min r0.zw, r0.zzzw, r1.xxxy
  88: ftoi r0.zw, r0.zzzw
  89: imad r0.z, r0.w, cb0[139].x, r0.z
  90: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xyzw, r0.z, l(0), t0.xyzw
  91: ushr r2.xyz, r1.xyzx, l(16, 8, 12, 0)
  92: bfi r0.zw, l(0, 0, 16, 12), l(0, 0, 16, 20), r1.yyyw, r2.xxxz
  93: utof r1.x, r2.y
  94: mad o3.y, r1.x, l(0.000000), l(-4.000000)
  95: and r0.zw, r0.zzzw, l(0.000000, 0.000000, 0.000000, 0.000000)
  96: utof r0.zw, r0.zzzw
  97: mad o3.xz, r0.zzwz, l(0.000000, 0.000000, 0.000001, 0.000000), l(-4.000000, 0.000000, 0.000000, 0.000000)
  98: mov o3.w, l(0)
  99: ushr r0.xz, r0.xxyx, l(16, 0, 8, 0)
 100: bfi r0.x, l(16), l(16), r0.y, r0.x
 101: utof r0.y, r0.z
 102: mad o4.y, r0.y, l(0.000000), l(-4.000000)
 103: and r0.x, r0.x, l(0.000000)
 104: utof r0.x, r0.x
 105: mad o4.x, r0.x, l(0.000000), l(-4.000000)
 106: ret
