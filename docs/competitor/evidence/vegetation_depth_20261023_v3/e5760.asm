Shader hash b5dcd591-032987aa-dffd5463-54575fa7

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[140], immediateIndexed
      dcl_constantbuffer cb1[2], immediateIndexed
      dcl_sampler s0, mode_comparison
      dcl_sampler s1, mode_default
      dcl_sampler s2, mode_default
      dcl_sampler s3, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_texture2d (float,float,float,float) t1
      dcl_resource_structured t2, 16
      dcl_resource_texture2d (float,float,float,float) t3
      dcl_input_ps_siv linear noperspective v0.xy, position
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v2.xyz
      dcl_input_ps linear v3.xyz
      dcl_input_ps linear v4.xyzw
      dcl_output o0.xyzw
      dcl_output oDepth
      dcl_temps 9
   0: dp3 r0.x, v4.xyzx, v4.xyzx
   1: rsq r0.x, r0.x
   2: mul r0.xyz, r0.xxxx, v4.xyzx
   3: dp3 r0.y, l(1.000000, 1.000000, 1.000000, 0.000000), abs(r0.xyzx)
   4: div r0.xy, r0.xzxx, r0.yyyy
   5: add r1.x, r0.y, r0.x
   6: add r1.y, -r0.y, r0.x
   7: mad r0.xy, r1.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000), l(0.500000, 0.500000, 0.000000, 0.000000)
   8: add r0.zw, cb1[0].xxxy, l(0.000000, 0.000000, -1.000000, -1.000000)
   9: mul r0.xy, r0.zwzz, r0.xyxx
  10: round_ni r1.xy, r0.xyxx
  11: frc r0.xy, r0.xyxx
  12: div r2.xy, r1.xyxx, r0.zwzz
  13: mad r2.xy, r2.xyxx, l(2.000000, 2.000000, 0.000000, 0.000000), l(-1.000000, -1.000000, 0.000000, 0.000000)
  14: add r3.x, r2.y, r2.x
  15: add r3.z, -r2.y, r2.x
  16: mul r2.xz, r3.xxzx, l(0.500000, 0.000000, 0.500000, 0.000000)
  17: dp2 r2.w, l(1.000000, 1.000000, 0.000000, 0.000000), abs(r2.xzxx)
  18: add r2.y, -r2.w, l(1.000000)
  19: dp3 r2.w, r2.xyzx, r2.xyzx
  20: rsq r2.w, r2.w
  21: mul r2.xyz, r2.wwww, r2.xyzx
  22: mul r3.xyz, r2.zxyz, l(0.000000, 1.000000, 0.000000, 0.000000)
  23: mad r3.xyz, r2.xyzx, l(0.000000, 0.000000, 1.000000, 0.000000), -r3.xyzx
  24: dp2 r2.w, r3.yzyy, r3.yzyy
  25: rsq r2.w, r2.w
  26: mul r3.xyz, r2.wwww, r3.xyzx
  27: mul r4.xyz, r2.zxyz, r3.xyzx
  28: mad r4.xyz, r2.yzxy, r3.yzxy, -r4.xyzx
  29: dp3 r2.w, r2.xyzx, v4.xyzx
  30: div r5.xyz, cb1[1].xyzx, cb1[1].wwww
  31: dp3 r3.x, r2.xyzx, r5.xyzx
  32: add r2.w, -r2.w, r3.x
  33: add r6.xyz, -v1.xyzx, v4.xyzx
  34: dp3 r3.x, r6.xyzx, r6.xyzx
  35: rsq r3.x, r3.x
  36: mul r6.xyz, r3.xxxx, r6.xyzx
  37: dp3 r2.x, r2.xyzx, r6.xyzx
  38: div r2.x, r2.w, r2.x
  39: mad r2.xyz, r6.xyzx, r2.xxxx, v4.xyzx
  40: add r2.xyz, -r5.xyzx, r2.xyzx
  41: dp3 r4.y, r4.xyzx, r2.xyzx
  42: dp2 r2.x, r3.zyzz, r2.xzxx
  43: mov r4.x, -r2.x
  44: mad r2.xy, r4.xyxx, cb1[1].wwww, l(0.500000, 0.500000, 0.000000, 0.000000)
  45: lt r2.zw, l(0, 0, 0, 0), r2.xxxy
  46: lt r3.xy, r2.xyxx, l(1.000000, 1.000000, 0.000000, 0.000000)
  47: add r2.xy, r1.xyxx, r2.xyxx
  48: div_sat r2.xy, r2.xyxx, cb1[0].xyxx
  49: and r2.z, r2.z, r3.x
  50: and r2.z, r2.w, r2.z
  51: and r2.z, r3.y, r2.z
  52: and r2.z, r2.z, l(1.000000)
  53: sample_indexable(texture2d)(float,float,float,float) r3.xyzw, r2.xyxx, t1.xyzw, s1
  54: sample_indexable(texture2d)(float,float,float,float) r2.x, r2.xyxx, t1.wxyz, s2
  55: add r2.x, -r2.x, l(0.500000)
  56: div r2.x, r2.x, cb1[1].w
  57: mul r2.x, r2.x, v4.w
  58: mul_sat r2.y, r3.w, l(2.500000)
  59: mad r2.w, r2.y, l(-2.000000), l(3.000000)
  60: mul r2.y, r2.y, r2.y
  61: mul r2.y, r2.y, r2.w
  62: mul r2.y, r2.z, r2.y
  63: add r2.z, -r0.y, r0.x
  64: round_pi r2.z, r2.z
  65: mov r1.zw, l(0.000000, 0.000000, 0.000000, 1.000000)
  66: mad r2.zw, r2.zzzz, l(0.000000, 0.000000, 1.000000, -1.000000), r1.zzzy
  67: add r1.zw, r1.xxxw, r2.zzzw
  68: add r1.xy, r1.xyxx, l(1.000000, 1.000000, 0.000000, 0.000000)
  69: div r2.zw, r1.zzzw, r0.zzzw
  70: div r0.zw, r1.xxxy, r0.zzzw
  71: mad r0.zw, r0.zzzw, l(0.000000, 0.000000, 2.000000, 2.000000), l(0.000000, 0.000000, -1.000000, -1.000000)
  72: mad r2.zw, r2.zzzw, l(0.000000, 0.000000, 2.000000, 2.000000), l(0.000000, 0.000000, -1.000000, -1.000000)
  73: add r4.x, r2.w, r2.z
  74: add r4.z, -r2.w, r2.z
  75: mul r4.xz, r4.xxzx, l(0.500000, 0.000000, 0.500000, 0.000000)
  76: dp2 r2.z, l(1.000000, 1.000000, 0.000000, 0.000000), abs(r4.xzxx)
  77: add r4.y, -r2.z, l(1.000000)
  78: dp3 r2.z, r4.xyzx, r4.xyzx
  79: rsq r2.z, r2.z
  80: mul r4.xyz, r2.zzzz, r4.xyzx
  81: mul r7.xyz, r4.zxyz, l(0.000000, 1.000000, 0.000000, 0.000000)
  82: mad r7.xyz, r4.xyzx, l(0.000000, 0.000000, 1.000000, 0.000000), -r7.xyzx
  83: dp2 r2.z, r7.yzyy, r7.yzyy
  84: rsq r2.z, r2.z
  85: mul r7.xyz, r2.zzzz, r7.xyzx
  86: mul r8.xyz, r4.zxyz, r7.xyzx
  87: mad r8.xyz, r4.yzxy, r7.yzxy, -r8.xyzx
  88: dp3 r2.z, r4.xyzx, v4.xyzx
  89: dp3 r2.w, r4.xyzx, r5.xyzx
  90: dp3 r3.w, r4.xyzx, r6.xyzx
  91: add r2.z, -r2.z, r2.w
  92: div r2.z, r2.z, r3.w
  93: mad r4.xyz, r6.xyzx, r2.zzzz, v4.xyzx
  94: add r4.xyz, -r5.xyzx, r4.xyzx
  95: dp3 r8.y, r8.xyzx, r4.xyzx
  96: dp2 r2.z, r7.zyzz, r4.xzxx
  97: mov r8.x, -r2.z
  98: mad r2.zw, r8.xxxy, cb1[1].wwww, l(0.000000, 0.000000, 0.500000, 0.500000)
  99: lt r4.xy, l(0, 0, 0, 0), r2.zwzz
 100: lt r4.zw, r2.zzzw, l(0.000000, 0.000000, 1.000000, 1.000000)
 101: add r1.zw, r1.zzzw, r2.zzzw
 102: div_sat r1.zw, r1.zzzw, cb1[0].xxxy
 103: and r2.z, r4.z, r4.x
 104: and r2.z, r4.y, r2.z
 105: and r2.z, r4.w, r2.z
 106: and r2.z, r2.z, l(1.000000)
 107: sample_indexable(texture2d)(float,float,float,float) r4.xyzw, r1.zwzz, t1.xyzw, s1
 108: sample_indexable(texture2d)(float,float,float,float) r1.z, r1.zwzz, t1.xywz, s2
 109: add r1.z, -r1.z, l(0.500000)
 110: div r1.z, r1.z, cb1[1].w
 111: mul r1.z, r1.z, v4.w
 112: mul_sat r1.w, r4.w, l(2.500000)
 113: mad r2.w, r1.w, l(-2.000000), l(3.000000)
 114: mul r1.w, r1.w, r1.w
 115: mul r1.w, r1.w, r2.w
 116: mul r1.w, r2.z, r1.w
 117: dp2 r2.z, r0.xyxx, l(1.000000, -1.000000, 0.000000, 0.000000)
 118: mul r1.w, r1.w, abs(r2.z)
 119: add r7.xy, -r0.xyxx, l(1.000000, 1.000000, 0.000000, 0.000000)
 120: min r0.x, r0.y, r0.x
 121: min r0.y, r7.y, r7.x
 122: mad r1.w, r2.y, r0.y, r1.w
 123: add r7.x, r0.w, r0.z
 124: add r7.z, -r0.w, r0.z
 125: mul r7.xz, r7.xxzx, l(0.500000, 0.000000, 0.500000, 0.000000)
 126: dp2 r0.z, l(1.000000, 1.000000, 0.000000, 0.000000), abs(r7.xzxx)
 127: add r7.y, -r0.z, l(1.000000)
 128: dp3 r0.z, r7.xyzx, r7.xyzx
 129: rsq r0.z, r0.z
 130: mul r7.xyz, r0.zzzz, r7.xyzx
 131: dp3 r0.z, r7.xyzx, r5.xyzx
 132: dp3 r0.w, r7.xyzx, v4.xyzx
 133: add r0.z, -r0.w, r0.z
 134: dp3 r0.w, r7.xyzx, r6.xyzx
 135: div r0.z, r0.z, r0.w
 136: mad r6.xyz, r6.xyzx, r0.zzzz, v4.xyzx
 137: add r5.xyz, -r5.xyzx, r6.xyzx
 138: mul r6.xyz, r7.zxyz, l(0.000000, 1.000000, 0.000000, 0.000000)
 139: mad r6.xyz, r7.xyzx, l(0.000000, 0.000000, 1.000000, 0.000000), -r6.xyzx
 140: dp2 r0.z, r6.yzyy, r6.yzyy
 141: rsq r0.z, r0.z
 142: mul r6.xyz, r0.zzzz, r6.xyzx
 143: mul r8.xyz, r6.xyzx, r7.zxyz
 144: mad r7.xyz, r7.yzxy, r6.yzxy, -r8.xyzx
 145: dp2 r0.z, r6.zyzz, r5.xzxx
 146: dp3 r5.y, r7.xyzx, r5.xyzx
 147: mov r5.x, -r0.z
 148: mad r0.zw, r5.xxxy, cb1[1].wwww, l(0.000000, 0.000000, 0.500000, 0.500000)
 149: lt r2.yw, l(0, 0, 0, 0), r0.zzzw
 150: lt r5.xy, r0.zwzz, l(1.000000, 1.000000, 0.000000, 0.000000)
 151: add r0.zw, r0.zzzw, r1.xxxy
 152: div_sat r0.zw, r0.zzzw, cb1[0].xxxy
 153: and r1.x, r2.y, r5.x
 154: and r1.x, r2.w, r1.x
 155: and r1.x, r5.y, r1.x
 156: and r1.x, r1.x, l(1.000000)
 157: sample_indexable(texture2d)(float,float,float,float) r5.xyzw, r0.zwzz, t1.xyzw, s1
 158: sample_indexable(texture2d)(float,float,float,float) r0.z, r0.zwzz, t1.xywz, s2
 159: add r0.z, -r0.z, l(0.500000)
 160: div r0.z, r0.z, cb1[1].w
 161: mul r0.z, r0.z, v4.w
 162: mul_sat r0.w, r5.w, l(2.500000)
 163: mad r1.y, r0.w, l(-2.000000), l(3.000000)
 164: mul r0.w, r0.w, r0.w
 165: mul r0.w, r0.w, r1.y
 166: mul r0.w, r1.x, r0.w
 167: mad r0.w, r0.w, r0.x, r1.w
 168: add r0.w, r0.w, l(-0.500000)
 169: lt r0.w, r0.w, l(0)
 170: discard_nz r0.w
 171: mul r0.w, r1.z, abs(r2.z)
 172: mul r1.xyz, abs(r2.zzzz), r4.xyzx
 173: mad r1.xyz, r3.xyzx, r0.yyyy, r1.xyzx
 174: mad r0.y, r2.x, r0.y, r0.w
 175: mad r0.y, r0.z, r0.x, r0.y
 176: mad_sat r0.xzw, r5.xxyz, r0.xxxx, r1.xxyz
 177: add r1.z, -r0.y, v3.z
 178: mov r2.x, cb0[46].z
 179: mov r2.y, cb0[47].z
 180: mov r2.z, cb0[48].z
 181: mov r2.w, cb0[49].z
 182: mov r1.xy, v3.xyxx
 183: mov r1.w, l(1.000000)
 184: dp4 r0.y, r2.xyzw, r1.xyzw
 185: mov r1.x, cb0[48].w
 186: mov r1.y, cb0[49].w
 187: dp2 r1.x, r1.xyxx, r1.zwzz
 188: div r0.y, r0.y, r1.x
 189: rcp r1.xy, cb0[5].xyxx
 190: mul r1.xy, r1.xyxx, v0.xyxx
 191: mad r1.y, r1.y, cb0[12].x, cb0[12].y
 192: add r1.z, -r1.y, l(1.000000)
 193: mad r1.xy, r1.xzxx, l(2.000000, 2.000000, 0.000000, 0.000000), l(-1.000000, -1.000000, 0.000000, 0.000000)
 194: mul r2.xyzw, -r1.yyyy, cb0[67].xyzw
 195: mad r1.xyzw, cb0[66].xyzw, r1.xxxx, r2.xyzw
 196: mad r1.xyzw, cb0[68].xyzw, r0.yyyy, r1.xyzw
 197: mov oDepth, r0.y
 198: add r1.xyzw, r1.xyzw, cb0[69].xyzw
 199: div r1.xyz, r1.xyzx, r1.wwww
 200: mul r2.xyzw, cb0[116].xzxz, l(0.500000, 0.500000, -0.500000, -0.500000)
 201: lt r3.xy, r2.xyxx, abs(r1.xzxx)
 202: discard_nz r3.x
 203: discard_nz r3.y
 204: lt r0.y, r1.y, l(0)
 205: discard_nz r0.y
 206: mul r3.xyz, r1.yyyy, cb0[135].xyzx
 207: mad r3.xyz, cb0[134].xyzx, r1.xxxx, r3.xyzx
 208: mad r3.xyz, cb0[136].xyzx, r1.zzzz, r3.xyzx
 209: add r3.xyz, r3.xyzx, cb0[137].xyzx
 210: ge r0.y, l(0), r3.z
 211: ge r1.y, r3.z, l(1.000000)
 212: sample_c_lz(texture2d)(float,float,float,float) r1.w, r3.xyxx, t0.xxxx, s0, r3.z
 213: or r0.y, r0.y, r1.y
 214: movc r0.y, r0.y, l(1.000000), r1.w
 215: div r1.yw, r1.xxxz, cb0[116].xxxz
 216: add_sat r1.yw, r1.yyyw, l(0.000000, 0.500000, 0.000000, 0.500000)
 217: itof r3.xy, cb0[139].xyxx
 218: mad r3.xy, r1.ywyy, r3.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
 219: sample_l(texture2d)(float,float,float,float) r4.xyz, r1.ywyy, t3.xyzw, s3, l(0)
 220: add r4.xyz, r4.xyzx, -cb0[40].xyzx
 221: frc r1.yw, r3.xxxy
 222: round_ni r3.xy, r3.xyxx
 223: ftoi r3.xy, r3.xyxx
 224: iadd r3.zw, r3.xxxy, l(0, 0, 1, 1)
 225: imax r3.zw, r3.zzzw, l(0, 0, 0, 0)
 226: iadd r5.xy, cb0[139].xyxx, l(-1, -1, 0, 0)
 227: imin r3.zw, r3.zzzw, r5.xxxy
 228: imad r3.z, r3.w, cb0[139].x, r3.z
 229: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.zw, r3.z, l(4), t2.xxxy
 230: ushr r3.z, r3.z, l(12)
 231: bfi r3.z, l(12), l(20), r3.w, r3.z
 232: and r3.z, r3.z, l(0x003fffff)
 233: iadd r6.xyzw, r3.xyxy, l(1, 0, 0, 1)
 234: imax r3.xy, r3.xyxx, l(0, 0, 0, 0)
 235: imin r3.xy, r5.xyxx, r3.xyxx
 236: imad r3.x, r3.y, cb0[139].x, r3.x
 237: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xy, r3.x, l(4), t2.xyxx
 238: imax r6.xyzw, r6.xyzw, l(0, 0, 0, 0)
 239: imin r5.xyzw, r5.xyxy, r6.xyzw
 240: imad r5.xy, r5.ywyy, cb0[139].xxxx, r5.xzxx
 241: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r5.yz, r5.y, l(4), t2.xxyx
 242: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r5.xw, r5.x, l(4), t2.xxxy
 243: ushr r3.w, r5.y, l(12)
 244: bfi r3.w, l(12), l(20), r5.z, r3.w
 245: and r3.w, r3.w, l(0x003fffff)
 246: utof r3.zw, r3.zzzw
 247: mul r3.w, r3.w, l(0.000001)
 248: mad r3.z, r3.z, l(0.000001), -r3.w
 249: mad r3.z, r1.y, r3.z, r3.w
 250: ushr r3.w, r5.x, l(12)
 251: bfi r3.w, l(12), l(20), r5.w, r3.w
 252: and r3.w, r3.w, l(0x003fffff)
 253: ushr r3.x, r3.x, l(12)
 254: bfi r3.x, l(12), l(20), r3.y, r3.x
 255: and r3.x, r3.x, l(0x003fffff)
 256: utof r3.xw, r3.xxxw
 257: mul r3.x, r3.x, l(0.000001)
 258: mad r3.y, r3.w, l(0.000001), -r3.x
 259: mad r1.y, r1.y, r3.y, r3.x
 260: add r3.x, -r1.y, r3.z
 261: mad r1.y, r1.w, r3.x, r1.y
 262: mul r1.y, r1.y, l(-0.721348)
 263: exp r1.y, r1.y
 264: mul r0.y, r0.y, r1.y
 265: dp3 r1.y, v2.xyzx, -cb0[123].xyzx
 266: max r1.y, r1.y, l(0)
 267: mul r3.xyz, r1.yyyy, cb0[125].xyzx
 268: dp3 r1.y, v2.xyzx, -cb0[124].xyzx
 269: max r1.y, r1.y, l(0)
 270: mul r5.xyz, r1.yyyy, cb0[126].xyzx
 271: mad r3.xyz, r3.xyzx, r0.yyyy, r5.xyzx
 272: lt r1.yw, r1.xxxz, r2.xxxy
 273: lt r1.xz, r2.zzwz, r1.xxzx
 274: and r0.y, r1.x, r1.y
 275: and r0.y, r1.w, r0.y
 276: and r0.y, r1.z, r0.y
 277: and r0.y, r0.y, l(1.000000)
 278: mad r1.xyz, r0.yyyy, r4.xyzx, cb0[40].xyzx
 279: mul r1.xyz, r0.xzwx, r1.xyzx
 280: mad o0.xyz, r0.xzwx, r3.xyzx, r1.xyzx
 281: mov o0.w, l(1.000000)
 282: ret
