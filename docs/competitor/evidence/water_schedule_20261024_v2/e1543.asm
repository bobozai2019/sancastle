Shader hash 35fcb9db-244fa7b9-fbe3b7c5-09f534a1

cs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[156], immediateIndexed
      dcl_uav_structured u0, 16
      dcl_input vThreadID.xy
      dcl_temps 6
      dcl_thread_group 32, 32, 1
   0: iadd r0.xyzw, vThreadID.xyxy, l(-1, 0, 1, 0)
   1: imax r0.x, r0.x, l(0)
   2: iadd r1.xy, cb0[155].xyxx, l(-1, -1, 0, 0)
   3: imin r0.xyzw, r0.xyzw, r1.xyxy
   4: imad r0.x, r0.y, cb0[155].x, r0.x
   5: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.xy, r0.x, l(8), u0.xyxx
   6: imad r0.z, r0.w, cb0[155].x, r0.z
   7: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.zw, r0.z, l(8), u0.xxxy
   8: iadd r2.xyzw, vThreadID.xyxy, l(0, -1, 0, 1)
   9: imax r2.y, r2.y, l(0)
  10: imin r1.zw, r1.xxxy, r2.zzzw
  11: imin r1.xy, r1.xyxx, r2.xyxx
  12: imad r1.x, r1.y, cb0[155].x, r1.x
  13: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xy, r1.x, l(8), u0.xyxx
  14: imad r1.z, r1.w, cb0[155].x, r1.z
  15: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.zw, r1.z, l(8), u0.xxxy
  16: imad r2.x, vThreadID.y, cb0[155].x, vThreadID.x
  17: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xyzw, r2.x, l(0), u0.xyzw
  18: ushr r2.y, r0.z, l(24)
  19: bfi r0.w, l(24), l(8), r0.w, r2.y
  20: and r0.zw, r0.zzzw, l(0.000000, 0.000000, 0.000000, 0.000000)
  21: utof r0.zw, r0.zzzw
  22: mad r0.z, r0.z, l(0.000001), l(-0.050000)
  23: max r0.z, r0.z, l(0)
  24: mad r0.z, r0.w, l(0.000001), r0.z
  25: ushr r0.w, r0.x, l(24)
  26: bfi r0.y, l(24), l(8), r0.y, r0.w
  27: and r0.xy, r0.xyxx, l(0.000000, 0.000000, 0.000000, 0.000000)
  28: utof r0.xy, r0.xyxx
  29: mad r0.x, r0.x, l(0.000001), l(-0.050000)
  30: max r0.x, r0.x, l(0)
  31: mad r0.x, r0.y, l(0.000001), r0.x
  32: add r0.x, -r0.z, r0.x
  33: ushr r0.z, r1.z, l(24)
  34: bfi r0.z, l(24), l(8), r1.w, r0.z
  35: and r0.w, r1.z, l(0.000000)
  36: utof r0.w, r0.w
  37: mad r0.w, r0.w, l(0.000001), l(-0.050000)
  38: max r0.w, r0.w, l(0)
  39: and r0.z, r0.z, l(0.000000)
  40: utof r0.z, r0.z
  41: mad r0.z, r0.z, l(0.000001), r0.w
  42: ushr r0.w, r1.x, l(24)
  43: bfi r0.w, l(24), l(8), r1.y, r0.w
  44: and r1.x, r1.x, l(0.000000)
  45: utof r1.x, r1.x
  46: mad r1.x, r1.x, l(0.000001), l(-0.050000)
  47: max r1.x, r1.x, l(0)
  48: and r0.w, r0.w, l(0.000000)
  49: utof r0.w, r0.w
  50: mad r0.w, r0.w, l(0.000001), r1.x
  51: add r0.y, -r0.z, r0.w
  52: mul r0.xy, r0.xyxx, cb0[154].zwzz
  53: mul r0.xy, r0.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
  54: mov r0.z, l(1.000000)
  55: dp3 r0.z, r0.xyzx, r0.xyzx
  56: rsq r0.z, r0.z
  57: mad r0.xy, r0.xyxx, r0.zzzz, l(1.000000, 1.000000, 0.000000, 0.000000)
  58: mul_sat r0.xy, r0.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
  59: mad r0.xy, r0.xyxx, l(255.000000, 255.000000, 0.000000, 0.000000), l(0.500000, 0.500000, 0.000000, 0.000000)
  60: ftou r0.xy, r0.xyxx
  61: imad r0.x, r0.y, l(256), r0.x
  62: ushr r1.xyzw, r3.xyzw, l(16, 8, 24, 28)
  63: bfi r0.yz, l(0, 16, 24, 0), l(0, 16, 8, 0), r3.yywy, r1.xxzx
  64: utof r1.xy, r1.ywyy
  65: mad r1.xy, r1.xyxx, l(1.000000, 1.000000, 0.000000, 0.000000), l(0.500000, 0.500000, 0.000000, 0.000000)
  66: ftou r1.xy, r1.xyxx
  67: ishl r1.xy, r1.xyxx, l(8, 28, 0, 0)
  68: and r0.yz, r0.yyzy, l(0.000000, 0.000000, 0.000000, 0.000000)
  69: utof r0.yz, r0.yyzy
  70: mad r0.yz, r0.yyzy, l(0.000000, 1.000000, 1.000000, 0.000000), l(0.000000, 0.500000, 0.500000, 0.000000)
  71: ftou r0.yz, r0.yyzy
  72: bfi r4.x, l(16), l(16), r0.y, r0.x
  73: and r0.x, r3.z, l(0.000000)
  74: ubfe r2.yz, l(0, 8, 4, 0), l(0, 16, 24, 0), r3.wwww
  75: utof r2.yz, r2.yyzy
  76: mad r2.yz, r2.yyzy, l(0.000000, 1.000000, 1.000000, 0.000000), l(0.000000, 0.500000, 0.500000, 0.000000)
  77: ftou r2.yz, r2.yyzy
  78: utof r0.x, r0.x
  79: mad r0.x, r0.x, l(1.000000), l(0.500000)
  80: ftou r3.x, r0.x
  81: ishl r5.x, r0.z, l(24)
  82: ushr r5.yz, r0.yyzy, l(0, 16, 8, 0)
  83: mov r3.y, l(0)
  84: iadd r0.xy, r3.xyxx, r5.xzxx
  85: or r4.y, r1.x, r5.y
  86: imad r0.y, r2.y, l(0x00010000), r0.y
  87: mov r4.z, r0.x
  88: imad r4.w, r2.z, l(0.000000), r0.y
  89: mov r1.z, l(0)
  90: iadd r0.xyzw, r1.zzzy, r4.xyzw
  91: store_structured u0.xyzw, r2.x, l(0), r0.xyzw
  92: ret
