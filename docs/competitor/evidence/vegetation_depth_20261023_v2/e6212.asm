Shader hash da279a36-05494c91-49af2d54-83645f12

ps_4_0
      dcl_constantbuffer cb0[13], immediateIndexed
      dcl_constantbuffer cb1[2], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps_siv linear noperspective v0.xyz, position
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v2.xy
      dcl_output o0.xyzw
      dcl_temps 1
   0: div r0.xy, l(1.000000, 1.000000, 1.000000, 1.000000), cb0[5].xyxx
   1: mul r0.xy, r0.xyxx, v0.xyxx
   2: mad r0.y, r0.y, cb0[12].x, cb0[12].y
   3: add r0.z, -r0.y, l(1.000000)
   4: sample_indexable r0.xyzw, r0.xzxx, t0.xyzw, s0
   5: mad r0.x, cb0[9].z, r0.x, cb0[9].w
   6: div r0.x, l(1.000000, 1.000000, 1.000000, 1.000000), r0.x
   7: mad r0.y, cb0[9].z, v0.z, cb0[9].w
   8: div r0.y, l(1.000000, 1.000000, 1.000000, 1.000000), r0.y
   9: add r0.x, -r0.y, r0.x
  10: mul r0.y, cb1[1].z, l(0.250000)
  11: div_sat r0.x, r0.x, r0.y
  12: add r0.yz, v2.xxyx, l(0.000000, -0.500000, -0.500000, 0.000000)
  13: dp2 r0.y, r0.yzyy, r0.yzyy
  14: sqrt r0.y, r0.y
  15: add r0.y, r0.y, r0.y
  16: min r0.y, r0.y, l(1.000000)
  17: add r0.y, -r0.y, l(1.000000)
  18: log r0.y, r0.y
  19: mul r0.y, r0.y, cb1[1].y
  20: exp r0.y, r0.y
  21: mad r0.z, r0.y, r0.x, l(-0.002000)
  22: mul r0.x, r0.x, r0.y
  23: mul r0.xyw, r0.xxxx, v1.xyxz
  24: mul o0.xyz, r0.xywx, cb1[1].xxxx
  25: lt r0.x, r0.z, l(0)
  26: discard_nz r0.x
  27: mov o0.w, l(1.000000)
  28: ret
