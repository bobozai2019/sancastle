Shader hash 4153a597-bcae864b-8f9b3739-84805f34

ps_4_0
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.zw
      dcl_output o0.xyzw
      dcl_temps 3
   0: sample_indexable r0.xyzw, v1.zwzz, t0.xyzw, s0
   1: lt r1.xyzw, r0.xyzw, l(0, 0, 0, 0)
   2: lt r2.xyzw, l(0, 0, 0, 0), r0.xyzw
   3: or r1.xyzw, r1.xyzw, r2.xyzw
   4: eq r2.xyzw, r0.xyzw, l(0, 0, 0, 0)
   5: or r1.xyzw, r1.xyzw, r2.xyzw
   6: ieq r1.xyzw, r1.xyzw, l(0, 0, 0, 0)
   7: or r1.x, r1.y, r1.x
   8: or r1.x, r1.z, r1.x
   9: or r1.x, r1.w, r1.x
  10: movc o0.xyzw, r1.xxxx, l(0, 0, 0, 0), r0.xyzw
  11: ret
