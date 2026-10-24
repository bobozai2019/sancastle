Shader hash ea79ba0a-0e09f3c7-c618c05f-451df96e

ps_4_0
      dcl_constantbuffer cb0[31], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_sampler s1, mode_default
      dcl_sampler s2, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_texture2d (float,float,float,float) t1
      dcl_resource_texture2d (float,float,float,float) t2
      dcl_input_ps linear v1.zw
      dcl_output o0.xyzw
      dcl_temps 3
   0: sample_indexable r0.xyzw, v1.zwzz, t1.xyzw, s1
   1: add r0.x, r0.x, l(-0.500000)
   2: add r0.x, r0.x, r0.x
   3: add r0.y, cb0[28].y, cb0[28].y
   4: mad r0.x, r0.x, cb0[30].z, -r0.y
   5: div r0.y, l(1.000000, 1.000000, 1.000000, 1.000000), r0.y
   6: mul_sat r0.x, r0.y, r0.x
   7: mad r0.y, r0.x, l(-2.000000), l(3.000000)
   8: mul r0.x, r0.x, r0.x
   9: mul r0.z, r0.x, r0.y
  10: sample_indexable r1.xyzw, v1.zwzz, t2.xyzw, s2
  11: mad r0.x, r0.y, r0.x, r1.w
  12: mad r0.x, -r0.z, r1.w, r0.x
  13: max r0.y, r1.y, r1.x
  14: max r1.w, r1.z, r0.y
  15: sample_indexable r2.xyzw, v1.zwzz, t0.xyzw, s0
  16: add r1.xyzw, r1.xyzw, -r2.xyzw
  17: mad o0.xyzw, r0.xxxx, r1.xyzw, r2.xyzw
  18: ret
