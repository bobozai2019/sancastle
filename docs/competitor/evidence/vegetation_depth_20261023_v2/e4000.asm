Shader hash 86a131bc-8b22430f-1c824efa-97c709a6

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[117], immediateIndexed
      dcl_constantbuffer cb1[3], immediateIndexed
      dcl_sampler s0, mode_default
      dcl_resource_texture2d (float,float,float,float) t0
      dcl_input_ps linear v1.xyz
      dcl_input_ps linear v2.xyz
      dcl_input_ps linear v3.xyz
      dcl_input_ps linear v4.xyzw
      dcl_output oDepth
      dcl_temps 5
   0: mul r0.xy, cb0[116].xzxx, l(0.500000, 0.500000, 0.000000, 0.000000)
   1: lt r0.xy, r0.xyxx, abs(v2.xzxx)
   2: discard_nz r0.x
   3: discard_nz r0.y
   4: lt r0.x, v2.y, l(0)
   5: discard_nz r0.x
   6: dp3 r0.x, v4.xyzx, v4.xyzx
   7: rsq r0.x, r0.x
   8: mul r0.xyz, r0.xxxx, v4.xyzx
   9: dp3 r0.y, l(1.000000, 1.000000, 1.000000, 0.000000), abs(r0.xyzx)
  10: div r0.xy, r0.xzxx, r0.yyyy
  11: add r1.x, r0.y, r0.x
  12: add r1.y, -r0.y, r0.x
  13: mad r0.xy, r1.xyxx, l(0.500000, 0.500000, 0.000000, 0.000000), l(0.500000, 0.500000, 0.000000, 0.000000)
  14: add r0.zw, cb1[0].xxxy, l(0.000000, 0.000000, -1.000000, -1.000000)
  15: mul r0.xy, r0.zwzz, r0.xyxx
  16: round_ni r0.xy, r0.xyxx
  17: div r0.zw, r0.xxxy, r0.zzzw
  18: mad r0.zw, r0.zzzw, l(0.000000, 0.000000, 2.000000, 2.000000), l(0.000000, 0.000000, -1.000000, -1.000000)
  19: add r1.x, r0.w, r0.z
  20: add r1.z, -r0.w, r0.z
  21: mul r1.xz, r1.xxzx, l(0.500000, 0.000000, 0.500000, 0.000000)
  22: dp2 r0.z, l(1.000000, 1.000000, 0.000000, 0.000000), abs(r1.xzxx)
  23: add r1.y, -r0.z, l(1.000000)
  24: dp3 r0.z, r1.xyzx, r1.xyzx
  25: rsq r0.z, r0.z
  26: mul r1.xyz, r0.zzzz, r1.xyzx
  27: dp3 r0.z, r1.xyzx, v4.xyzx
  28: div r2.xyz, cb1[1].xyzx, cb1[1].wwww
  29: dp3 r0.w, r1.xyzx, r2.xyzx
  30: add r0.z, -r0.z, r0.w
  31: add r3.xyz, -v1.xyzx, v4.xyzx
  32: dp3 r0.w, r3.xyzx, r3.xyzx
  33: rsq r0.w, r0.w
  34: mul r3.xyz, r0.wwww, r3.xyzx
  35: dp3 r0.w, r1.xyzx, r3.xyzx
  36: div r0.z, r0.z, r0.w
  37: mad r3.xyz, r3.xyzx, r0.zzzz, v4.xyzx
  38: add r2.xyz, -r2.xyzx, r3.xyzx
  39: mul r3.xyz, r1.zxyz, l(0.000000, 1.000000, 0.000000, 0.000000)
  40: mad r3.xyz, r1.xyzx, l(0.000000, 0.000000, 1.000000, 0.000000), -r3.xyzx
  41: dp2 r0.z, r3.yzyy, r3.yzyy
  42: rsq r0.z, r0.z
  43: mul r3.xyz, r0.zzzz, r3.xyzx
  44: mul r4.xyz, r1.zxyz, r3.xyzx
  45: mad r1.xyz, r1.yzxy, r3.yzxy, -r4.xyzx
  46: dp2 r0.z, r3.zyzz, r2.xzxx
  47: dp3 r1.y, r1.xyzx, r2.xyzx
  48: mov r1.x, -r0.z
  49: mad r0.zw, r1.xxxy, cb1[1].wwww, l(0.000000, 0.000000, 0.500000, 0.500000)
  50: lt r1.xy, l(0, 0, 0, 0), r0.zwzz
  51: lt r1.zw, r0.zzzw, l(0.000000, 0.000000, 1.000000, 1.000000)
  52: add r0.xy, r0.zwzz, r0.xyxx
  53: div_sat r0.xy, r0.xyxx, cb1[0].xyxx
  54: sample_indexable(texture2d)(float,float,float,float) r0.x, r0.xyxx, t0.wxyz, s0
  55: and r0.y, r1.z, r1.x
  56: and r0.y, r1.y, r0.y
  57: and r0.y, r1.w, r0.y
  58: and r0.y, r0.y, l(1.000000)
  59: mul_sat r0.z, r0.x, l(10.000000)
  60: add r0.x, -r0.x, l(0.500000)
  61: div r0.x, r0.x, cb1[1].w
  62: mad r0.w, r0.z, l(-2.000000), l(3.000000)
  63: mul r0.z, r0.z, r0.z
  64: mul r0.z, r0.z, r0.w
  65: mad r0.y, r0.z, r0.y, l(-0.500000)
  66: lt r0.y, r0.y, l(0)
  67: discard_nz r0.y
  68: mul r0.y, v4.w, cb1[2].x
  69: mad r0.x, r0.x, v4.w, r0.y
  70: add r0.z, -r0.x, v3.z
  71: mov r1.x, cb0[46].z
  72: mov r1.y, cb0[47].z
  73: mov r1.z, cb0[48].z
  74: mov r1.w, cb0[49].z
  75: mov r0.xy, v3.xyxx
  76: mov r0.w, l(1.000000)
  77: dp4 r0.x, r1.xyzw, r0.xyzw
  78: mov r1.x, cb0[48].w
  79: mov r1.y, cb0[49].w
  80: dp2 r0.y, r1.xyxx, r0.zwzz
  81: div oDepth, r0.x, r0.y
  82: ret
