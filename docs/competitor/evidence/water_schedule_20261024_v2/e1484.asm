Shader hash 043e72d4-ed23d6ac-ef35c927-4cf9a736

cs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[156], immediateIndexed
      dcl_resource_structured t0, 16
      dcl_uav_structured u0, 16
      dcl_input vThreadID.xy
      dcl_temps 5
      dcl_thread_group 32, 32, 1
   0: imad r0.x, vThreadID.y, cb0[155].x, vThreadID.x
   1: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xyzw, r0.x, l(0), u0.xyzw
   2: itof r0.yz, vThreadID.xxyx
   3: add r0.yz, r0.yyzy, l(0.000000, 0.500000, 0.500000, 0.000000)
   4: itof r2.xy, cb0[155].xyxx
   5: div_sat r0.yz, r0.yyzy, r2.xxyx
   6: itof r2.xy, cb0[153].xyxx
   7: mad r0.yz, r0.yyzy, r2.xxyx, l(0.000000, -0.500000, -0.500000, 0.000000)
   8: round_ni r2.xy, r0.yzyy
   9: frc r0.yz, r0.yyzy
  10: ftoi r2.xy, r2.xyxx
  11: iadd r2.zw, r2.xxxy, l(0, 0, 1, 1)
  12: imax r2.zw, r2.zzzw, l(0, 0, 0, 0)
  13: iadd r3.xy, cb0[153].xyxx, l(-1, -1, 0, 0)
  14: imin r2.zw, r2.zzzw, r3.xxxy
  15: imad r0.w, r2.w, cb0[153].x, r2.z
  16: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.zw, r0.w, l(8), t0.xxxy
  17: ushr r0.w, r2.z, l(12)
  18: bfi r0.w, l(12), l(20), r2.w, r0.w
  19: and r2.z, r2.z, l(4095)
  20: and r0.w, r0.w, l(0.000000)
  21: utof r0.w, r0.w
  22: iadd r4.xyzw, r2.xyxy, l(1, 0, 0, 1)
  23: imax r2.xy, r2.xyxx, l(0, 0, 0, 0)
  24: imin r2.xy, r3.xyxx, r2.xyxx
  25: imad r2.x, r2.y, cb0[153].x, r2.x
  26: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xy, r2.x, l(8), t0.xyxx
  27: imax r4.xyzw, r4.xyzw, l(0, 0, 0, 0)
  28: imin r3.xyzw, r3.xyxy, r4.xyzw
  29: imad r3.xy, r3.ywyy, cb0[153].xxxx, r3.xzxx
  30: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.yz, r3.y, l(8), t0.xxyx
  31: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xw, r3.x, l(8), t0.xxxy
  32: ushr r2.w, r3.y, l(12)
  33: bfi r2.w, l(12), l(20), r3.z, r2.w
  34: and r3.y, r3.y, l(4095)
  35: utof r3.y, r3.y
  36: mul r3.y, r3.y, l(0.002466)
  37: and r2.w, r2.w, l(0.000000)
  38: utof r2.zw, r2.zzzw
  39: mul r2.w, r2.w, l(0.000001)
  40: mad r0.w, r0.w, l(0.000001), -r2.w
  41: mad r0.w, r0.y, r0.w, r2.w
  42: ushr r2.w, r3.x, l(12)
  43: bfi r2.w, l(12), l(20), r3.w, r2.w
  44: and r3.x, r3.x, l(4095)
  45: utof r3.x, r3.x
  46: and r2.w, r2.w, l(0.000000)
  47: ushr r3.z, r2.x, l(12)
  48: bfi r2.y, l(12), l(20), r2.y, r3.z
  49: and r2.xy, r2.xyxx, l(0.000000, 0.000000, 0.000000, 0.000000)
  50: utof r2.xyw, r2.xyxw
  51: mul r2.xy, r2.xyxx, l(0.002466, 0.000001, 0.000000, 0.000000)
  52: mad r2.w, r2.w, l(0.000001), -r2.y
  53: mad r2.y, r0.y, r2.w, r2.y
  54: add r0.w, r0.w, -r2.y
  55: mad r0.w, r0.z, r0.w, r2.y
  56: mad r2.y, r2.z, l(0.002466), -r3.y
  57: mad r2.y, r0.y, r2.y, r3.y
  58: mad r2.z, r3.x, l(0.002466), -r2.x
  59: mad r0.y, r0.y, r2.z, r2.x
  60: add r2.x, -r0.y, r2.y
  61: mad r0.y, r0.z, r2.x, r0.y
  62: max r0.y, r0.y, r0.w
  63: mul_sat r0.y, r0.y, l(0.099010)
  64: mad r0.y, r0.y, l(16777215.000000), l(0.500000)
  65: ftou r0.y, r0.y
  66: ushr r0.z, r0.y, l(8)
  67: ubfe r2.xyz, l(8, 8, 4, 0), l(8, 16, 24, 0), r1.xwwx
  68: utof r2.xyz, r2.xyzx
  69: mad r2.xyz, r2.xyzx, l(1.000000, 1.000000, 1.000000, 0.000000), l(0.500000, 0.500000, 0.500000, 0.000000)
  70: ftou r2.xyz, r2.xyzx
  71: ishl r0.w, r2.y, l(16)
  72: or r0.z, r0.w, r0.z
  73: imad r3.w, r2.z, l(0.000000), r0.z
  74: and r0.zw, r1.xxxz, l(0.000000, 0.000000, 0.000000, 0.000000)
  75: utof r0.zw, r0.zzzw
  76: mad r0.zw, r0.zzzw, l(0.000000, 0.000000, 1.000000, 1.000000), l(0.000000, 0.000000, 0.500000, 0.500000)
  77: ftou r0.zw, r0.zzzw
  78: bfi r3.z, l(8), l(24), r0.y, r0.w
  79: imad r0.y, r2.x, l(256), r0.z
  80: ushr r1.xzw, r1.xxyw, l(16, 0, 8, 28)
  81: bfi r0.z, l(16), l(16), r1.y, r1.x
  82: utof r1.xy, r1.zwzz
  83: mad r1.xy, r1.xyxx, l(1.000000, 1.000000, 0.000000, 0.000000), l(0.500000, 0.500000, 0.000000, 0.000000)
  84: ftou r1.xy, r1.xyxx
  85: ishl r1.xy, r1.xyxx, l(8, 28, 0, 0)
  86: and r0.z, r0.z, l(0.000000)
  87: utof r0.z, r0.z
  88: mad r0.z, r0.z, l(1.000000), l(0.500000)
  89: ftou r0.z, r0.z
  90: bfi r3.x, l(16), l(16), r0.z, r0.y
  91: ushr r0.y, r0.z, l(16)
  92: or r3.y, r1.x, r0.y
  93: mov r1.z, l(0)
  94: iadd r1.xyzw, r1.zzzy, r3.xyzw
  95: store_structured u0.xyzw, r0.x, l(0), r1.xyzw
  96: ret
