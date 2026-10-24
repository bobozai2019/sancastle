Shader hash 265ac06a-9f9b9cd9-ba123701-80c359b1

ps_5_0
      dcl_globalFlags refactoringAllowed
      dcl_input_ps linear v1.xy
      dcl_output o0.xyzw
      dcl_temps 1
   0: add r0.xy, v1.xyxx, l(-0.500000, -0.500000, 0.000000, 0.000000)
   1: dp2 r0.x, r0.xyxx, r0.xyxx
   2: sqrt r0.x, r0.x
   3: add r0.x, -r0.x, l(0.400000)
   4: lt r0.x, r0.x, l(0)
   5: discard_nz r0.x
   6: mov o0.xyzw, l(0, 0, 0, 0)
   7: ret
