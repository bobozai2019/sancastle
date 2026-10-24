Shader hash cbb52986-03569b8e-96354194-8bc59fff

ps_4_0
      dcl_constantbuffer cb0[43], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_sampler s1, mode_default
      dcl_sampler s2, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_texture2d (float,float,float,float) t1
      dcl_resource_texture2d (float,float,float,float) t2
      dcl_input_ps linear v1.xy
      dcl_input_ps linear v1.zw
      dcl_output o0.xyzw
      dcl_temps 4
   0: sample_indexable r0.xyzw, v1.xyxx, t1.xyzw, s1
   1: sample_indexable r1.xyzw, v1.zwzz, t0.xyzw, s0
   2: mul r0.xyz, r0.xxxx, r1.xyzx
   3: lt r0.w, cb0[40].y, l(0.500000)
   4: if_nz r0.w
   5:   add r1.xy, v1.xyxx, -cb0[38].xyxx
   6:   mul r1.yz, abs(r1.yyxy), cb0[39].xxxx
   7:   div r0.w, cb0[22].x, cb0[22].y
   8:   add r0.w, r0.w, l(-1.000000)
   9:   mad r0.w, cb0[39].w, r0.w, l(1.000000)
  10:   mul r1.x, r0.w, r1.z
  11:   mov_sat r1.xy, r1.xyxx
  12:   log r1.xy, r1.xyxx
  13:   mul r1.xy, r1.xyxx, cb0[39].zzzz
  14:   exp r1.xy, r1.xyxx
  15:   dp2 r0.w, r1.xyxx, r1.xyxx
  16:   add r0.w, -r0.w, l(1.000000)
  17:   max r0.w, r0.w, l(0)
  18:   log r0.w, r0.w
  19:   mul r0.w, r0.w, cb0[39].y
  20:   exp r0.w, r0.w
  21:   add r1.xyz, -cb0[37].xyzx, l(1.000000, 1.000000, 1.000000, 0.000000)
  22:   mad r1.xyz, r0.wwww, r1.xyzx, cb0[37].xyzx
  23:   mul r2.xyz, r0.xyzx, r1.xyzx
  24:   add r1.x, r1.w, l(-1.000000)
  25:   mad r2.w, r0.w, r1.x, l(1.000000)
  26: else
  27:   sample_indexable r3.xyzw, v1.xyxx, t2.xyzw, s2
  28:   mul r0.w, r3.w, l(0.077399)
  29:   add r1.x, r3.w, l(0.055000)
  30:   mul r1.x, r1.x, l(0.947867)
  31:   max r1.x, abs(r1.x), l(0.000000)
  32:   log r1.x, r1.x
  33:   mul r1.x, r1.x, l(2.400000)
  34:   exp r1.x, r1.x
  35:   ge r1.y, l(0.040450), r3.w
  36:   movc r0.w, r1.y, r0.w, r1.x
  37:   add r1.xyz, -cb0[37].xyzx, l(1.000000, 1.000000, 1.000000, 0.000000)
  38:   mad r1.xyz, r0.wwww, r1.xyzx, cb0[37].xyzx
  39:   mad r1.xyz, r0.xyzx, r1.xyzx, -r0.xyzx
  40:   mad r2.xyz, cb0[40].xxxx, r1.xyzx, r0.xyzx
  41:   add r0.x, r1.w, l(-1.000000)
  42:   mad r2.w, r0.w, r0.x, l(1.000000)
  43: endif
  44: lt r0.x, l(0.500000), cb0[42].x
  45: if_nz r0.x
  46:   mov_sat r0.xyz, r2.xyzx
  47:   dp3 r2.w, r0.xyzx, l(0.212673, 0.715152, 0.072175, 0.000000)
  48: endif
  49: mov o0.xyzw, r2.xyzw
  50: ret
