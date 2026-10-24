Shader hash 9a7846c6-b09bb6e6-36fe8515-6de4fde0

ps_4_0
      dcl_constantbuffer cb0[29], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_texture2d (float,float,float,float) t1
      dcl_resource_texture2d (float,float,float,float) t2
      dcl_input_ps linear v1.xy
      dcl_input_ps linear v1.zw
      dcl_input_ps linear v2.xyzw
      dcl_input_ps linear v3.xyzw
      dcl_input_ps linear v4.xyzw
      dcl_output o0.xyzw
      dcl_temps 7
   0: sample_indexable r0.xyzw, v1.xyxx, t0.xyzw, s0
   1: lt r0.y, l(0), r0.y
   2: if_nz r0.y
   3:   lt r0.y, l(0), r0.x
   4:   if_nz r0.y
   5:     mul r1.xy, cb0[28].xyxx, l(-1.000000, 1.000000, 0.000000, 0.000000)
   6:     mov r1.z, l(1.000000)
   7:     mov r2.xy, v1.xyxx
   8:     mov r3.x, l(0)
   9:     mov r2.z, l(-1.000000)
  10:     mov r4.x, l(1.000000)
  11:     loop
  12:       lt r0.y, r2.z, l(7.000000)
  13:       lt r0.z, l(0.900000), r4.x
  14:       and r0.y, r0.z, r0.y
  15:       breakc_z r0.y
  16:       add r2.xyz, r1.xyzx, r2.xyzx
  17:       sample_l r3.xyzw, r2.xyxx, t0.yxzw, s0, l(0)
  18:       dp2 r4.x, r3.yxyy, l(0.500000, 0.500000, 0.000000, 0.000000)
  19:     endloop
  20:     lt r0.y, l(0.900000), r3.x
  21:     and r0.y, r0.y, l(1.000000)
  22:     add r1.x, r0.y, r2.z
  23:   else
  24:     mov r1.x, l(0)
  25:     mov r4.x, l(0)
  26:   endif
  27:   mul r0.yz, cb0[28].xxyx, l(0.000000, 1.000000, -1.000000, 0.000000)
  28:   mov r0.w, l(1.000000)
  29:   mov r2.yz, v1.xxyx
  30:   mov r2.xw, l(-1.000000, 0.000000, 0.000000, 1.000000)
  31:   loop
  32:     lt r3.x, r2.x, l(7.000000)
  33:     lt r3.y, l(0.900000), r2.w
  34:     and r3.x, r3.y, r3.x
  35:     breakc_z r3.x
  36:     add r2.xyz, r0.wyzw, r2.xyzx
  37:     sample_l r3.xyzw, r2.yzyy, t0.xyzw, s0, l(0)
  38:     dp2 r2.w, r3.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
  39:   endloop
  40:   mov r4.y, r2.w
  41:   add r0.y, r1.x, r2.x
  42:   lt r0.y, l(2.000000), r0.y
  43:   if_nz r0.y
  44:     add r1.y, -r1.x, l(0.250000)
  45:     mad r1.zw, r2.xxxx, l(0.000000, 0.000000, 1.000000, -1.000000), l(0.000000, 0.000000, 0.000000, -0.250000)
  46:     mad r2.xyzw, r1.yxzw, cb0[28].xyxy, v1.xyxy
  47:     sample_l(-1,0,0) r3.xyzw, r2.xyxx, t0.xyzw, s0, l(0)
  48:     sample_l(1,0,0) r2.xyzw, r2.zwzz, t0.xyzw, s0, l(0)
  49:     mov r3.z, r2.x
  50:     mad r0.yz, r3.xxzx, l(0.000000, 5.000000, 5.000000, 0.000000), l(0.000000, -3.750000, -3.750000, 0.000000)
  51:     mul r0.yz, abs(r0.yyzy), r3.xxzx
  52:     round_ne r0.yz, r0.yyzy
  53:     round_ne r1.y, r3.y
  54:     round_ne r1.w, r2.y
  55:     mad r0.yz, r1.yywy, l(0.000000, 2.000000, 2.000000, 0.000000), r0.yyzy
  56:     ge r1.yw, r4.xxxy, l(0.000000, 0.900000, 0.000000, 0.900000)
  57:     movc r0.yz, r1.yywy, l(0, 0, 0, 0), r0.yyzy
  58:     mad r0.yz, r0.yyzy, l(0.000000, 20.000000, 20.000000, 0.000000), r1.xxzx
  59:     mad r0.yz, r0.yyzy, l(0.000000, 0.006250, 0.001786, 0.000000), l(0.000000, 0.503125, 0.000893, 0.000000)
  60:     sample_l r1.xyzw, r0.yzyy, t1.xyzw, s0, l(0)
  61:   else
  62:     mov r1.xy, l(0, 0, 0, 0)
  63:   endif
  64:   mad r0.y, cb0[28].x, l(0.250000), v1.x
  65:   mov r2.xy, -cb0[28].xyxx
  66:   mov r2.z, l(1.000000)
  67:   mov r3.y, r0.y
  68:   mov r3.z, v1.y
  69:   mov r3.xw, l(1.000000, 0.000000, 0.000000, -1.000000)
  70:   loop
  71:     lt r0.z, r3.w, l(7.000000)
  72:     lt r0.w, l(0.900000), r3.x
  73:     and r0.z, r0.w, r0.z
  74:     breakc_z r0.z
  75:     add r3.yzw, r2.xxyz, r3.yyzw
  76:     sample_l r4.xyzw, r3.yzyy, t0.xyzw, s0, l(0)
  77:     mad r0.z, r4.x, l(5.000000), l(-3.750000)
  78:     mul r0.z, abs(r0.z), r4.x
  79:     round_ne r5.x, r0.z
  80:     round_ne r5.y, r4.y
  81:     dp2 r3.x, r5.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000)
  82:   endloop
  83:   mov r2.x, r3.w
  84:   sample_l(1,0,0) r4.xyzw, v1.xyxx, t0.xyzw, s0, l(0)
  85:   lt r0.z, l(0), r4.x
  86:   if_nz r0.z
  87:     mov r4.xy, cb0[28].xyxx
  88:     mov r4.z, l(1.000000)
  89:     mov r5.x, r0.y
  90:     mov r5.y, v1.y
  91:     mov r0.z, l(0)
  92:     mov r5.z, l(-1.000000)
  93:     mov r3.y, l(1.000000)
  94:     loop
  95:       lt r1.z, r5.z, l(7.000000)
  96:       lt r1.w, l(0.900000), r3.y
  97:       and r1.z, r1.w, r1.z
  98:       breakc_z r1.z
  99:       add r5.xyz, r4.xyzx, r5.xyzx
 100:       sample_l r6.xyzw, r5.xyxx, t0.xyzw, s0, l(0)
 101:       mad r1.z, r6.x, l(5.000000), l(-3.750000)
 102:       mul r1.z, abs(r1.z), r6.x
 103:       round_ne r0.w, r1.z
 104:       round_ne r0.z, r6.y
 105:       dp2 r3.y, r0.wzww, l(0.500000, 0.500000, 0.000000, 0.000000)
 106:     endloop
 107:     lt r0.y, l(0.900000), r0.z
 108:     and r0.y, r0.y, l(1.000000)
 109:     add r2.z, r0.y, r5.z
 110:   else
 111:     mov r2.z, l(0)
 112:     mov r3.y, l(0)
 113:   endif
 114:   add r0.y, r2.z, r2.x
 115:   lt r0.y, l(2.000000), r0.y
 116:   if_nz r0.y
 117:     mov r2.y, -r2.x
 118:     mad r4.xyzw, r2.yyzz, cb0[28].xyxy, v1.xyxy
 119:     sample_l(-1,0,0) r5.xyzw, r4.xyxx, t0.xyzw, s0, l(0)
 120:     sample_l(0,-1,0) r6.xyzw, r4.xyxx, t0.yzxw, s0, l(0)
 121:     sample_l(1,0,0) r4.xyzw, r4.zwzz, t0.xyzw, s0, l(0)
 122:     mov r6.x, r5.y
 123:     mov r6.yw, r4.yyyx
 124:     mad r0.yz, r6.xxyx, l(0.000000, 2.000000, 2.000000, 0.000000), r6.zzwz
 125:     ge r1.zw, r3.xxxy, l(0.000000, 0.000000, 0.900000, 0.900000)
 126:     movc r0.yz, r1.zzwz, l(0, 0, 0, 0), r0.yyzy
 127:     mad r0.yz, r0.yyzy, l(0.000000, 20.000000, 20.000000, 0.000000), r2.xxzx
 128:     mad r0.yz, r0.yyzy, l(0.000000, 0.006250, 0.001786, 0.000000), l(0.000000, 0.503125, 0.000893, 0.000000)
 129:     sample_l r2.xyzw, r0.yzyy, t1.xyzw, s0, l(0)
 130:     add r1.xy, r1.xyxx, r2.yxyy
 131:   endif
 132:   eq r0.y, -r1.y, r1.x
 133:   if_nz r0.y
 134:     mov r2.xy, v2.xyxx
 135:     mov r2.z, l(1.000000)
 136:     mov r3.x, l(0)
 137:     loop
 138:       lt r0.y, v4.x, r2.x
 139:       lt r0.z, l(0.828100), r2.z
 140:       and r0.y, r0.z, r0.y
 141:       eq r0.z, r3.x, l(0)
 142:       and r0.y, r0.z, r0.y
 143:       breakc_z r0.y
 144:       sample_l r3.xyzw, r2.xyxx, t0.xyzw, s0, l(0)
 145:       mad r2.xy, cb0[28].xyxx, l(-2.000000, -0.000000, 0.000000, 0.000000), r2.xyxx
 146:       mov r2.z, r3.y
 147:     endloop
 148:     mov r3.yz, r2.xxzx
 149:     mad r0.yz, r3.xxzx, l(0.000000, 0.500000, -2.000000, 0.000000), l(0.000000, 0.007813, 2.031250, 0.000000)
 150:     sample_l r2.xyzw, r0.yzyy, t2.xyzw, s0, l(0)
 151:     mad r0.y, r2.w, l(-2.007874), l(3.250000)
 152:     mad r2.x, cb0[28].x, r0.y, r3.y
 153:     mov r2.y, v3.y
 154:     sample_l r3.xyzw, r2.xyxx, t0.xyzw, s0, l(0)
 155:     mov r4.xy, v2.zwzz
 156:     mov r4.z, l(1.000000)
 157:     mov r5.x, l(0)
 158:     loop
 159:       lt r0.y, r4.x, v4.y
 160:       lt r0.z, l(0.828100), r4.z
 161:       and r0.y, r0.z, r0.y
 162:       eq r0.z, r5.x, l(0)
 163:       and r0.y, r0.z, r0.y
 164:       breakc_z r0.y
 165:       sample_l r5.xyzw, r4.xyxx, t0.xyzw, s0, l(0)
 166:       mad r4.xy, cb0[28].xyxx, l(2.000000, 0.000000, 0.000000, 0.000000), r4.xyxx
 167:       mov r4.z, r5.y
 168:     endloop
 169:     mov r5.yz, r4.xxzx
 170:     mad r0.yz, r5.xxzx, l(0.000000, 0.500000, -2.000000, 0.000000), l(0.000000, 0.523438, 2.031250, 0.000000)
 171:     sample_l r4.xyzw, r0.yzyy, t2.xyzw, s0, l(0)
 172:     mad r0.y, r4.w, l(-2.007874), l(3.250000)
 173:     mad r2.z, -cb0[28].x, r0.y, r5.y
 174:     mad r4.xyzw, cb0[28].zzzz, r2.zxzx, -v1.zzzz
 175:     round_ne r4.xyzw, r4.xyzw
 176:     sqrt r0.yz, abs(r4.wwzw)
 177:     sample_l(1,0,0) r5.xyzw, r2.zyzz, t0.yxzw, s0, l(0)
 178:     mov r5.x, r3.x
 179:     mul r1.zw, r5.xxxy, l(0.000000, 0.000000, 4.000000, 4.000000)
 180:     round_ne r1.zw, r1.zzzw
 181:     mad r0.yz, r1.zzwz, l(0.000000, 16.000000, 16.000000, 0.000000), r0.yyzy
 182:     mad r0.yz, r0.yyzy, l(0.000000, 0.006250, 0.001786, 0.000000), l(0.000000, 0.003125, 0.000893, 0.000000)
 183:     sample_l r3.xyzw, r0.yzyy, t1.xyzw, s0, l(0)
 184:     ge r4.xyzw, abs(r4.xyzw), abs(r4.wzwz)
 185:     and r4.xyzw, r4.xyzw, l(1.000000, 1.000000, 0.750000, 0.750000)
 186:     add r0.y, r4.y, r4.x
 187:     div r0.yz, r4.zzwz, r0.yyyy
 188:     mov r2.w, v1.y
 189:     sample_l(0,1,0) r4.xyzw, r2.xwxx, t0.xyzw, s0, l(0)
 190:     mad r0.w, -r0.y, r4.x, l(1.000000)
 191:     sample_l(1,1,0) r4.xyzw, r2.zwzz, t0.xyzw, s0, l(0)
 192:     mad_sat r4.x, -r0.z, r4.x, r0.w
 193:     sample_l(0,-2,0) r5.xyzw, r2.xwxx, t0.xyzw, s0, l(0)
 194:     mad r0.y, -r0.y, r5.x, l(1.000000)
 195:     sample_l(1,-2,0) r2.xyzw, r2.zwzz, t0.xyzw, s0, l(0)
 196:     mad_sat r4.y, -r0.z, r2.x, r0.y
 197:     mul o0.xy, r3.xyxx, r4.xyxx
 198:   else
 199:     mov o0.xy, r1.xyxx
 200:     mov r0.x, l(0)
 201:   endif
 202: else
 203:   mov o0.xy, l(0, 0, 0, 0)
 204: endif
 205: lt r0.x, l(0), r0.x
 206: if_nz r0.x
 207:   mov r0.xy, v3.xyxx
 208:   mov r0.z, l(1.000000)
 209:   mov r1.x, l(0)
 210:   loop
 211:     lt r0.w, v4.z, r0.y
 212:     lt r2.x, l(0.828100), r0.z
 213:     and r0.w, r0.w, r2.x
 214:     eq r2.x, r1.x, l(0)
 215:     and r0.w, r0.w, r2.x
 216:     breakc_z r0.w
 217:     sample_l r1.xyzw, r0.xyxx, t0.yxzw, s0, l(0)
 218:     mad r0.xy, cb0[28].xyxx, l(-0.000000, -2.000000, 0.000000, 0.000000), r0.xyxx
 219:     mov r0.z, r1.y
 220:   endloop
 221:   mov r1.yz, r0.yyzy
 222:   mad r0.xy, r1.xzxx, l(0.500000, -2.000000, 0.000000, 0.000000), l(0.007813, 2.031250, 0.000000, 0.000000)
 223:   sample_l r0.xyzw, r0.xyxx, t2.xyzw, s0, l(0)
 224:   mad r0.x, r0.w, l(-2.007874), l(3.250000)
 225:   mad r0.x, cb0[28].y, r0.x, r1.y
 226:   mov r0.y, v2.x
 227:   sample_l r1.xyzw, r0.yxyy, t0.xyzw, s0, l(0)
 228:   mov r2.xy, v3.zwzz
 229:   mov r2.z, l(1.000000)
 230:   mov r3.x, l(0)
 231:   loop
 232:     lt r1.x, r2.y, v4.w
 233:     lt r1.z, l(0.828100), r2.z
 234:     and r1.x, r1.z, r1.x
 235:     eq r1.z, r3.x, l(0)
 236:     and r1.x, r1.z, r1.x
 237:     breakc_z r1.x
 238:     sample_l r3.xyzw, r2.xyxx, t0.yxzw, s0, l(0)
 239:     mad r2.xy, cb0[28].xyxx, l(0.000000, 2.000000, 0.000000, 0.000000), r2.xyxx
 240:     mov r2.z, r3.y
 241:   endloop
 242:   mov r3.yz, r2.yyzy
 243:   mad r1.xz, r3.xxzx, l(0.500000, 0.000000, -2.000000, 0.000000), l(0.523438, 0.000000, 2.031250, 0.000000)
 244:   sample_l r2.xyzw, r1.xzxx, t2.xyzw, s0, l(0)
 245:   mad r1.x, r2.w, l(-2.007874), l(3.250000)
 246:   mad r0.z, -cb0[28].y, r1.x, r3.y
 247:   mad r2.xyzw, cb0[28].wwww, r0.zxzx, -v1.wwww
 248:   round_ne r2.xyzw, r2.xyzw
 249:   sqrt r1.xz, abs(r2.wwzw)
 250:   sample_l(0,1,0) r3.xyzw, r0.yzyy, t0.xyzw, s0, l(0)
 251:   mov r3.x, r1.y
 252:   mul r1.yw, r3.xxxy, l(0.000000, 4.000000, 0.000000, 4.000000)
 253:   round_ne r1.yw, r1.yyyw
 254:   mad r1.xy, r1.ywyy, l(16.000000, 16.000000, 0.000000, 0.000000), r1.xzxx
 255:   mad r1.xy, r1.xyxx, l(0.006250, 0.001786, 0.000000, 0.000000), l(0.003125, 0.000893, 0.000000, 0.000000)
 256:   sample_l r1.xyzw, r1.xyxx, t1.xyzw, s0, l(0)
 257:   ge r2.xyzw, abs(r2.xyzw), abs(r2.wzwz)
 258:   and r2.xyzw, r2.xyzw, l(1.000000, 1.000000, 0.750000, 0.750000)
 259:   add r0.y, r2.y, r2.x
 260:   div r1.zw, r2.zzzw, r0.yyyy
 261:   mov r0.w, v1.x
 262:   sample_l(1,0,0) r2.xyzw, r0.wxww, t0.xyzw, s0, l(0)
 263:   mad r0.y, -r1.z, r2.y, l(1.000000)
 264:   sample_l(1,1,0) r2.xyzw, r0.wzww, t0.xyzw, s0, l(0)
 265:   mad_sat r2.z, -r1.w, r2.y, r0.y
 266:   sample_l(-2,0,0) r3.xyzw, r0.wxww, t0.xyzw, s0, l(0)
 267:   mad r0.x, -r1.z, r3.y, l(1.000000)
 268:   sample_l(-2,1,0) r3.xyzw, r0.wzww, t0.xyzw, s0, l(0)
 269:   mad_sat r2.w, -r1.w, r3.y, r0.x
 270:   mul o0.zw, r1.xxxy, r2.zzzw
 271: else
 272:   mov o0.zw, l(0, 0, 0, 0)
 273: endif
 274: ret
