Shader hash cf0b8d03-7896e51f-9e89f477-f5ee1a16

ps_4_0
      dcl_constantbuffer cb0[143], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.xy
      dcl_output o0.xyzw
      dcl_temps 4
   0: sample_indexable r0.xyzw, v1.xyxx, t0.xyzw, s0
   1: mov r1.x, cb0[142].x
   2: mov r1.yw, l(0, 0, 0, 0)
   3: add r2.xy, r1.xyxx, v1.xyxx
   4: add r1.xy, -r1.xyxx, v1.xyxx
   5: sample_indexable r3.xyzw, r1.xyxx, t0.xyzw, s0
   6: sample_indexable r2.xyzw, r2.xyxx, t0.xyzw, s0
   7: mul r2.xyzw, r2.xyzw, l(0.219000, 0.219000, 0.219000, 0.219000)
   8: mad r0.xyzw, r0.xyzw, l(0.532000, 0.532000, 0.532000, 0.532000), r2.xyzw
   9: mad r0.xyzw, r3.xyzw, l(0.219000, 0.219000, 0.219000, 0.219000), r0.xyzw
  10: mul r1.z, cb0[142].x, l(2.000000)
  11: add r1.xy, r1.zwzz, v1.xyxx
  12: add r1.zw, -r1.zzzw, v1.xxxy
  13: sample_indexable r2.xyzw, r1.zwzz, t0.xyzw, s0
  14: sample_indexable r1.xyzw, r1.xyxx, t0.xyzw, s0
  15: mad r0.xyzw, r1.xyzw, l(0.015000, 0.015000, 0.015000, 0.015000), r0.xyzw
  16: mad o0.xyzw, r2.xyzw, l(0.015000, 0.015000, 0.015000, 0.015000), r0.xyzw
  17: ret
