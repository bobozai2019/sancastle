Shader hash cc61073d-b16f1f11-f4b1b959-ae177a76

ps_4_0
      dcl_constantbuffer cb0[128], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v2.xyz
      dcl_input_ps linear v3.xyz
      dcl_input_ps linear v4.xy
      dcl_output o0.xyzw
      dcl_temps 4
   0: lt r0.x, v1.y, l(0)
   1: discard_nz r0.x
   2: mul r0.xyz, cb0[125].xyzx, cb0[127].xyzx
   3: mul_sat r0.w, v2.y, l(50.000000)
   4: mad r1.xyz, -cb0[127].xyzx, cb0[125].xyzx, cb0[121].xyzx
   5: mad r0.xyz, r0.wwww, r1.xyzx, r0.xyzx
   6: sample_indexable r1.xyzw, v4.xyxx, t0.xyzw, s0
   7: add r0.w, r1.x, l(-0.500000)
   8: mad_sat r0.w, -r0.w, l(2.000000), l(1.000000)
   9: add r1.xyz, -v1.xyzx, cb0[6].xyzx
  10: dp3 r1.w, r1.xyzx, r1.xyzx
  11: rsq r1.w, r1.w
  12: mul r2.xyz, r1.wwww, r1.xyzx
  13: mad r1.xyz, r1.xyzx, r1.wwww, -cb0[123].xyzx
  14: dp3_sat r1.w, v2.xyzx, r2.xyzx
  15: add r1.w, -r1.w, l(1.000000)
  16: log r1.w, r1.w
  17: mul r2.x, r0.w, r1.w
  18: mul r2.yz, r0.wwww, l(0.000000, 8.000000, 100.000000, 0.000000)
  19: mul r0.w, r1.w, r2.y
  20: exp r0.w, r0.w
  21: mul r3.xyz, r0.wwww, cb0[121].xyzx
  22: mul r0.w, r2.x, l(3.000000)
  23: exp r0.w, r0.w
  24: mul r0.xyz, r0.wwww, r0.xyzx
  25: mad r0.xyz, r3.xyzx, l(0.500000, 0.500000, 0.500000, 0.000000), r0.xyzx
  26: dp3 r0.w, r1.xyzx, r1.xyzx
  27: max r0.w, r0.w, l(0.000000)
  28: rsq r0.w, r0.w
  29: mul r1.xyz, r0.wwww, r1.xyzx
  30: dp3_sat r0.w, v2.xyzx, r1.xyzx
  31: log r0.w, r0.w
  32: mul r0.w, r0.w, r2.z
  33: exp r0.w, r0.w
  34: mad r0.xyz, r0.wwww, cb0[125].xyzx, r0.xyzx
  35: add o0.xyz, r0.xyzx, v3.xyzx
  36: mov o0.w, l(1.000000)
  37: ret
