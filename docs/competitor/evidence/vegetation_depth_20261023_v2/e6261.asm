Shader hash cfcd0af5-798b242f-ebdc7d73-e442c782

ps_4_0
      dcl_sampler s0, mode_default
      dcl_sampler s1, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_resource_texture2d (float,float,float,float) t1
      dcl_input_ps linear v1.xy
      dcl_output o0.xyzw
      dcl_temps 2
   0: sample_indexable r0.xyzw, v1.xyxx, t1.xyzw, s1
   1: ge r0.x, r0.x, l(0.050000)
   2: and r0.x, r0.x, l(1.000000)
   3: sample_indexable r1.xyzw, v1.xyxx, t0.xyzw, s0
   4: add r0.y, -r1.x, l(1.000000)
   5: mul o0.xyzw, r0.yyyy, r0.xxxx
   6: ret
