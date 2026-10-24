Shader hash aeb80ec8-e6689c5b-01f6c1f7-54a2f17f

cs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[159], immediateIndexed
      dcl_uav_structured u0, 16
      dcl_input vThreadID.xy
      dcl_temps 7
      dcl_thread_group 32, 32, 1
   0: imad r0.x, vThreadID.y, cb0[155].x, vThreadID.x
   1: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xyzw, r0.x, l(0), u0.xyzw
   2: ushr r2.xyzw, r1.xyzw, l(16, 8, 24, 28)
   3: bfi r0.yz, l(0, 16, 24, 0), l(0, 16, 8, 0), r1.yywy, r2.xxzx
   4: utof r2.xy, r2.ywyy
   5: mad r2.zw, r2.xxxy, l(0.000000, 0.000000, 0.000000, 1.000000), l(0.000000, 0.000000, -4.000000, 0.500000)
   6: and r0.yz, r0.yyzy, l(0.000000, 0.000000, 0.000000, 0.000000)
   7: utof r0.yz, r0.yyzy
   8: mad r2.xy, r0.yzyy, l(0.000000, 1.000000, 0.000000, 0.000000), l(-4.000000, 0.500000, 0.000000, 0.000000)
   9: div r0.yz, r2.xxzx, cb0[116].xxzx
  10: ftou r2.xy, r2.ywyy
  11: mul r0.yz, r0.yyzy, cb0[158].zzzz
  12: itof r2.zw, vThreadID.xxxy
  13: add r2.zw, r2.zzzw, l(0.000000, 0.000000, 0.500000, 0.500000)
  14: itof r3.xy, cb0[155].xyxx
  15: div_sat r2.zw, r2.zzzw, r3.xxxy
  16: mad r0.yz, -r0.yyzy, cb0[157].zzzz, r2.zzwz
  17: mad r0.yz, r0.yyzy, r3.xxyx, l(0.000000, -0.500000, -0.500000, 0.000000)
  18: round_ni r2.zw, r0.yyyz
  19: frc r0.yz, r0.yyzy
  20: ftoi r2.zw, r2.zzzw
  21: imax r3.xy, r2.zwzz, l(0, 0, 0, 0)
  22: iadd r3.zw, cb0[155].xxxy, l(0, 0, -1, -1)
  23: imin r3.xy, r3.zwzz, r3.xyxx
  24: imad r0.w, r3.y, cb0[155].x, r3.x
  25: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xy, r0.w, l(0), u0.xyxx
  26: iadd r4.xyzw, r2.zwzw, l(1, 0, 0, 1)
  27: iadd r2.zw, r2.zzzw, l(0, 0, 1, 1)
  28: imax r2.zw, r2.zzzw, l(0, 0, 0, 0)
  29: imin r2.zw, r3.zzzw, r2.zzzw
  30: imad r0.w, r2.w, cb0[155].x, r2.z
  31: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.zw, r0.w, l(0), u0.xxxy
  32: imax r4.xyzw, r4.xyzw, l(0, 0, 0, 0)
  33: imin r4.xyzw, r3.zwzw, r4.xyzw
  34: imad r3.zw, r4.yyyw, cb0[155].xxxx, r4.xxxz
  35: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r4.xy, r3.z, l(0), u0.xyxx
  36: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.zw, r3.w, l(0), u0.xxxy
  37: ushr r4.zw, r2.zzzw, l(0, 0, 16, 8)
  38: bfi r0.w, l(16), l(16), r2.w, r4.z
  39: utof r1.y, r4.w
  40: mad r5.y, r1.y, l(0.000000), l(-4.000000)
  41: and r0.w, r0.w, l(0.000000)
  42: utof r0.w, r0.w
  43: mad r5.x, r0.w, l(0.000000), l(-4.000000)
  44: ushr r2.zw, r3.zzzw, l(0, 0, 16, 8)
  45: bfi r0.w, l(16), l(16), r3.w, r2.z
  46: utof r1.y, r2.w
  47: mad r6.y, r1.y, l(0.000000), l(-4.000000)
  48: and r0.w, r0.w, l(0.000000)
  49: utof r0.w, r0.w
  50: mad r6.x, r0.w, l(0.000000), l(-4.000000)
  51: add r2.zw, r5.xxxy, -r6.xxxy
  52: mad r2.zw, r0.yyyy, r2.zzzw, r6.xxxy
  53: ushr r3.zw, r4.xxxy, l(0, 0, 16, 8)
  54: bfi r0.w, l(16), l(16), r4.y, r3.z
  55: utof r1.y, r3.w
  56: mad r4.y, r1.y, l(0.000000), l(-4.000000)
  57: and r0.w, r0.w, l(0.000000)
  58: utof r0.w, r0.w
  59: mad r4.x, r0.w, l(0.000000), l(-4.000000)
  60: ushr r3.xz, r3.xxyx, l(16, 0, 8, 0)
  61: bfi r0.w, l(16), l(16), r3.y, r3.x
  62: utof r1.y, r3.z
  63: mad r3.y, r1.y, l(0.000000), l(-4.000000)
  64: and r0.w, r0.w, l(0.000000)
  65: utof r0.w, r0.w
  66: mad r3.x, r0.w, l(0.000000), l(-4.000000)
  67: add r3.zw, -r3.xxxy, r4.xxxy
  68: mad r0.yw, r0.yyyy, r3.zzzw, r3.xxxy
  69: add r2.zw, -r0.yyyw, r2.zzzw
  70: mad r0.yz, r0.zzzz, r2.zzwz, r0.yywy
  71: add r0.yz, r0.yyzy, l(0.000000, 4.000000, 4.000000, 0.000000)
  72: mul_sat r0.yz, r0.yyzy, l(0.000000, 0.125000, 0.125000, 0.000000)
  73: mad r0.yz, r0.yyzy, l(0.000000, 16777215.000000, 16777215.000000, 0.000000), l(0.000000, 0.500000, 0.500000, 0.000000)
  74: ftou r0.yz, r0.yyzy
  75: ushr r0.w, r0.y, l(16)
  76: ishl r0.z, r0.z, l(8)
  77: or r3.y, r0.z, r0.w
  78: and r0.zw, r1.xxxz, l(0.000000, 0.000000, 0.000000, 0.000000)
  79: ubfe r1.xyz, l(8, 8, 4, 0), l(8, 16, 24, 0), r1.xwwx
  80: utof r1.xyz, r1.xyzx
  81: mad r1.xyz, r1.xyzx, l(1.000000, 1.000000, 1.000000, 0.000000), l(0.500000, 0.500000, 0.500000, 0.000000)
  82: ftou r1.xyz, r1.xyzx
  83: utof r0.zw, r0.zzzw
  84: mad r0.zw, r0.zzzw, l(0.000000, 0.000000, 1.000000, 1.000000), l(0.000000, 0.000000, 0.500000, 0.500000)
  85: ftou r4.xy, r0.zwzz
  86: imad r0.z, r1.x, l(256), r4.x
  87: bfi r3.x, l(16), l(16), r0.y, r0.z
  88: ishl r5.x, r2.x, l(24)
  89: ushr r5.y, r2.x, l(8)
  90: ishl r2.w, r2.y, l(28)
  91: mov r4.z, l(0)
  92: iadd r0.yz, r4.yyzy, r5.xxyx
  93: imad r0.z, r1.y, l(0x00010000), r0.z
  94: mov r3.z, r0.y
  95: imad r3.w, r1.z, l(0.000000), r0.z
  96: mov r2.xyz, l(0, 0, 0, 0)
  97: iadd r1.xyzw, r2.xyzw, r3.xyzw
  98: store_structured u0.xyzw, r0.x, l(0), r1.xyzw
  99: ret
