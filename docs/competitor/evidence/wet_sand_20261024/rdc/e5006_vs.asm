Shader hash 7f3d41e8-293c5a93-292e56b1-50f1fe73

vs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[142], immediateIndexed
      dcl_constantbuffer cb1[4], immediateIndexed
      dcl_resource_structured t0, 16
      dcl_resource_structured t1, 16
      dcl_input v0.xyz
      dcl_output_siv o0.xyzw, position
      dcl_output o1.xyz
      dcl_output o2.xyz
      dcl_output o3.xyzw
      dcl_output o4.xyzw
      dcl_output o5.xyzw
      dcl_temps 8
   0: iadd r0.xy, cb0[139].xyxx, l(-1, -1, 0, 0)
   1: itof r0.xy, r0.xyxx
   2: itof r0.zw, cb0[139].xxxy
   3: mul r1.xy, v0.yyyy, cb1[1].xzxx
   4: mad r1.xy, cb1[0].xzxx, v0.xxxx, r1.xyxx
   5: mad r1.xy, cb1[2].xzxx, v0.zzzz, r1.xyxx
   6: add r1.xy, r1.xyxx, cb1[3].xzxx
   7: div r1.zw, r1.xxxy, cb0[116].xxxz
   8: add_sat r1.zw, r1.zzzw, l(0.000000, 0.000000, 0.500000, 0.500000)
   9: mad r0.zw, r1.zzzw, r0.zzzw, l(0.000000, 0.000000, -0.500000, -0.500000)
  10: max r0.zw, r0.zzzw, l(0, 0, 0, 0)
  11: min r0.xy, r0.xyxx, r0.zwzz
  12: ftoi r0.xy, r0.xyxx
  13: imad r0.x, r0.y, cb0[139].x, r0.x
  14: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.xyzw, r0.x, l(0), t0.xyzw
  15: ushr r2.xyzw, r0.xyzw, l(16, 8, 12, 26)
  16: bfi r2.xz, l(16, 0, 12, 0), l(16, 0, 20, 0), r0.yywy, r2.xxzx
  17: and r2.xz, r2.xxzx, l(0.000000, 0.000000, 0.000000, 0.000000)
  18: utof r2.xyzw, r2.xyzw
  19: mul r0.y, r2.z, l(0.000001)
  20: mad r2.xz, r2.xxzx, l(0.000000, 0.000000, 0.000001, 0.000000), l(-4.000000, 0.000000, 0.000000, 0.000000)
  21: mul r3.xyzw, r0.yyyy, cb0[63].xyzw
  22: mad r3.xyzw, cb0[62].xyzw, r1.xxxx, r3.xyzw
  23: mad r3.xyzw, cb0[64].xyzw, r1.yyyy, r3.xyzw
  24: mov o1.xz, r1.xxyx
  25: add o0.xyzw, r3.xyzw, cb0[65].xyzw
  26: mov o1.y, r2.z
  27: mov o3.xz, r2.xxzx
  28: and r0.yz, r0.xxzx, l(0, 255, 4095, 0)
  29: ubfe r0.xw, l(8, 0, 0, 22), l(8, 0, 0, 4), r0.xxxw
  30: utof r0.xyzw, r0.xyzw
  31: mad r1.x, r0.y, l(0.007843), l(-1.000000)
  32: mul r0.y, r0.z, l(0.002466)
  33: mov o3.w, r0.y
  34: mad r1.y, r0.x, l(0.007843), l(-1.000000)
  35: mul o5.w, r0.w, l(0.000001)
  36: dp2 r0.x, r1.xyxx, r1.xyxx
  37: mul r0.yzw, r1.yyyy, l(0.000000, 0.000000, 0.000000, 1.000000)
  38: mad r0.yzw, r1.xxxx, l(0.000000, 1.000000, 0.000000, 0.000000), r0.yyzw
  39: add r0.x, -r0.x, l(1.000000)
  40: sqrt r0.x, r0.x
  41: mad o2.xyz, r0.xxxx, l(0.000000, 1.000000, 0.000000, 0.000000), r0.yzwy
  42: mad o3.y, r2.y, l(0.000000), l(-4.000000)
  43: mul o5.z, r2.w, l(0.015873)
  44: itof r0.xy, cb0[141].xyxx
  45: mad r0.xy, r1.zwzz, r0.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
  46: round_ni r0.zw, r0.xxxy
  47: frc r0.xy, r0.xyxx
  48: ftoi r0.zw, r0.zzzw
  49: iadd r1.xy, r0.zwzz, l(1, 1, 0, 0)
  50: imax r1.xy, r1.xyxx, l(0, 0, 0, 0)
  51: iadd r1.zw, cb0[141].xxxy, l(0, 0, -1, -1)
  52: imin r1.xy, r1.zwzz, r1.xyxx
  53: imad r1.x, r1.y, cb0[141].x, r1.x
  54: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xyz, r1.x, l(0), t1.xyzx
  55: ubfe r1.x, l(8), l(8), r2.x
  56: utof r1.x, r1.x
  57: mad r1.y, r1.x, l(0.007843), l(-1.000000)
  58: and r2.zw, r2.xxxz, l(0.000000, 0.000000, 0.000000, 0.000000)
  59: utof r2.zw, r2.zzzw
  60: mad r1.x, r2.z, l(0.007843), l(-1.000000)
  61: iadd r3.xyzw, r0.zwzw, l(1, 0, 0, 1)
  62: imax r0.zw, r0.zzzw, l(0, 0, 0, 0)
  63: imin r0.zw, r1.zzzw, r0.zzzw
  64: imad r0.z, r0.w, cb0[141].x, r0.z
  65: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r4.xyz, r0.z, l(0), t1.xyzx
  66: imax r3.xyzw, r3.xyzw, l(0, 0, 0, 0)
  67: imin r3.xyzw, r1.zwzw, r3.xyzw
  68: imad r0.zw, r3.yyyw, cb0[141].xxxx, r3.xxxz
  69: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xyz, r0.w, l(0), t1.xyzx
  70: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r5.xyz, r0.z, l(0), t1.xyzx
  71: ubfe r0.z, l(8), l(8), r3.x
  72: utof r0.z, r0.z
  73: mad r6.y, r0.z, l(0.007843), l(-1.000000)
  74: and r0.zw, r3.xxxz, l(0.000000, 0.000000, 0.000000, 0.000000)
  75: utof r0.zw, r0.zzzw
  76: mad r6.x, r0.z, l(0.007843), l(-1.000000)
  77: mul r0.z, r0.w, l(0.000001)
  78: add r1.xy, r1.xyxx, -r6.xyxx
  79: mad r1.xy, r0.xxxx, r1.xyxx, r6.xyxx
  80: ubfe r0.w, l(8), l(8), r5.x
  81: utof r0.w, r0.w
  82: mad r6.y, r0.w, l(0.007843), l(-1.000000)
  83: and r1.zw, r5.xxxz, l(0.000000, 0.000000, 0.000000, 0.000000)
  84: utof r1.zw, r1.zzzw
  85: mad r6.x, r1.z, l(0.007843), l(-1.000000)
  86: ubfe r0.w, l(8), l(8), r4.x
  87: utof r0.w, r0.w
  88: mad r7.y, r0.w, l(0.007843), l(-1.000000)
  89: and r3.zw, r4.xxxz, l(0.000000, 0.000000, 0.000000, 0.000000)
  90: utof r3.zw, r3.zzzw
  91: mad r7.x, r3.z, l(0.007843), l(-1.000000)
  92: mul r0.w, r3.w, l(0.000001)
  93: add r3.zw, r6.xxxy, -r7.xxxy
  94: mad r3.zw, r0.xxxx, r3.zzzw, r7.xxxy
  95: add r1.xy, r1.xyxx, -r3.zwzz
  96: mad o4.xy, r0.yyyy, r1.xyxx, r3.zwzz
  97: mad r1.x, r2.w, l(0.000001), -r0.z
  98: mad r0.z, r0.x, r1.x, r0.z
  99: mad r1.x, r1.w, l(0.000001), -r0.w
 100: mad r0.w, r0.x, r1.x, r0.w
 101: add r0.z, -r0.w, r0.z
 102: mad r0.z, r0.y, r0.z, r0.w
 103: add r0.w, r0.z, l(-0.050000)
 104: mov o4.z, r0.z
 105: max o4.w, r0.w, l(0)
 106: ushr r0.zw, r2.xxxy, l(0, 0, 16, 8)
 107: bfi r0.z, l(16), l(16), r2.y, r0.z
 108: utof r0.w, r0.w
 109: mad r1.y, r0.w, l(0.000000), l(-4.000000)
 110: and r0.z, r0.z, l(0.000000)
 111: utof r0.z, r0.z
 112: mad r1.x, r0.z, l(0.000000), l(-4.000000)
 113: ushr r0.zw, r3.xxxy, l(0, 0, 16, 8)
 114: bfi r0.z, l(16), l(16), r3.y, r0.z
 115: utof r0.w, r0.w
 116: mad r2.y, r0.w, l(0.000000), l(-4.000000)
 117: and r0.z, r0.z, l(0.000000)
 118: utof r0.z, r0.z
 119: mad r2.x, r0.z, l(0.000000), l(-4.000000)
 120: add r0.zw, r1.xxxy, -r2.xxxy
 121: mad r0.zw, r0.xxxx, r0.zzzw, r2.xxxy
 122: ushr r1.xy, r5.xyxx, l(16, 8, 0, 0)
 123: bfi r1.x, l(16), l(16), r5.y, r1.x
 124: utof r1.y, r1.y
 125: mad r2.y, r1.y, l(0.000000), l(-4.000000)
 126: and r1.x, r1.x, l(0.000000)
 127: utof r1.x, r1.x
 128: mad r2.x, r1.x, l(0.000000), l(-4.000000)
 129: ushr r1.xy, r4.xyxx, l(16, 8, 0, 0)
 130: bfi r1.x, l(16), l(16), r4.y, r1.x
 131: utof r1.y, r1.y
 132: mad r3.y, r1.y, l(0.000000), l(-4.000000)
 133: and r1.x, r1.x, l(0.000000)
 134: utof r1.x, r1.x
 135: mad r3.x, r1.x, l(0.000000), l(-4.000000)
 136: add r1.xy, r2.xyxx, -r3.xyxx
 137: mad r1.xy, r0.xxxx, r1.xyxx, r3.xyxx
 138: add r0.xz, r0.zzwz, -r1.xxyx
 139: mad o5.xy, r0.yyyy, r0.xzxx, r1.xyxx
 140: ret
