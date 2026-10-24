Shader hash 671274ca-6c7d9a8f-8ff66c02-334f8f4a

ps_4_0
      dcl_constantbuffer cb0[29], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_texture2d (float,float,float,float) t1
      dcl_input_ps linear v1.xy
      dcl_input_ps linear v2.xyzw
      dcl_output o0.xyzw
      dcl_temps 3
   0: sample_indexable r0.xyzw, v2.xyxx, t1.xyzw, s0
   1: sample_indexable r1.xyzw, v2.zwzz, t1.xyzw, s0
   2: sample_indexable r2.xyzw, v1.xyxx, t1.ywzx, s0
   3: mov r2.x, r0.w
   4: mov r2.y, r1.y
   5: dp4 r0.x, r2.xyzw, l(1.000000, 1.000000, 1.000000, 1.000000)
   6: lt r0.x, r0.x, l(0.000010)
   7: if_nz r0.x
   8:   sample_l o0.xyzw, v1.xyxx, t0.xyzw, s0, l(0)
   9: else
  10:   max r0.x, r0.w, r2.z
  11:   max r0.y, r2.w, r2.y
  12:   lt r0.x, r0.y, r0.x
  13:   and r1.x, r0.w, r0.x
  14:   and r1.z, r2.z, r0.x
  15:   movc r1.yw, r0.xxxx, l(0, 0, 0, 0), r2.yyyw
  16:   movc r2.x, r0.x, r0.w, r2.y
  17:   movc r2.y, r0.x, r2.z, r2.w
  18:   dp2 r0.x, r2.xyxx, l(1.000000, 1.000000, 0.000000, 0.000000)
  19:   div r0.xy, r2.xyxx, r0.xxxx
  20:   mul r2.xyzw, cb0[28].xyxy, l(1.000000, 1.000000, -1.000000, -1.000000)
  21:   mad r1.xyzw, r1.xyzw, r2.xyzw, v1.xyxy
  22:   sample_l r2.xyzw, r1.xyxx, t0.xyzw, s0, l(0)
  23:   sample_l r1.xyzw, r1.zwzz, t0.xyzw, s0, l(0)
  24:   mul r1.xyzw, r0.yyyy, r1.xyzw
  25:   mad o0.xyzw, r0.xxxx, r2.xyzw, r1.xyzw
  26: endif
  27: ret
