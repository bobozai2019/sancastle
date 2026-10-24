Shader hash 1661279f-f3be97a4-605d09c2-a3c7137f

ps_4_0
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.xy
      dcl_input_ps linear v2.xyzw
      dcl_input_ps linear v3.xyzw
      dcl_input_ps linear v4.xyzw
      dcl_output o0.xyzw
      dcl_temps 6
   0: sample_indexable r0.xyzw, v1.xyxx, t0.xyzw, s0
   1: sample_indexable r1.xyzw, v2.xyxx, t0.xyzw, s0
   2: add r2.xyz, r0.xyzx, -r1.xyzx
   3: max r0.w, abs(r2.y), abs(r2.x)
   4: max r2.x, abs(r2.z), r0.w
   5: sample_indexable r3.xyzw, v2.zwzz, t0.xyzw, s0
   6: add r4.xyz, r0.xyzx, -r3.xyzx
   7: max r0.w, abs(r4.y), abs(r4.x)
   8: max r2.y, abs(r4.z), r0.w
   9: ge r2.zw, r2.xxxy, l(0.000000, 0.000000, 0.100000, 0.100000)
  10: and r2.zw, r2.zzzw, l(0.000000, 0.000000, 1.000000, 1.000000)
  11: dp2 r0.w, r2.zwzz, l(1.000000, 1.000000, 0.000000, 0.000000)
  12: eq r0.w, r0.w, l(0)
  13: discard_nz r0.w
  14: sample_indexable r4.xyzw, v3.xyxx, t0.xyzw, s0
  15: add r4.xyz, r0.xyzx, -r4.xyzx
  16: max r0.w, abs(r4.y), abs(r4.x)
  17: max r4.x, abs(r4.z), r0.w
  18: sample_indexable r5.xyzw, v3.zwzz, t0.xyzw, s0
  19: add r0.xyz, r0.xyzx, -r5.xyzx
  20: max r0.x, abs(r0.y), abs(r0.x)
  21: max r4.y, abs(r0.z), r0.x
  22: max r0.xy, r2.xyxx, r4.xyxx
  23: sample_indexable r4.xyzw, v4.xyxx, t0.xyzw, s0
  24: add r1.xyz, r1.xyzx, -r4.xyzx
  25: max r0.z, abs(r1.y), abs(r1.x)
  26: max r1.x, abs(r1.z), r0.z
  27: sample_indexable r4.xyzw, v4.zwzz, t0.xyzw, s0
  28: add r3.xyz, r3.xyzx, -r4.xyzx
  29: max r0.z, abs(r3.y), abs(r3.x)
  30: max r1.y, abs(r3.z), r0.z
  31: max r0.xy, r0.xyxx, r1.xyxx
  32: max r0.x, r0.y, r0.x
  33: add r0.yz, r2.xxyx, r2.xxyx
  34: ge r0.xy, r0.yzyy, r0.xxxx
  35: and r0.xy, r0.xyxx, l(1.000000, 1.000000, 0.000000, 0.000000)
  36: mul r0.xy, r0.xyxx, r2.zwzz
  37: mov o0.xy, r0.xyxx
  38: mov o0.zw, l(0, 0, 0, 0)
  39: ret
