Shader hash 0f088406-3a6bb67e-e018e057-5a6de84f

cs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[153], immediateIndexed
      dcl_resource_structured t0, 16
      dcl_uav_structured u0, 16
      dcl_input vThreadID.x
      dcl_temps 11
      dcl_thread_group 1024, 1, 1
   0: uge r0.x, vThreadID.x, cb0[138].x
   1: if_nz r0.x
   2:   ret
   3: endif
   4: iadd r0.x, vThreadID.x, cb0[113].x
   5: iadd r0.x, r0.x, cb0[113].w
   6: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xy, vThreadID.x, l(0), u0.xyxx
   7: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.z, vThreadID.x, l(12), u0.xxxx
   8: lt r0.y, r1.x, l(0.010000)
   9: xor r0.z, r0.x, l(0x0000e663)
  10: ushr r0.x, r0.x, l(16)
  11: xor r0.x, r0.z, r0.x
  12: xor r0.x, r0.x, l(0)
  13: imul null, r0.x, r0.x, l(9)
  14: ushr r0.z, r0.x, l(4)
  15: xor r0.x, r0.z, r0.x
  16: imul null, r0.x, r0.x, l(0.000000)
  17: ushr r0.z, r0.x, l(15)
  18: xor r0.x, r0.z, r0.x
  19: xor r0.z, r0.x, l(61)
  20: ushr r0.w, r0.x, l(16)
  21: xor r0.xz, r0.wwww, r0.xxzx
  22: imul null, r0.z, r0.z, l(9)
  23: ushr r1.w, r0.z, l(4)
  24: xor r0.z, r0.z, r1.w
  25: imul null, r0.z, r0.z, l(0.000000)
  26: ushr r1.w, r0.z, l(15)
  27: xor r0.z, r0.z, r1.w
  28: xor r0.x, r0.x, l(0x005b5c68)
  29: imul null, r0.x, r0.x, l(9)
  30: ushr r0.w, r0.x, l(4)
  31: xor r0.x, r0.w, r0.x
  32: imul null, r0.x, r0.x, l(0.000000)
  33: ushr r0.w, r0.x, l(15)
  34: xor r0.x, r0.w, r0.x
  35: bfi r0.xz, l(23, 0, 23, 0), l(0, 0, 0, 0), r0.xxzx, l(1.000000, 0.000000, 1.000000, 0.000000)
  36: add r0.xz, r0.xxzx, l(-1.500000, 0.000000, -1.500000, 0.000000)
  37: mul r2.yz, r0.zzxz, cb0[116].xxzx
  38: mov r2.x, l(0.010000)
  39: movc r0.xyz, r0.yyyy, r2.xyzx, r1.xyzx
  40: div r1.xy, r0.yzyy, cb0[116].xzxx
  41: add_sat r1.xy, r1.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
  42: itof r1.zw, cb0[152].xxxy
  43: mad r1.xy, r1.xyxx, r1.zwzz, l(-0.500000, -0.500000, 0.000000, 0.000000)
  44: round_ni r1.zw, r1.xxxy
  45: ftoi r1.zw, r1.zzzw
  46: frc r1.xy, r1.xyxx
  47: iadd r2.xy, cb0[152].xyxx, l(-1, -1, 0, 0)
  48: imax r2.zw, r1.zzzw, l(0, 0, 0, 0)
  49: imin r2.zw, r2.xxxy, r2.zzzw
  50: imad r0.w, r2.w, cb0[152].x, r2.z
  51: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xyzw, r0.w, l(0), t0.xyzw
  52: ushr r4.xyz, r3.xyzx, l(16, 8, 24, 0)
  53: bfi r2.zw, l(0, 0, 16, 24), l(0, 0, 16, 8), r3.yyyw, r4.xxxz
  54: and r2.zw, r2.zzzw, l(0.000000, 0.000000, 0.000000, 0.000000)
  55: utof r2.zw, r2.zzzw
  56: mul r0.w, r2.w, l(0.000001)
  57: mad r5.y, r2.z, l(0.000000), l(-4.000000)
  58: utof r2.z, r4.y
  59: mad r5.w, r2.z, l(0.000000), l(-4.000000)
  60: and r2.z, r3.z, l(0.000000)
  61: utof r2.z, r2.z
  62: ubfe r2.w, l(8), l(16), r3.w
  63: utof r2.w, r2.w
  64: mul r2.zw, r2.zzzw, l(0.000000, 0.000000, 0.000001, 0.003922)
  65: iadd r3.xyzw, r1.zwzw, l(1, 0, 0, 1)
  66: imax r3.xyzw, r3.xyzw, l(0, 0, 0, 0)
  67: imin r3.xyzw, r2.xyxy, r3.xyzw
  68: imad r3.xy, r3.ywyy, cb0[152].xxxx, r3.xzxx
  69: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r4.xyzw, r3.x, l(0), t0.xyzw
  70: ushr r3.xzw, r4.xxyz, l(16, 0, 8, 24)
  71: bfi r3.xw, l(16, 0, 0, 24), l(16, 0, 0, 8), r4.yyyw, r3.xxxw
  72: and r3.xw, r3.xxxw, l(0.000000, 0.000000, 0.000000, 0.000000)
  73: utof r3.xw, r3.xxxw
  74: mad r6.y, r3.x, l(0.000000), l(-4.000000)
  75: utof r3.x, r3.z
  76: mad r6.w, r3.x, l(0.000000), l(-4.000000)
  77: and r3.x, r4.z, l(0.000000)
  78: ubfe r3.z, l(8), l(16), r4.w
  79: utof r3.xz, r3.xxzx
  80: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r4.xyzw, r3.y, l(0), t0.xyzw
  81: ushr r7.xyz, r4.xyzx, l(16, 8, 24, 0)
  82: bfi r4.xy, l(16, 24, 0, 0), l(16, 8, 0, 0), r4.ywyy, r7.xzxx
  83: and r4.xy, r4.xyxx, l(0.000000, 0.000000, 0.000000, 0.000000)
  84: utof r4.xy, r4.xyxx
  85: mul r3.y, r4.y, l(0.000001)
  86: mad r8.y, r4.x, l(0.000000), l(-4.000000)
  87: utof r4.x, r7.y
  88: mad r8.w, r4.x, l(0.000000), l(-4.000000)
  89: and r4.x, r4.z, l(0.000000)
  90: utof r4.x, r4.x
  91: ubfe r4.y, l(8), l(16), r4.w
  92: utof r4.y, r4.y
  93: mul r4.xy, r4.xyxx, l(0.000001, 0.003922, 0.000000, 0.000000)
  94: iadd r1.zw, r1.zzzw, l(0, 0, 1, 1)
  95: imax r1.zw, r1.zzzw, l(0, 0, 0, 0)
  96: imin r1.zw, r2.xxxy, r1.zzzw
  97: imad r1.z, r1.w, cb0[152].x, r1.z
  98: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r7.xyzw, r1.z, l(0), t0.xyzw
  99: ushr r9.xyz, r7.xyzx, l(16, 8, 24, 0)
 100: bfi r1.zw, l(0, 0, 16, 24), l(0, 0, 16, 8), r7.yyyw, r9.xxxz
 101: and r1.zw, r1.zzzw, l(0.000000, 0.000000, 0.000000, 0.000000)
 102: utof r1.zw, r1.zzzw
 103: mad r10.y, r1.z, l(0.000000), l(-4.000000)
 104: utof r1.z, r9.y
 105: mad r10.w, r1.z, l(0.000000), l(-4.000000)
 106: and r1.z, r7.z, l(0.000000)
 107: utof r1.z, r1.z
 108: ubfe r2.x, l(8), l(16), r7.w
 109: utof r2.x, r2.x
 110: add r4.zw, -r5.yyyw, r6.yyyw
 111: mad r4.zw, r1.xxxx, r4.zzzw, r5.yyyw
 112: mad r2.y, r3.x, l(0.000001), -r2.z
 113: mad r2.y, r1.x, r2.y, r2.z
 114: mad r2.z, r3.w, l(0.000001), -r0.w
 115: mad r0.w, r1.x, r2.z, r0.w
 116: mad r2.z, r3.z, l(0.003922), -r2.w
 117: mad r2.z, r1.x, r2.z, r2.w
 118: add r3.xz, -r8.yywy, r10.yywy
 119: mad r3.xz, r1.xxxx, r3.xxzx, r8.yywy
 120: mad r1.z, r1.z, l(0.000001), -r4.x
 121: mad r1.z, r1.x, r1.z, r4.x
 122: mad r1.w, r1.w, l(0.000001), -r3.y
 123: mad r1.w, r1.x, r1.w, r3.y
 124: mad r2.x, r2.x, l(0.003922), -r4.y
 125: mad r1.x, r1.x, r2.x, r4.y
 126: add r2.xw, -r4.zzzw, r3.xxxz
 127: mad r2.xw, r1.yyyy, r2.xxxw, r4.zzzw
 128: add r1.xz, -r2.zzyz, r1.xxzx
 129: mad r1.z, r1.y, r1.z, r2.y
 130: add r1.w, -r0.w, r1.w
 131: mad r0.w, r1.y, r1.w, r0.w
 132: mad r1.x, r1.y, r1.x, r2.z
 133: lt r1.y, l(0.050000), r1.z
 134: and r1.y, r1.y, l(1.000000)
 135: mul r1.yw, r1.yyyy, r2.xxxw
 136: mul r1.yw, r1.yyyw, cb0[152].zzzz
 137: mad r0.yz, r1.yywy, l(0.000000, 0.500000, 0.500000, 0.000000), r0.yyzy
 138: add r1.y, r1.z, l(-0.050000)
 139: max r1.y, r1.y, l(0)
 140: add r2.z, r0.w, r1.y
 141: mul r3.xyzw, cb0[116].xzxz, l(-0.500000, -0.500000, 0.500000, 0.500000)
 142: max r0.yz, r0.yyzy, r3.xxyx
 143: min r2.yw, r3.zzzw, r0.yyyz
 144: dp2 r0.y, r1.xxxx, cb0[152].zzzz
 145: add r0.x, r0.y, r0.x
 146: mad_sat r2.x, -cb0[152].z, l(0.200000), r0.x
 147: store_structured u0.xyzw, vThreadID.x, l(0), r2.xyzw
 148: ret
