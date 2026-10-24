Shader hash 6daca57c-b70c880f-ded4fabf-db7395b7

cs_5_0
      dcl_globalFlags refactoringAllowed
      dcl_constantbuffer cb0[151], dynamicIndexed
      dcl_uav_structured u0, 4
      dcl_uav_structured u1, 4
      dcl_uav_structured u2, 4
      dcl_uav_structured u3, 4
      dcl_uav_structured u4, 16
      dcl_input vThreadID.x
      dcl_temps 2
      dcl_thread_group 1024, 1, 1
   0: uge r0.x, vThreadID.x, cb0[138].x
   1: if_nz r0.x
   2:   ret
   3: endif
   4: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.xyzw, vThreadID.x, l(0), u4.xyzw
   5: mul r0.x, r0.x, l(-5.770780)
   6: exp r0.x, r0.x
   7: add r0.x, -r0.x, l(1.000000)
   8: ge r0.x, r0.x, l(0.200000)
   9: mov r1.xy, l(0, 0, 0, 0)
  10: loop
  11:   ige r1.z, r1.x, l(6)
  12:   mov r1.y, l(0)
  13:   breakc_nz r1.z
  14:   dp3 r1.z, cb0[r1.x + 139].xyzx, r0.yzwy
  15:   add r1.z, r1.z, cb0[r1.x + 139].w
  16:   lt r1.z, r1.z, l(0)
  17:   if_nz r1.z
  18:     mov r1.y, l(-1)
  19:     break
  20:   endif
  21:   iadd r1.x, r1.x, l(1)
  22:   mov r1.xy, r1.xzxx
  23: endloop
  24: not r1.x, r1.y
  25: and r1.x, r0.x, r1.x
  26: if_nz r1.x
  27:   imm_atomic_iadd r1.x, u2, l(1, 0, 0, 0), l(1)
  28:   store_structured u0.x, r1.x, l(0), vThreadID.x
  29: endif
  30: mov r1.xy, l(0, 0, 0, 0)
  31: loop
  32:   ige r1.z, r1.x, l(6)
  33:   mov r1.y, l(0)
  34:   breakc_nz r1.z
  35:   dp3 r1.z, cb0[r1.x + 145].xyzx, r0.yzwy
  36:   add r1.z, r1.z, cb0[r1.x + 145].w
  37:   lt r1.z, r1.z, l(0)
  38:   if_nz r1.z
  39:     mov r1.y, l(-1)
  40:     break
  41:   endif
  42:   iadd r1.x, r1.x, l(1)
  43:   mov r1.xy, r1.xzxx
  44: endloop
  45: not r0.y, r1.y
  46: and r0.x, r0.y, r0.x
  47: if_nz r0.x
  48:   imm_atomic_iadd r0.x, u3, l(1, 0, 0, 0), l(1)
  49:   store_structured u1.x, r0.x, l(0), vThreadID.x
  50: endif
  51: ret
