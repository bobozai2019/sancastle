Shader hash 36fb0bef-ead2b7f9-c8612f85-ca4ddb4e

ps_4_0
      dcl_constantbuffer cb0[4], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.xyzw
      dcl_input_ps linear v2.xy
      dcl_output o0.xyzw
      dcl_temps 3
   0: mul r0.x, v1.w, l(255.000000)
   1: round_ne r0.x, r0.x
   2: mul r0.w, r0.x, l(0.003922)
   3: sample_indexable r1.xyzw, v2.xyxx, t0.xyzw, s0
   4: add r1.xyzw, r1.xyzw, cb0[3].xyzw
   5: mad r2.x, r0.w, r1.w, l(-0.001000)
   6: lt r2.x, r2.x, l(0)
   7: discard_nz r2.x
   8: mov r0.xyz, v1.xyzx
   9: mul r0.xyzw, r0.xyzw, r1.xyzw
  10: mul o0.xyz, r0.wwww, r0.xyzx
  11: mov o0.w, r0.w
  12: ret
