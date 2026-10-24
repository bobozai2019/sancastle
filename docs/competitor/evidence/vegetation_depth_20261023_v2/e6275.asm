Shader hash c9b02909-93674206-54f052f7-9799b57c

// Note: shader requires additional functionality:
//       Raw and Structured buffers
//
ps_4_0
      dcl_globalFlags refactoringAllowed, enableRawAndStructuredBuffers
      dcl_constantbuffer cb0[150], immediateIndexed
      dcl_sampler s0, mode_comparison
      dcl_sampler s1, mode_default
      dcl_sampler s2, mode_default
      dcl_sampler s3, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_texture2d (float,float,float,float) t1
      dcl_resource_texture2d (float,float,float,float) t2
      dcl_resource_texture3d (float,float,float,float) t3
      dcl_resource_structured t4, 16
      dcl_resource_structured t5, 16
      dcl_input_ps_siv linear noperspective v0.xy, position
      dcl_input_ps linear v1.xy
      dcl_output o0.xyzw
      dcl_temps 18
   0: sample_indexable r0.xyzw, v1.xyxx, t1.xyzw, s1
   1: mad r0.yz, v1.xxyx, l(0.000000, 2.000000, 2.000000, 0.000000), l(0.000000, -1.000000, -1.000000, 0.000000)
   2: mul r1.xyzw, -r0.zzzz, cb0[67].xyzw
   3: mad r1.xyzw, cb0[66].xyzw, r0.yyyy, r1.xyzw
   4: mad r0.xyzw, cb0[68].xyzw, r0.xxxx, r1.xyzw
   5: add r0.xyzw, r0.xyzw, cb0[69].xyzw
   6: div r0.xyz, r0.xyzx, r0.wwww
   7: add r1.xyz, r0.xyzx, -cb0[6].xyzx
   8: dp3 r0.w, r1.xyzx, r1.xyzx
   9: rsq r0.w, r0.w
  10: mul r1.xyz, r0.wwww, r1.xyzx
  11: add r0.xyz, -r0.xyzx, cb0[6].xyzx
  12: dp3 r0.x, r0.xyzx, r0.xyzx
  13: sqrt r0.x, r0.x
  14: div r0.yzw, l(1.000000, 1.000000, 1.000000, 1.000000), r1.xxyz
  15: mad r2.xyz, -cb0[116].xyzx, l(0.500000, 0.500000, 0.500000, 0.000000), cb0[117].xyzx
  16: add r3.xyz, r2.xyzx, -cb0[6].xyzx
  17: mul r3.xyz, r0.yzwy, r3.xyzx
  18: mad r4.xyz, cb0[116].xyzx, l(0.500000, 0.500000, 0.500000, 0.000000), cb0[117].xyzx
  19: add r5.xyz, r4.xyzx, -cb0[6].xyzx
  20: mul r0.yzw, r0.yyzw, r5.xxyz
  21: min r5.xyz, r0.yzwy, r3.xyzx
  22: max r0.yzw, r0.yyzw, r3.xxyz
  23: max r1.w, r5.y, r5.x
  24: max r3.x, r5.z, r1.w
  25: min r0.y, r0.z, r0.y
  26: min r3.y, r0.w, r0.y
  27: lt r0.y, r3.y, l(0)
  28: lt r0.z, r3.y, r3.x
  29: or r0.y, r0.z, r0.y
  30: movc r0.yz, r0.yyyy, l(0.000000, -1.000000, -1.000000, 0.000000), r3.xxyx
  31: max r0.y, r0.y, l(0.100000)
  32: min r0.x, r0.x, r0.z
  33: add r0.x, -r0.y, r0.x
  34: lt r0.z, r0.x, l(0)
  35: if_nz r0.z
  36:   mov o0.xyzw, l(0, 0, 0, 0)
  37:   ret
  38: endif
  39: sample_indexable r3.xyzw, v1.xyxx, t2.xyzw, s2
  40: max r0.x, r0.x, l(0)
  41: dp3 r0.z, -r1.xyzx, -cb0[123].xyzx
  42: div r0.w, r0.x, cb0[145].y
  43: round_pi r0.w, r0.w
  44: min r0.w, r0.w, cb0[145].z
  45: ftoi r1.w, r0.w
  46: round_z r0.w, r0.w
  47: div r0.x, r0.x, r0.w
  48: itof r5.xy, cb0[139].xyxx
  49: iadd r5.zw, cb0[139].xxxy, l(0, 0, -1, -1)
  50: itof r6.xy, cb0[141].xyxx
  51: iadd r6.zw, cb0[141].xxxy, l(0, 0, -1, -1)
  52: add r0.w, cb0[147].w, cb0[148].x
  53: div r7.xyz, l(400.000000, 400.000000, 400.000000, 0.000000), cb0[146].yzwy
  54: add r2.w, -cb0[148].w, cb0[149].x
  55: mul r7.xyz, r7.xyzx, r7.xyzx
  56: mul r7.xyz, r7.xyzx, r7.xyzx
  57: mad r8.xyz, cb0[148].yyzy, cb0[148].yyzy, l(1.000000, 2.000000, 1.000000, 0.000000)
  58: dp2 r3.w, r0.zzzz, cb0[148].yyyy
  59: add r3.w, -r3.w, r8.x
  60: log r3.w, abs(r3.w)
  61: mul r3.w, r3.w, l(1.500000)
  62: exp r3.w, r3.w
  63: mad r8.xw, -cb0[148].yyyz, cb0[148].yyyz, l(1.000000, 0.000000, 0.000000, 1.000000)
  64: mul r4.w, r8.x, l(3.000000)
  65: mad r7.w, r0.z, r0.z, l(1.000000)
  66: mul r4.w, r4.w, r7.w
  67: mul r3.w, r8.y, r3.w
  68: mul r3.w, r3.w, l(25.132742)
  69: div r3.w, r4.w, r3.w
  70: dp2 r0.z, r0.zzzz, cb0[148].zzzz
  71: add r0.z, -r0.z, r8.z
  72: log r0.z, abs(r0.z)
  73: mul r0.z, r0.z, l(1.500000)
  74: exp r0.z, r0.z
  75: mul r0.z, r0.z, l(12.566371)
  76: div r0.z, r8.w, r0.z
  77: div r8.xyz, l(1.000000, 1.000000, 1.000000, 1.000000), -cb0[123].xyzx
  78: mul r9.xz, cb0[113].zzzz, l(0.010000, 0.000000, 0.005000, 0.000000)
  79: mov r9.y, l(0)
  80: mul r10.xz, cb0[113].zzzz, l(0.010000, 0.000000, 0.005000, 0.000000)
  81: mov r10.y, l(0)
  82: mov r11.xyz, l(0, 0, 0, 0)
  83: mov r4.w, l(1.000000)
  84: mov r7.w, l(0)
  85: loop
  86:   ige r8.w, r7.w, r1.w
  87:   breakc_nz r8.w
  88:   itof r8.w, r7.w
  89:   mad r12.xy, r8.wwww, l(2.083000, 4.867000, 0.000000, 0.000000), v0.xyxx
  90:   dp2 r9.w, r12.xyxx, l(0.067111, 0.005837, 0.000000, 0.000000)
  91:   frc r9.w, r9.w
  92:   mul r9.w, r9.w, l(52.982918)
  93:   frc r9.w, r9.w
  94:   mad r8.w, r9.w, cb0[149].y, r8.w
  95:   mad r8.w, r0.x, r8.w, r0.y
  96:   mul r12.xyz, r1.xyzx, r8.wwww
  97:   mad r13.xyz, r1.xyzx, r8.wwww, cb0[6].xyzx
  98:   div r14.xy, r13.xzxx, cb0[116].xzxx
  99:   add_sat r14.xy, r14.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
 100:   mad r14.zw, r14.xxxy, r5.xxxy, l(0.000000, 0.000000, -0.500000, -0.500000)
 101:   round_ni r15.xy, r14.zwzz
 102:   ftoi r15.xy, r15.xyxx
 103:   frc r14.zw, r14.zzzw
 104:   imax r15.zw, r15.xxxy, l(0, 0, 0, 0)
 105:   imin r15.zw, r5.zzzw, r15.zzzw
 106:   imad r8.w, r15.w, cb0[139].x, r15.z
 107:   ld_structured r16.xy, r8.w, l(8), t4.xyxx
 108:   and r8.w, r16.x, l(0.000000)
 109:   utof r8.w, r8.w
 110:   mul r8.w, r8.w, l(0.000001)
 111:   ushr r9.w, r16.x, l(24)
 112:   ishl r10.w, r16.y, l(8)
 113:   iadd r9.w, r9.w, r10.w
 114:   and r9.w, r9.w, l(0.000000)
 115:   utof r9.w, r9.w
 116:   mul r9.w, r9.w, l(0.000001)
 117:   iadd r16.xyzw, r15.xyxy, l(1, 0, 0, 1)
 118:   imax r16.xyzw, r16.xyzw, l(0, 0, 0, 0)
 119:   imin r16.xyzw, r5.zwzw, r16.xyzw
 120:   imad r15.zw, r16.yyyw, cb0[139].xxxx, r16.xxxz
 121:   ld_structured r16.xy, r15.z, l(8), t4.xyxx
 122:   and r10.w, r16.x, l(0.000000)
 123:   utof r10.w, r10.w
 124:   ushr r11.w, r16.x, l(24)
 125:   ishl r12.w, r16.y, l(8)
 126:   iadd r11.w, r11.w, r12.w
 127:   and r11.w, r11.w, l(0.000000)
 128:   utof r11.w, r11.w
 129:   ld_structured r16.xy, r15.w, l(8), t4.xyxx
 130:   and r12.w, r16.x, l(0.000000)
 131:   utof r12.w, r12.w
 132:   mul r12.w, r12.w, l(0.000001)
 133:   ushr r13.w, r16.x, l(24)
 134:   ishl r15.z, r16.y, l(8)
 135:   iadd r13.w, r13.w, r15.z
 136:   and r13.w, r13.w, l(0.000000)
 137:   utof r13.w, r13.w
 138:   mul r13.w, r13.w, l(0.000001)
 139:   iadd r15.xy, r15.xyxx, l(1, 1, 0, 0)
 140:   imax r15.xy, r15.xyxx, l(0, 0, 0, 0)
 141:   imin r15.xy, r5.zwzz, r15.xyxx
 142:   imad r15.x, r15.y, cb0[139].x, r15.x
 143:   ld_structured r15.xy, r15.x, l(8), t4.xyxx
 144:   and r15.z, r15.x, l(0.000000)
 145:   ushr r15.x, r15.x, l(24)
 146:   ishl r15.y, r15.y, l(8)
 147:   iadd r15.x, r15.y, r15.x
 148:   and r15.x, r15.x, l(0.000000)
 149:   utof r15.xz, r15.xxzx
 150:   mad r10.w, r10.w, l(0.000001), -r8.w
 151:   mad r8.w, r14.z, r10.w, r8.w
 152:   mad r10.w, r11.w, l(0.000001), -r9.w
 153:   mad r9.w, r14.z, r10.w, r9.w
 154:   mad r10.w, r15.z, l(0.000001), -r12.w
 155:   mad r10.w, r14.z, r10.w, r12.w
 156:   mad r11.w, r15.x, l(0.000001), -r13.w
 157:   mad r11.w, r14.z, r11.w, r13.w
 158:   add r10.w, -r8.w, r10.w
 159:   mad r8.w, r14.w, r10.w, r8.w
 160:   add r10.w, -r9.w, r11.w
 161:   mad r9.w, r14.w, r10.w, r9.w
 162:   add r8.w, r8.w, l(-0.050000)
 163:   max r8.w, r8.w, l(0)
 164:   add r8.w, r8.w, r9.w
 165:   lt r8.w, r13.y, r8.w
 166:   if_nz r8.w
 167:     break
 168:   endif
 169:   dp3 r8.w, r12.xyzx, r12.xyzx
 170:   sqrt r8.w, r8.w
 171:   mad r12.xy, r14.xyxx, r6.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
 172:   round_ni r12.zw, r12.xxxy
 173:   ftoi r12.zw, r12.zzzw
 174:   frc r12.xy, r12.xyxx
 175:   imax r14.xy, r12.zwzz, l(0, 0, 0, 0)
 176:   imin r14.xy, r6.zwzz, r14.xyxx
 177:   imad r9.w, r14.y, cb0[141].x, r14.x
 178:   ld_structured r14.xyz, r9.w, l(4), t5.xyzx
 179:   ushr r9.w, r14.x, l(12)
 180:   ushr r10.w, r14.z, l(14)
 181:   ishl r11.w, r14.y, l(20)
 182:   iadd r9.w, r9.w, r11.w
 183:   and r9.w, r9.w, l(0x003fffff)
 184:   utof r9.w, r9.w
 185:   mul r9.w, r9.w, l(0.000001)
 186:   utof r10.w, r10.w
 187:   mul r10.w, r10.w, l(0.000004)
 188:   iadd r14.xyzw, r12.zwzw, l(1, 0, 0, 1)
 189:   imax r14.xyzw, r14.xyzw, l(0, 0, 0, 0)
 190:   imin r14.xyzw, r6.zwzw, r14.xyzw
 191:   imad r14.xy, r14.ywyy, cb0[141].xxxx, r14.xzxx
 192:   ld_structured r15.xyz, r14.x, l(4), t5.xyzx
 193:   ushr r11.w, r15.x, l(12)
 194:   ushr r13.w, r15.z, l(14)
 195:   ishl r14.x, r15.y, l(20)
 196:   iadd r11.w, r11.w, r14.x
 197:   and r11.w, r11.w, l(0x003fffff)
 198:   utof r11.w, r11.w
 199:   utof r13.w, r13.w
 200:   ld_structured r14.xyz, r14.y, l(4), t5.xyzx
 201:   ushr r14.x, r14.x, l(12)
 202:   ushr r14.z, r14.z, l(14)
 203:   ishl r14.y, r14.y, l(20)
 204:   iadd r14.x, r14.y, r14.x
 205:   and r14.x, r14.x, l(0x003fffff)
 206:   utof r14.xy, r14.xzxx
 207:   mul r14.xy, r14.xyxx, l(0.000001, 0.000004, 0.000000, 0.000000)
 208:   iadd r12.zw, r12.zzzw, l(0, 0, 1, 1)
 209:   imax r12.zw, r12.zzzw, l(0, 0, 0, 0)
 210:   imin r12.zw, r6.zzzw, r12.zzzw
 211:   imad r12.z, r12.w, cb0[141].x, r12.z
 212:   ld_structured r15.xyz, r12.z, l(4), t5.xyzx
 213:   ushr r12.z, r15.x, l(12)
 214:   ushr r12.w, r15.z, l(14)
 215:   ishl r14.z, r15.y, l(20)
 216:   iadd r12.z, r12.z, r14.z
 217:   and r12.z, r12.z, l(0x003fffff)
 218:   utof r12.zw, r12.zzzw
 219:   mad r11.w, r11.w, l(0.000001), -r9.w
 220:   mad r9.w, r12.x, r11.w, r9.w
 221:   mad r11.w, r13.w, l(0.000004), -r10.w
 222:   mad r10.w, r12.x, r11.w, r10.w
 223:   mad r11.w, r12.z, l(0.000001), -r14.x
 224:   mad r11.w, r12.x, r11.w, r14.x
 225:   mad r12.z, r12.w, l(0.000004), -r14.y
 226:   mad r12.x, r12.x, r12.z, r14.y
 227:   add r11.w, -r9.w, r11.w
 228:   mad r9.w, r12.y, r11.w, r9.w
 229:   add r11.w, -r10.w, r12.x
 230:   mad r10.w, r12.y, r11.w, r10.w
 231:   add r10.w, r10.w, r10.w
 232:   mul r8.w, r8.w, l(0.010000)
 233:   min r8.w, r8.w, l(1.000000)
 234:   div r11.w, r13.y, cb0[116].y
 235:   mul r11.w, -r11.w, cb0[145].x
 236:   mul r11.w, r11.w, l(1.442695)
 237:   exp r11.w, r11.w
 238:   mul r10.w, r10.w, r11.w
 239:   mul r11.w, r8.w, r10.w
 240:   mul r9.w, r9.w, l(-2.885390)
 241:   exp r9.w, r9.w
 242:   add r9.w, -r9.w, l(1.000000)
 243:   ge r12.x, r9.w, l(0.050000)
 244:   if_nz r12.x
 245:     lt r12.x, r13.y, cb0[148].w
 246:     lt r12.y, cb0[149].x, r13.y
 247:     or r12.x, r12.y, r12.x
 248:     if_z r12.x
 249:       mad r12.xyz, r13.xyzx, l(0.050000, 0.050000, 0.050000, 0.000000), r9.xyzx
 250:       sample_l r12.xyzw, r12.xyzx, t3.xyzw, s3, l(0)
 251:       add r12.y, r13.y, -cb0[148].w
 252:       add_sat r12.y, r12.y, r12.y
 253:       mad r12.z, r12.y, l(-2.000000), l(3.000000)
 254:       mul r12.y, r12.y, r12.y
 255:       mul r12.y, r12.y, r12.z
 256:       mad r12.z, r9.w, r2.w, cb0[148].w
 257:       add r12.w, -r12.z, cb0[148].w
 258:       add r12.z, -r12.z, r13.y
 259:       div r12.w, l(1.000000, 1.000000, 1.000000, 1.000000), r12.w
 260:       mul_sat r12.z, r12.w, r12.z
 261:       mad r12.w, r12.z, l(-2.000000), l(3.000000)
 262:       mul r12.z, r12.z, r12.z
 263:       mul r12.z, r12.z, r12.w
 264:       add r12.w, -r12.x, l(1.000000)
 265:       mad r9.w, r9.w, r12.z, -r12.x
 266:       div r12.x, l(1.000000, 1.000000, 1.000000, 1.000000), r12.w
 267:       mul_sat r9.w, r9.w, r12.x
 268:       mad r12.x, r9.w, l(-2.000000), l(3.000000)
 269:       mul r9.w, r9.w, r9.w
 270:       mul r9.w, r9.w, r12.x
 271:       mul r9.w, r12.y, r9.w
 272:       dp2 r9.w, r9.wwww, r8.wwww
 273:     else
 274:       mov r9.w, l(0)
 275:     endif
 276:   else
 277:     mov r9.w, l(0)
 278:   endif
 279:   mad r8.w, r10.w, r8.w, r9.w
 280:   lt r10.w, r8.w, l(0.010000)
 281:   if_nz r10.w
 282:     iadd r10.w, r7.w, l(1)
 283:     mov r7.w, r10.w
 284:     continue
 285:   endif
 286:   mul r12.xyz, r13.yyyy, cb0[135].xyzx
 287:   mad r12.xyz, cb0[134].xyzx, r13.xxxx, r12.xyzx
 288:   mad r12.xyz, cb0[136].xyzx, r13.zzzz, r12.xyzx
 289:   add r12.xyz, r12.xyzx, cb0[137].xyzx
 290:   sample_c_lz r10.w, r12.xyxx, t0.xxxx, s0, r12.z
 291:   ge r12.x, l(0), r12.z
 292:   ge r12.y, r12.z, l(1.000000)
 293:   or r12.x, r12.y, r12.x
 294:   movc r10.w, r12.x, l(1.000000), r10.w
 295:   mul r12.x, r0.w, -r8.w
 296:   mul r12.x, r0.x, r12.x
 297:   mul r12.x, r12.x, l(1.442695)
 298:   exp r12.x, r12.x
 299:   mul r4.w, r4.w, r12.x
 300:   add r12.xyz, r2.xyzx, -r13.xyzx
 301:   mul r12.xyz, r8.xyzx, r12.xyzx
 302:   add r14.xyz, r4.xyzx, -r13.xyzx
 303:   mul r14.xyz, r8.xyzx, r14.xyzx
 304:   min r15.xyz, r12.xyzx, r14.xyzx
 305:   max r12.xyz, r12.xyzx, r14.xyzx
 306:   max r12.w, r15.y, r15.x
 307:   max r12.w, r15.z, r12.w
 308:   min r12.x, r12.y, r12.x
 309:   min r12.x, r12.z, r12.x
 310:   lt r12.y, r12.x, l(0)
 311:   lt r12.z, r12.x, r12.w
 312:   or r12.y, r12.z, r12.y
 313:   add r12.x, r12.x, l(-0.100000)
 314:   max r12.x, r12.x, l(0)
 315:   movc r12.x, r12.y, l(0), r12.x
 316:   div r12.y, r12.x, cb0[145].w
 317:   round_pi r12.y, r12.y
 318:   min r12.y, r12.y, cb0[146].x
 319:   ftoi r12.z, r12.y
 320:   round_z r12.y, r12.y
 321:   div r12.x, r12.x, r12.y
 322:   mov r12.yw, l(0, 0, 0, 0)
 323:   loop
 324:     ige r13.w, r12.w, r12.z
 325:     breakc_nz r13.w
 326:     itof r13.w, r12.w
 327:     xor r14.x, r7.w, r12.w
 328:     itof r14.x, r14.x
 329:     mad r14.xy, r14.xxxx, l(2.083000, 4.867000, 0.000000, 0.000000), v0.xyxx
 330:     dp2 r14.x, r14.xyxx, l(0.067111, 0.005837, 0.000000, 0.000000)
 331:     frc r14.x, r14.x
 332:     mul r14.x, r14.x, l(52.982918)
 333:     frc r14.x, r14.x
 334:     mad r13.w, r14.x, cb0[149].y, r13.w
 335:     mad r13.w, r12.x, r13.w, l(0.100000)
 336:     mad r14.xyz, -cb0[123].xyzx, r13.wwww, r13.xyzx
 337:     lt r13.w, r14.y, cb0[148].w
 338:     lt r14.w, cb0[149].x, r14.y
 339:     or r13.w, r13.w, r14.w
 340:     if_nz r13.w
 341:       break
 342:     endif
 343:     div r15.xy, r14.xzxx, cb0[116].xzxx
 344:     add_sat r15.xy, r15.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
 345:     mad r15.xy, r15.xyxx, r6.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
 346:     round_ni r15.zw, r15.xxxy
 347:     ftoi r15.zw, r15.zzzw
 348:     frc r15.xy, r15.xyxx
 349:     imax r16.xy, r15.zwzz, l(0, 0, 0, 0)
 350:     imin r16.xy, r6.zwzz, r16.xyxx
 351:     imad r14.w, r16.y, cb0[141].x, r16.x
 352:     ld_structured r16.xy, r14.w, l(4), t5.xyxx
 353:     ushr r14.w, r16.x, l(12)
 354:     ishl r16.x, r16.y, l(20)
 355:     iadd r14.w, r14.w, r16.x
 356:     and r14.w, r14.w, l(0x003fffff)
 357:     utof r14.w, r14.w
 358:     mul r14.w, r14.w, l(0.000001)
 359:     iadd r16.xyzw, r15.zwzw, l(1, 0, 0, 1)
 360:     imax r16.xyzw, r16.xyzw, l(0, 0, 0, 0)
 361:     imin r16.xyzw, r6.zwzw, r16.xyzw
 362:     imad r16.xy, r16.ywyy, cb0[141].xxxx, r16.xzxx
 363:     ld_structured r17.xy, r16.x, l(4), t5.xyxx
 364:     ushr r16.x, r17.x, l(12)
 365:     ishl r16.z, r17.y, l(20)
 366:     iadd r16.x, r16.z, r16.x
 367:     and r16.x, r16.x, l(0x003fffff)
 368:     ld_structured r17.xy, r16.y, l(4), t5.xyxx
 369:     ushr r16.y, r17.x, l(12)
 370:     ishl r16.z, r17.y, l(20)
 371:     iadd r16.y, r16.z, r16.y
 372:     and r16.y, r16.y, l(0x003fffff)
 373:     utof r16.xy, r16.xyxx
 374:     mul r16.y, r16.y, l(0.000001)
 375:     iadd r15.zw, r15.zzzw, l(0, 0, 1, 1)
 376:     imax r15.zw, r15.zzzw, l(0, 0, 0, 0)
 377:     imin r15.zw, r6.zzzw, r15.zzzw
 378:     imad r15.z, r15.w, cb0[141].x, r15.z
 379:     ld_structured r17.xy, r15.z, l(4), t5.xyxx
 380:     ushr r15.z, r17.x, l(12)
 381:     ishl r15.w, r17.y, l(20)
 382:     iadd r15.z, r15.w, r15.z
 383:     and r15.z, r15.z, l(0x003fffff)
 384:     utof r15.z, r15.z
 385:     mad r15.w, r16.x, l(0.000001), -r14.w
 386:     mad r14.w, r15.x, r15.w, r14.w
 387:     mad r15.z, r15.z, l(0.000001), -r16.y
 388:     mad r15.x, r15.x, r15.z, r16.y
 389:     add r15.x, -r14.w, r15.x
 390:     mad r14.w, r15.y, r15.x, r14.w
 391:     mul r14.w, r14.w, l(-2.885390)
 392:     exp r14.w, r14.w
 393:     add r14.w, -r14.w, l(1.000000)
 394:     ge r15.x, r14.w, l(0.050000)
 395:     if_nz r15.x
 396:       if_z r13.w
 397:         add r15.xyz, r14.xyzx, -cb0[6].xyzx
 398:         dp3 r13.w, r15.xyzx, r15.xyzx
 399:         sqrt r13.w, r13.w
 400:         mad r15.xyz, r14.xyzx, l(0.050000, 0.050000, 0.050000, 0.000000), r10.xyzx
 401:         sample_l r15.xyzw, r15.xyzx, t3.xyzw, s3, l(0)
 402:         add r14.x, r14.y, -cb0[148].w
 403:         add_sat r14.x, r14.x, r14.x
 404:         mad r14.z, r14.x, l(-2.000000), l(3.000000)
 405:         mul r14.x, r14.x, r14.x
 406:         mul r14.x, r14.x, r14.z
 407:         mad r14.z, r14.w, r2.w, cb0[148].w
 408:         add r15.y, -r14.z, cb0[148].w
 409:         add r14.y, -r14.z, r14.y
 410:         div r14.z, l(1.000000, 1.000000, 1.000000, 1.000000), r15.y
 411:         mul_sat r14.y, r14.z, r14.y
 412:         mad r14.z, r14.y, l(-2.000000), l(3.000000)
 413:         mul r14.y, r14.y, r14.y
 414:         mul r14.y, r14.y, r14.z
 415:         mul r13.w, r13.w, l(0.010000)
 416:         min r13.w, r13.w, l(1.000000)
 417:         add r14.z, -r15.x, l(1.000000)
 418:         mad r14.y, r14.w, r14.y, -r15.x
 419:         div r14.z, l(1.000000, 1.000000, 1.000000, 1.000000), r14.z
 420:         mul_sat r14.y, r14.z, r14.y
 421:         mad r14.z, r14.y, l(-2.000000), l(3.000000)
 422:         mul r14.y, r14.y, r14.y
 423:         mul r14.y, r14.y, r14.z
 424:         mul r14.x, r14.x, r14.y
 425:         dp2 r13.w, r14.xxxx, r13.wwww
 426:       else
 427:         mov r13.w, l(0)
 428:       endif
 429:     else
 430:       mov r13.w, l(0)
 431:     endif
 432:     mad r12.y, r13.w, r12.x, r12.y
 433:     iadd r12.w, r12.w, l(1)
 434:   endloop
 435:   mul r12.x, r0.w, -r12.y
 436:   mul r12.xzw, r7.xxyz, r12.xxxx
 437:   mul r12.xzw, r12.xxzw, l(1.442695, 0.000000, 1.442695, 1.442695)
 438:   exp r12.xzw, r12.xxzw
 439:   mul r13.xyz, r11.wwww, r12.xzwx
 440:   mul r13.xyz, r3.wwww, r13.xyzx
 441:   mul r13.xyz, r13.xyzx, cb0[143].xyzx
 442:   mul r12.xzw, r9.wwww, r12.xxzw
 443:   mul r12.xzw, r0.zzzz, r12.xxzw
 444:   mul r12.xzw, r12.xxzw, cb0[144].xxyz
 445:   mul r12.xzw, r12.xxzw, l(10.000000, 0.000000, 10.000000, 10.000000)
 446:   mad r12.xzw, r13.xxyz, l(12.000000, 0.000000, 12.000000, 12.000000), r12.xxzw
 447:   mul r12.xzw, r10.wwww, r12.xxzw
 448:   mul r12.xzw, r12.xxzw, cb0[125].xxyz
 449:   mul r12.xzw, r4.wwww, r12.xxzw
 450:   mul r12.xzw, r12.xxzw, cb0[148].xxxx
 451:   mad r12.xzw, r12.xxzw, r0.xxxx, r11.xxyz
 452:   mul r13.xyz, r8.wwww, cb0[40].xyzx
 453:   mul r13.xyz, r4.wwww, r13.xyzx
 454:   mad r12.xzw, r13.xxyz, r0.xxxx, r12.xxzw
 455:   lt r8.w, r4.w, l(0.020000)
 456:   if_nz r8.w
 457:     mov r11.xyz, r12.xzwx
 458:     mov r4.w, l(0)
 459:     break
 460:   endif
 461:   mov r11.xyz, r12.xzwx
 462:   iadd r7.w, r7.w, l(1)
 463: endloop
 464: mad o0.xyz, r3.xyzx, r4.wwww, r11.xyzx
 465: add o0.w, -r4.w, l(1.000000)
 466: ret
