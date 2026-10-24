Shader hash b1501689-61df01f4-c1b5ae2e-223a5599

// Note: shader requires additional functionality:
//       Typed UAV Load Additional Formats
//
cs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[140], immediateIndexed
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_uav_typed_texture2d (float,float,float,float) u0
      dcl_input vThreadID.xy
      dcl_temps 20
      dcl_thread_group 32, 32, 1
   0: imad r0.x, cb0[138].x, vThreadID.y, vThreadID.x
   1: itof r0.yz, cb0[138].xxyx
   2: div r1.xy, cb0[116].xzxx, r0.yzyy
   3: div r1.xy, l(1.000000, 1.000000, 1.000000, 1.000000), r1.xyxx
   4: iadd r2.xyzw, vThreadID.xyxy, l(1, 0, -1, 0)
   5: mov r3.xy, r2.zwzz
   6: mov r3.zw, l(0, 0, 0, 0)
   7: ld_indexable(texture2d)(float,float,float,float) r0.w, r3.xyzw, t0.xyzw
   8: mov r2.zw, l(0, 0, 0, 0)
   9: ld_indexable(texture2d)(float,float,float,float) r1.z, r2.xyzw, t0.xywz
  10: iadd r2.xyzw, vThreadID.xyxy, l(0, 1, 0, -1)
  11: mov r3.xy, r2.zwzz
  12: mov r3.zw, l(0, 0, 0, 0)
  13: ld_indexable(texture2d)(float,float,float,float) r1.w, r3.xyzw, t0.xyzw
  14: mov r2.zw, l(0, 0, 0, 0)
  15: ld_indexable(texture2d)(float,float,float,float) r2.x, r2.xyzw, t0.wxyz
  16: add r3.x, r0.w, -r1.z
  17: add r3.y, r1.w, -r2.x
  18: mul r1.xy, r1.xyxx, r3.xyxx
  19: mul r1.xy, r1.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
  20: mov r1.z, l(1.000000)
  21: dp3 r0.w, r1.xyzx, r1.xyzx
  22: rsq r0.w, r0.w
  23: mul r1.xyzw, r0.wwww, r1.xxyy
  24: dp2 r0.w, r1.ywyy, r1.ywyy
  25: add r0.w, -r0.w, l(1.000000)
  26: sqrt r0.w, r0.w
  27: mul r1.xyzw, r1.xyzw, l(1.000000, 0.000000, 0.000000, 1.000000)
  28: add r1.xyz, r1.zzwz, r1.xyyx
  29: mad r1.xyz, r0.wwww, l(0.000000, 1.000000, 0.000000, 0.000000), r1.xyzx
  30: mov r2.xy, vThreadID.xyxx
  31: mov r2.zw, l(0, 0, 0, 0)
  32: ld_indexable(texture2d)(float,float,float,float) r2.y, r2.xyzw, t0.xwyz
  33: itof r3.xy, vThreadID.xyxx
  34: add r4.xyzw, r3.xyxy, l(0.500000, 0.500000, 1.000000, 1.000000)
  35: div_sat r3.zw, r4.xxxy, r0.yyyz
  36: add r3.zw, r3.zzzw, l(0.000000, 0.000000, -0.500000, -0.500000)
  37: mul r2.xz, r3.zzwz, cb0[116].xxzx
  38: div r3.zw, l(1.000000, 1.000000, 1.000000, 1.000000), r0.yyyz
  39: mul r3.zw, r3.zzzw, cb0[116].xxxz
  40: mov r5.y, vThreadID.y
  41: mov r6.x, vThreadID.x
  42: mov r7.xyz, l(0, 0, 0, 0)
  43: mov r0.w, cb0[139].y
  44: mov r1.w, l(0)
  45: loop
  46:   ige r2.w, r1.w, cb0[139].x
  47:   breakc_nz r2.w
  48:   imul null, r2.w, r0.x, r1.w
  49:   imul null, r2.w, r2.w, cb0[113].w
  50:   xor r4.x, r2.w, l(61)
  51:   ushr r4.y, r2.w, l(16)
  52:   xor r4.x, r4.y, r4.x
  53:   imul null, r4.x, r4.x, l(9)
  54:   ushr r7.w, r4.x, l(4)
  55:   xor r4.x, r4.x, r7.w
  56:   imul null, r4.x, r4.x, l(0.000000)
  57:   ushr r7.w, r4.x, l(15)
  58:   xor r4.x, r4.x, r7.w
  59:   bfi r4.x, l(23), l(0), r4.x, l(1.000000)
  60:   add r4.x, r4.x, l(-1.000000)
  61:   xor r2.w, r2.w, r4.y
  62:   xor r2.w, r2.w, l(0x005b5c68)
  63:   imul null, r2.w, r2.w, l(9)
  64:   ushr r4.y, r2.w, l(4)
  65:   xor r2.w, r2.w, r4.y
  66:   imul null, r2.w, r2.w, l(0.000000)
  67:   ushr r4.y, r2.w, l(15)
  68:   xor r2.w, r2.w, r4.y
  69:   bfi r2.w, l(23), l(0), r2.w, l(1.000000)
  70:   add r2.w, r2.w, l(-1.000000)
  71:   mad r8.z, -r4.x, l(2.000000), l(1.000000)
  72:   mul r2.w, r2.w, l(6.283185)
  73:   mad r4.x, -r8.z, r8.z, l(1.000000)
  74:   sqrt r4.x, r4.x
  75:   sincos r9.x, r10.x, r2.w
  76:   mul r8.x, r4.x, r10.x
  77:   mul r8.y, r4.x, r9.x
  78:   add r8.xyz, r1.xyzx, r8.xyzx
  79:   dp3 r2.w, r8.xyzx, r8.xyzx
  80:   rsq r2.w, r2.w
  81:   mul r8.xyz, r2.wwww, r8.xyzx
  82:   dp2 r2.w, r8.xzxx, r8.xzxx
  83:   rsq r2.w, r2.w
  84:   mul r4.xy, r2.wwww, r8.xzxx
  85:   max r4.xy, abs(r4.xyxx), l(0.000000, 0.000000, 0.000000, 0.000000)
  86:   div r4.xy, l(1.000000, 1.000000, 1.000000, 1.000000), r4.xyxx
  87:   lt r9.xyzw, l(0, 0, 0, 0), r8.xzxz
  88:   movc r10.xy, r9.xyxx, r4.zwzz, r3.xyxx
  89:   add r10.xy, r10.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
  90:   div_sat r10.xy, r10.xyxx, r0.yzyy
  91:   add r10.xy, r10.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
  92:   lt r10.zw, r8.xxxz, l(0, 0, 0, 0)
  93:   iadd r11.xy, -r9.zwzz, r10.zwzz
  94:   mad r9.zw, r10.xxxy, cb0[116].xxxz, -r2.xxxz
  95:   mul r10.xy, r4.xyxx, abs(r9.zwzz)
  96:   mul r10.zw, r3.zzzw, r4.xxxy
  97:   lt r2.w, r10.x, r10.y
  98:   iadd r12.xy, r11.xyxx, vThreadID.xyxx
  99:   mad r9.zw, abs(r9.zzzw), r4.xxxy, r10.zzzw
 100:   mov r5.x, r12.x
 101:   mov r5.z, r9.z
 102:   mov r5.w, r10.y
 103:   mov r6.y, r12.y
 104:   mov r6.z, r10.x
 105:   mov r6.w, r9.w
 106:   movc r12.xyzw, r2.wwww, r5.xyzw, r6.xyzw
 107:   mov r13.xy, r11.xyxx
 108:   mov r13.zw, r12.zzzw
 109:   mov r15.xy, r12.xyxx
 110:   mov r5.xz, r10.zzwz
 111:   mov r2.w, r0.w
 112:   mov r5.w, l(0)
 113:   mov r6.yz, l(0, 0, 0, 0)
 114:   mov r14.xyzw, l(0, 0, 0, 0)
 115:   loop
 116:     ige r6.w, r5.w, l(256)
 117:     breakc_nz r6.w
 118:     iadd r6.w, r5.w, l(1)
 119:     iadd r6.z, r6.z, l(1)
 120:     ishr r9.zw, cb0[138].xxxy, r6.yyyy
 121:     imax r9.zw, r9.zzzw, l(0, 0, 1, 1)
 122:     itof r10.xy, r15.xyxx
 123:     add r10.xy, r10.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
 124:     itof r16.xy, r9.zwzz
 125:     div_sat r10.xy, r10.xyxx, r16.xyxx
 126:     add r10.xy, r10.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
 127:     mul r16.xz, r10.xxyx, cb0[116].xxzx
 128:     mov r17.xy, r15.xyxx
 129:     mov r17.zw, r6.yyyy
 130:     ld_indexable(texture2d)(float,float,float,float) r18.xyzw, r17.xyzw, t0.xyzw
 131:     mov r16.y, r18.w
 132:     add r19.xyz, -r2.xyzx, r16.xyzx
 133:     dp3 r7.w, r19.xyzx, r19.xyzx
 134:     rsq r7.w, r7.w
 135:     mul r19.xyz, r7.wwww, r19.xyzx
 136:     dp3 r19.x, r19.xyzx, r1.xyzx
 137:     lt r7.w, r14.x, r19.x
 138:     add r8.w, -r14.x, r19.x
 139:     mad r19.yzw, r18.xxyz, r8.wwww, r14.yyzw
 140:     movc r18.xyzw, r7.wwww, r19.xyzw, r14.xyzw
 141:     ilt r7.w, r2.w, r6.z
 142:     if_nz r7.w
 143:       iadd r7.w, r6.y, l(1)
 144:       ishr r10.xy, cb0[138].xyxx, r7.wwww
 145:       imax r10.xy, r10.xyxx, l(1, 1, 0, 0)
 146:       ishr r16.yw, r15.xxxy, l(0, 1, 0, 1)
 147:       itof r10.xy, r10.xyxx
 148:       div r17.zw, l(1.000000, 1.000000, 1.000000, 1.000000), r10.xxxy
 149:       mul r17.zw, r17.zzzw, cb0[116].xxxz
 150:       itof r19.xy, r16.ywyy
 151:       add r19.zw, r19.xxxy, l(0.000000, 0.000000, 1.000000, 1.000000)
 152:       movc r19.xy, r9.xyxx, r19.zwzz, r19.xyxx
 153:       add r19.xy, r19.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
 154:       div_sat r10.xy, r19.xyxx, r10.xyxx
 155:       add r10.xy, r10.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
 156:       mad r10.xy, r10.xyxx, cb0[116].xzxx, -r16.xzxx
 157:       mul r11.zw, r4.xxxy, abs(r10.xxxy)
 158:       mul r10.xy, r4.xyxx, r17.zwzz
 159:       mov r13.xyzw, r11.xyzw
 160:       mov r5.w, r6.w
 161:       mov r6.z, l(0)
 162:       mov r14.xyzw, r18.xyzw
 163:       mov r6.y, r7.w
 164:       mov r15.xy, r16.ywyy
 165:       mov r5.xz, r10.xxyx
 166:       continue
 167:     endif
 168:     lt r7.w, r13.z, r13.w
 169:     iadd r10.xy, r13.xyxx, r15.xyxx
 170:     add r16.xw, r5.xxxz, r13.zzzw
 171:     mov r19.x, r10.x
 172:     mov r19.y, r17.y
 173:     mov r19.z, r16.x
 174:     mov r19.w, r13.w
 175:     mov r16.x, r17.x
 176:     mov r16.y, r10.y
 177:     mov r16.z, r13.z
 178:     movc r15.xyzw, r7.wwww, r19.xyzw, r16.xyzw
 179:     ilt r10.xy, r15.xyxx, l(0, 0, 0, 0)
 180:     or r7.w, r10.y, r10.x
 181:     ige r9.zw, r15.xxxy, r9.zzzw
 182:     or r8.w, r9.w, r9.z
 183:     or r7.w, r7.w, r8.w
 184:     if_nz r7.w
 185:       mov r14.xyzw, r18.xyzw
 186:       break
 187:     endif
 188:     mov r13.zw, r15.zzzw
 189:     mov r5.w, r6.w
 190:     mov r14.xyzw, r18.xyzw
 191:   endloop
 192:   add_sat r2.w, -r14.x, l(1.000000)
 193:   dp3 r4.x, -cb0[123].xyzx, r8.xyzx
 194:   max r4.x, r4.x, l(0)
 195:   mul r4.y, r4.x, r4.x
 196:   mul r4.y, r4.y, r4.y
 197:   mul r4.x, r4.y, r4.x
 198:   mad r5.xzw, r4.xxxx, cb0[125].xxyz, cb0[40].xxyz
 199:   mad r5.xzw, r5.xxzw, r2.wwww, r14.yyzw
 200:   add r7.xyz, r5.xzwx, r7.xyzx
 201:   iadd r1.w, r1.w, l(1)
 202: endloop
 203: ld_uav_typed(texture2d)(float,float,float,float) r0.xyzw, vThreadID.xyyy, u0.xyzw
 204: itof r1.x, cb0[139].x
 205: div r1.xyz, r7.xyzx, r1.xxxx
 206: mov r1.w, l(1.000000)
 207: add r1.xyzw, -r0.xyzw, r1.xyzw
 208: mad r0.xyzw, cb0[139].zzzz, r1.xyzw, r0.xyzw
 209: store_uav_typed u0.xyzw, vThreadID.xyyy, r0.xyzw
 210: ret
