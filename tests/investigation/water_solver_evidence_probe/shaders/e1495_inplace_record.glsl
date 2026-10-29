#[compute]
#version 450
// Mechanical packed-uint lowering of frozen original DXBC, not original HLSL.
// Same logical in-place water alias and 32x32 threads. No intra-dispatch barrier added.
layout(local_size_x=32,local_size_y=32,local_size_z=1) in;
layout(set=0,binding=0,std430) buffer Water {uvec4 waterCells[];};
layout(set=0,binding=1,std430) readonly buffer Constants {uvec4 constants[];};
float dx_dp2(vec4 a,vec4 b){precise float m0=a.x*b.x;precise float m1=a.y*b.y;precise float sum=m0+m1;return sum;}
float dx_dp3(vec4 a,vec4 b){precise float m0=a.x*b.x;precise float m1=a.y*b.y;precise float m2=a.z*b.z;precise float sum=m0+m1;precise float total=sum+m2;return total;}
layout(set=0,binding=5,std430) buffer StreamOutput {uvec4 observedStream[];};
void main(){
 uvec4 vThreadID=uvec4(gl_GlobalInvocationID,0u);
 uvec4 r0=uvec4(0u);
 uvec4 r1=uvec4(0u);
 uvec4 r2=uvec4(0u);
 uvec4 r3=uvec4(0u);
 uvec4 r4=uvec4(0u);
 uvec4 r5=uvec4(0u);
 uvec4 r6=uvec4(0u);
 uvec4 r7=uvec4(0u);

 // DXBC 0: iadd r0.xyzw, vThreadID.xyxy, l(0xffffffff, 0x00000000, 0x00000001, 0x00000000)
 uvec4 t0=(vThreadID.xyxy+uvec4(0xffffffffu,0x00000000u,0x00000001u,0x00000000u));
 r0.xyzw=t0.xyzw;
 // DXBC 1: imax r0.x, r0.x, l(0x00000000)
 uvec4 t1=uvec4(max(ivec4(uvec4(r0.x)),ivec4(uvec4(0x00000000u))));
 r0.x=t1.x;
 // DXBC 2: iadd r1.xy, cb0[155].xyxx, l(0xffffffff, 0xffffffff, 0x00000000, 0x00000000)
 uvec4 t2=(constants[155].xyxx+uvec4(0xffffffffu,0xffffffffu,0x00000000u,0x00000000u));
 r1.xy=t2.xy;
 // DXBC 3: imin r0.xy, r0.xyxx, r1.xyxx
 uvec4 t3=uvec4(min(ivec4(r0.xyxx),ivec4(r1.xyxx)));
 r0.xy=t3.xy;
 // DXBC 4: imad r0.x, r0.y, cb0[155].x, r0.x
 uvec4 t4=(uvec4(r0.y)*uvec4(constants[155].x)+uvec4(r0.x));
 r0.x=t4.x;
 // DXBC 5: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xyz, r0.x, l(0x00000000), u0.xyzx
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot5=(vThreadID.y*512u+vThreadID.x)*10u+0u;
 observedStream[streamSlot5]=uvec4((uvec4(r0.x)).x,0u,7u,5u);
 uvec4 cell5=waterCells[(uvec4(r0.x)).x];
 uvec4 t5=uvec4(0u);
 t5.x=cell5.x;
 t5.y=cell5.y;
 t5.z=cell5.z;
 r2.xyz=t5.xyz;
 uvec4 streamValue5=uvec4(0u);
 streamValue5.xyz=r2.xyz;
 observedStream[streamSlot5+1u]=streamValue5;
 // DXBC 6: imin r0.xy, r0.zwzz, r1.xyxx
 uvec4 t6=uvec4(min(ivec4(r0.zwzz),ivec4(r1.xyxx)));
 r0.xy=t6.xy;
 // DXBC 7: imad r0.x, r0.y, cb0[155].x, r0.x
 uvec4 t7=(uvec4(r0.y)*uvec4(constants[155].x)+uvec4(r0.x));
 r0.x=t7.x;
 // DXBC 8: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.x, r0.x, l(0x00000008), u0.xxxx
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot8=(vThreadID.y*512u+vThreadID.x)*10u+2u;
 observedStream[streamSlot8]=uvec4((uvec4(r0.x)).x,8u,1u,8u);
 uvec4 cell8=waterCells[(uvec4(r0.x)).x];
 uvec4 t8=uvec4(0u);
 t8.x=cell8.z;
 r0.x=t8.x;
 uvec4 streamValue8=uvec4(0u);
 streamValue8.x=r0.x;
 observedStream[streamSlot8+1u]=streamValue8;
 // DXBC 9: and r0.x, r0.x, l(0x00ffffff)
 uvec4 t9=(uvec4(r0.x)&uvec4(0x00ffffffu));
 r0.x=t9.x;
 // DXBC 10: utof r0.x, r0.x
 precise vec4 f10=vec4(uvec4(r0.x));
 uvec4 t10=floatBitsToUint(f10);
 r0.x=t10.x;
 // DXBC 11: iadd r3.xyzw, vThreadID.xyxy, l(0x00000000, 0xffffffff, 0x00000000, 0x00000001)
 uvec4 t11=(vThreadID.xyxy+uvec4(0x00000000u,0xffffffffu,0x00000000u,0x00000001u));
 r3.xyzw=t11.xyzw;
 // DXBC 12: imax r3.y, r3.y, l(0x00000000)
 uvec4 t12=uvec4(max(ivec4(uvec4(r3.y)),ivec4(uvec4(0x00000000u))));
 r3.y=t12.y;
 // DXBC 13: imin r0.yz, r1.xxyx, r3.zzwz
 uvec4 t13=uvec4(min(ivec4(r1.xxyx),ivec4(r3.zzwz)));
 r0.yz=t13.yz;
 // DXBC 14: imad r0.y, r0.z, cb0[155].x, r0.y
 uvec4 t14=(uvec4(r0.z)*uvec4(constants[155].x)+uvec4(r0.y));
 r0.y=t14.y;
 // DXBC 15: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.y, r0.y, l(0x00000008), u0.xxxx
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot15=(vThreadID.y*512u+vThreadID.x)*10u+4u;
 observedStream[streamSlot15]=uvec4((uvec4(r0.y)).x,8u,2u,15u);
 uvec4 cell15=waterCells[(uvec4(r0.y)).x];
 uvec4 t15=uvec4(0u);
 t15.y=cell15.z;
 r0.y=t15.y;
 uvec4 streamValue15=uvec4(0u);
 streamValue15.y=r0.y;
 observedStream[streamSlot15+1u]=streamValue15;
 // DXBC 16: imin r0.zw, r1.xxxy, r3.xxxy
 uvec4 t16=uvec4(min(ivec4(r1.xxxy),ivec4(r3.xxxy)));
 r0.zw=t16.zw;
 // DXBC 17: ige r1.xy, vThreadID.xyxx, r1.xyxx
 uvec4 t17=mix(uvec4(0u),uvec4(0xffffffffu),greaterThanEqual(ivec4(vThreadID.xyxx),ivec4(r1.xyxx)));
 r1.xy=t17.xy;
 // DXBC 18: imad r0.z, r0.w, cb0[155].x, r0.z
 uvec4 t18=(uvec4(r0.w)*uvec4(constants[155].x)+uvec4(r0.z));
 r0.z=t18.z;
 // DXBC 19: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r0.zw, r0.z, l(0x00000004), u0.xxxy
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot19=(vThreadID.y*512u+vThreadID.x)*10u+6u;
 observedStream[streamSlot19]=uvec4((uvec4(r0.z)).x,4u,12u,19u);
 uvec4 cell19=waterCells[(uvec4(r0.z)).x];
 uvec4 t19=uvec4(0u);
 t19.z=cell19.y;
 t19.w=cell19.z;
 r0.zw=t19.zw;
 uvec4 streamValue19=uvec4(0u);
 streamValue19.zw=r0.zw;
 observedStream[streamSlot19+1u]=streamValue19;
 // DXBC 20: and r0.yw, r0.yyyw, l(0x00000000, 0x00ffffff, 0x00000000, 0x00ffffff)
 uvec4 t20=(r0.yyyw&uvec4(0x00000000u,0x00ffffffu,0x00000000u,0x00ffffffu));
 r0.yw=t20.yw;
 // DXBC 21: utof r0.yw, r0.yyyw
 precise vec4 f21=vec4(r0.yyyw);
 uvec4 t21=floatBitsToUint(f21);
 r0.yw=t21.yw;
 // DXBC 22: mul r0.xy, r0.xyxx, l(0x3521999b, 0x3521999b, 0x00000000, 0x00000000)
 precise vec4 f22=(uintBitsToFloat(r0.xyxx)*uintBitsToFloat(uvec4(0x3521999bu,0x3521999bu,0x00000000u,0x00000000u)));
 uvec4 t22=floatBitsToUint(f22);
 r0.xy=t22.xy;
 // DXBC 23: imad r1.z, vThreadID.y, cb0[155].x, vThreadID.x
 uvec4 t23=(uvec4(vThreadID.y)*uvec4(constants[155].x)+uvec4(vThreadID.x));
 r1.z=t23.z;
 // DXBC 24: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xyzw, r1.z, l(0x00000000), u0.xyzw
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot24=(vThreadID.y*512u+vThreadID.x)*10u+8u;
 observedStream[streamSlot24]=uvec4((uvec4(r1.z)).x,0u,15u,24u);
 uvec4 cell24=waterCells[(uvec4(r1.z)).x];
 uvec4 t24=uvec4(0u);
 t24.x=cell24.x;
 t24.y=cell24.y;
 t24.z=cell24.z;
 t24.w=cell24.w;
 r3.xyzw=t24.xyzw;
 uvec4 streamValue24=uvec4(0u);
 streamValue24.xyzw=r3.xyzw;
 observedStream[streamSlot24+1u]=streamValue24;
 // DXBC 25: ushr r1.w, r2.x, l(0x00000010)
 uvec4 t25=(uvec4(r2.x)>>(uvec4(0x00000010u)&uvec4(31u)));
 r1.w=t25.w;
 // DXBC 26: bfi r1.w, l(0x00000010), l(0x00000010), r2.y, r1.w
 uvec4 t26=uvec4(bitfieldInsert((uvec4(r1.w)).x,(uvec4(r2.y)).x,int((uvec4(0x00000010u)).x),int((uvec4(0x00000010u)).x)),bitfieldInsert((uvec4(r1.w)).y,(uvec4(r2.y)).y,int((uvec4(0x00000010u)).y),int((uvec4(0x00000010u)).y)),bitfieldInsert((uvec4(r1.w)).z,(uvec4(r2.y)).z,int((uvec4(0x00000010u)).z),int((uvec4(0x00000010u)).z)),bitfieldInsert((uvec4(r1.w)).w,(uvec4(r2.y)).w,int((uvec4(0x00000010u)).w),int((uvec4(0x00000010u)).w)));
 r1.w=t26.w;
 // DXBC 27: and r2.x, r2.z, l(0x00ffffff)
 uvec4 t27=(uvec4(r2.z)&uvec4(0x00ffffffu));
 r2.x=t27.x;
 // DXBC 28: utof r2.x, r2.x
 precise vec4 f28=vec4(uvec4(r2.x));
 uvec4 t28=floatBitsToUint(f28);
 r2.x=t28.x;
 // DXBC 29: mul r2.y, r2.x, l(0x3521999b)
 precise vec4 f29=(uintBitsToFloat(uvec4(r2.x))*uintBitsToFloat(uvec4(0x3521999bu)));
 uvec4 t29=floatBitsToUint(f29);
 r2.y=t29.y;
 // DXBC 30: and r1.w, r1.w, l(0x00ffffff)
 uvec4 t30=(uvec4(r1.w)&uvec4(0x00ffffffu));
 r1.w=t30.w;
 // DXBC 31: utof r1.w, r1.w
 precise vec4 f31=vec4(uvec4(r1.w));
 uvec4 t31=floatBitsToUint(f31);
 r1.w=t31.w;
 // DXBC 32: mad r2.x, r1.w, l(0x35000001), l(0xc0800000)
 precise vec4 f32=fma(uintBitsToFloat(uvec4(r1.w)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t32=floatBitsToUint(f32);
 r2.x=t32.x;
 // DXBC 33: mov r4.w, l(0x00000000)
 uvec4 t33=uvec4(0x00000000u);
 r4.w=t33.w;
 // DXBC 34: and r5.xyz, r3.xzxx, l(0x000000ff, 0x00ffffff, 0x000000ff, 0x00000000)
 uvec4 t34=(r3.xzxx&uvec4(0x000000ffu,0x00ffffffu,0x000000ffu,0x00000000u));
 r5.xyz=t34.xyz;
 // DXBC 35: utof r5.xyz, r5.xyzx
 precise vec4 f35=vec4(r5.xyzx);
 uvec4 t35=floatBitsToUint(f35);
 r5.xyz=t35.xyz;
 // DXBC 36: mul r4.y, r5.y, l(0x3521999b)
 precise vec4 f36=(uintBitsToFloat(uvec4(r5.y))*uintBitsToFloat(uvec4(0x3521999bu)));
 uvec4 t36=floatBitsToUint(f36);
 r4.y=t36.y;
 // DXBC 37: movc r2.xy, vThreadID.xxxx, r2.xyxx, r4.wyww
 uvec4 t37=mix(r4.wyww,r2.xyxx,notEqual(vThreadID.xxxx,uvec4(0u)));
 r2.xy=t37.xy;
 // DXBC 38: add r1.w, r2.y, l(0xbd4ccccd)
 precise vec4 f38=(uintBitsToFloat(uvec4(r2.y))+uintBitsToFloat(uvec4(0xbd4ccccdu)));
 uvec4 t38=floatBitsToUint(f38);
 r1.w=t38.w;
 // DXBC 39: max r1.w, r1.w, l(0x00000000)
 precise vec4 f39=max(uintBitsToFloat(uvec4(r1.w)),uintBitsToFloat(uvec4(0x00000000u)));
 uvec4 t39=floatBitsToUint(f39);
 r1.w=t39.w;
 // DXBC 40: movc r0.xy, r1.xyxx, r4.yyyy, r0.xyxx
 uvec4 t40=mix(r0.xyxx,r4.yyyy,notEqual(r1.xyxx,uvec4(0u)));
 r0.xy=t40.xy;
 // DXBC 41: add r0.xy, r0.xyxx, l(0xbd4ccccd, 0xbd4ccccd, 0x00000000, 0x00000000)
 precise vec4 f41=(uintBitsToFloat(r0.xyxx)+uintBitsToFloat(uvec4(0xbd4ccccdu,0xbd4ccccdu,0x00000000u,0x00000000u)));
 uvec4 t41=floatBitsToUint(f41);
 r0.xy=t41.xy;
 // DXBC 42: max r0.xy, r0.xyxx, l(0x00000000, 0x00000000, 0x00000000, 0x00000000)
 precise vec4 f42=max(uintBitsToFloat(r0.xyxx),uintBitsToFloat(uvec4(0x00000000u,0x00000000u,0x00000000u,0x00000000u)));
 uvec4 t42=floatBitsToUint(f42);
 r0.xy=t42.xy;
 // DXBC 43: add r1.x, r0.x, r1.w
 precise vec4 f43=(uintBitsToFloat(uvec4(r0.x))+uintBitsToFloat(uvec4(r1.w)));
 uvec4 t43=floatBitsToUint(f43);
 r1.x=t43.x;
 // DXBC 44: ushr r0.z, r0.z, l(0x00000008)
 uvec4 t44=(uvec4(r0.z)>>(uvec4(0x00000008u)&uvec4(31u)));
 r0.z=t44.z;
 // DXBC 45: mul r6.y, r0.w, l(0x3521999b)
 precise vec4 f45=(uintBitsToFloat(uvec4(r0.w))*uintBitsToFloat(uvec4(0x3521999bu)));
 uvec4 t45=floatBitsToUint(f45);
 r6.y=t45.y;
 // DXBC 46: utof r0.z, r0.z
 precise vec4 f46=vec4(uvec4(r0.z));
 uvec4 t46=floatBitsToUint(f46);
 r0.z=t46.z;
 // DXBC 47: mad r6.x, r0.z, l(0x35000001), l(0xc0800000)
 precise vec4 f47=fma(uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(0x35000001u)),uintBitsToFloat(uvec4(0xc0800000u)));
 uvec4 t47=floatBitsToUint(f47);
 r6.x=t47.x;
 // DXBC 48: movc r0.zw, vThreadID.yyyy, r6.xxxy, r4.wwwy
 uvec4 t48=mix(r4.wwwy,r6.xxxy,notEqual(vThreadID.yyyy,uvec4(0u)));
 r0.zw=t48.zw;
 // DXBC 49: add r0.w, r0.w, l(0xbd4ccccd)
 precise vec4 f49=(uintBitsToFloat(uvec4(r0.w))+uintBitsToFloat(uvec4(0xbd4ccccdu)));
 uvec4 t49=floatBitsToUint(f49);
 r0.w=t49.w;
 // DXBC 50: max r0.w, r0.w, l(0x00000000)
 precise vec4 f50=max(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(0x00000000u)));
 uvec4 t50=floatBitsToUint(f50);
 r0.w=t50.w;
 // DXBC 51: add r1.x, r0.w, r1.x
 precise vec4 f51=(uintBitsToFloat(uvec4(r0.w))+uintBitsToFloat(uvec4(r1.x)));
 uvec4 t51=floatBitsToUint(f51);
 r1.x=t51.x;
 // DXBC 52: add r1.x, r0.y, r1.x
 precise vec4 f52=(uintBitsToFloat(uvec4(r0.y))+uintBitsToFloat(uvec4(r1.x)));
 uvec4 t52=floatBitsToUint(f52);
 r1.x=t52.x;
 // DXBC 53: add r1.y, cb0[154].x, cb0[154].x
 precise vec4 f53=(uintBitsToFloat(uvec4(constants[154].x))+uintBitsToFloat(uvec4(constants[154].x)));
 uvec4 t53=floatBitsToUint(f53);
 r1.y=t53.y;
 // DXBC 54: mul r2.y, cb0[157].z, cb0[157].w
 precise vec4 f54=(uintBitsToFloat(uvec4(constants[157].z))*uintBitsToFloat(uvec4(constants[157].w)));
 uvec4 t54=floatBitsToUint(f54);
 r2.y=t54.y;
 // DXBC 55: div r1.y, r1.y, r2.y
 precise vec4 f55=(uintBitsToFloat(uvec4(r1.y))/uintBitsToFloat(uvec4(r2.y)));
 uvec4 t55=floatBitsToUint(f55);
 r1.y=t55.y;
 // DXBC 56: mad r1.x, r1.x, l(0x3e800000), -r1.y
 precise vec4 f56=fma(uintBitsToFloat(uvec4(r1.x)),uintBitsToFloat(uvec4(0x3e800000u)),uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r1.y)))));
 uvec4 t56=floatBitsToUint(f56);
 r1.x=t56.x;
 // DXBC 57: max r1.x, r1.x, l(0x00000000)
 precise vec4 f57=max(uintBitsToFloat(uvec4(r1.x)),uintBitsToFloat(uvec4(0x00000000u)));
 uvec4 t57=floatBitsToUint(f57);
 r1.x=t57.x;
 // DXBC 58: ge r1.y, r2.x, l(0x00000000)
 uvec4 t58=mix(uvec4(0u),uvec4(0xffffffffu),greaterThanEqual(uintBitsToFloat(uvec4(r2.x)),uintBitsToFloat(uvec4(0x00000000u))));
 r1.y=t58.y;
 // DXBC 59: mad r6.xyz, r5.xyzx, l(0x3c008081, 0x3521999b, 0x3f800000, 0x00000000), l(0xbf800000, 0xbd4ccccd, 0x3f000000, 0x00000000)
 precise vec4 f59=fma(uintBitsToFloat(r5.xyzx),uintBitsToFloat(uvec4(0x3c008081u,0x3521999bu,0x3f800000u,0x00000000u)),uintBitsToFloat(uvec4(0xbf800000u,0xbd4ccccdu,0x3f000000u,0x00000000u)));
 uvec4 t59=floatBitsToUint(f59);
 r6.xyz=t59.xyz;
 // DXBC 60: max r2.y, r6.y, l(0x00000000)
 precise vec4 f60=max(uintBitsToFloat(uvec4(r6.y)),uintBitsToFloat(uvec4(0x00000000u)));
 uvec4 t60=floatBitsToUint(f60);
 r2.y=t60.y;
 // DXBC 61: movc r1.y, r1.y, r1.w, r2.y
 uvec4 t61=mix(uvec4(r2.y),uvec4(r1.w),notEqual(uvec4(r1.y),uvec4(0u)));
 r1.y=t61.y;
 // DXBC 62: add r1.y, -r1.x, r1.y
 precise vec4 f62=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r1.x))))+uintBitsToFloat(uvec4(r1.y)));
 uvec4 t62=floatBitsToUint(f62);
 r1.y=t62.y;
 // DXBC 63: mul r1.y, r2.x, r1.y
 precise vec4 f63=(uintBitsToFloat(uvec4(r2.x))*uintBitsToFloat(uvec4(r1.y)));
 uvec4 t63=floatBitsToUint(f63);
 r1.y=t63.y;
 // DXBC 64: ushr r7.xyzw, r3.xyzw, l(0x00000010, 0x00000008, 0x00000018, 0x0000001c)
 uvec4 t64=(r3.xyzw>>(uvec4(0x00000010u,0x00000008u,0x00000018u,0x0000001cu)&uvec4(31u)));
 r7.xyzw=t64.xyzw;
 // DXBC 65: bfi r2.xz, l(0x00000010, 0x00000000, 0x00000018, 0x00000000), l(0x00000010, 0x00000000, 0x00000008, 0x00000000), r3.yywy, r7.xxzx
 uvec4 t65=uvec4(bitfieldInsert((r7.xxzx).x,(r3.yywy).x,int((uvec4(0x00000010u,0x00000000u,0x00000008u,0x00000000u)).x),int((uvec4(0x00000010u,0x00000000u,0x00000018u,0x00000000u)).x)),bitfieldInsert((r7.xxzx).y,(r3.yywy).y,int((uvec4(0x00000010u,0x00000000u,0x00000008u,0x00000000u)).y),int((uvec4(0x00000010u,0x00000000u,0x00000018u,0x00000000u)).y)),bitfieldInsert((r7.xxzx).z,(r3.yywy).z,int((uvec4(0x00000010u,0x00000000u,0x00000008u,0x00000000u)).z),int((uvec4(0x00000010u,0x00000000u,0x00000018u,0x00000000u)).z)),bitfieldInsert((r7.xxzx).w,(r3.yywy).w,int((uvec4(0x00000010u,0x00000000u,0x00000008u,0x00000000u)).w),int((uvec4(0x00000010u,0x00000000u,0x00000018u,0x00000000u)).w)));
 r2.xz=t65.xz;
 // DXBC 66: utof r3.yz, r7.yywy
 precise vec4 f66=vec4(r7.yywy);
 uvec4 t66=floatBitsToUint(f66);
 r3.yz=t66.yz;
 // DXBC 67: ubfe r3.xw, l(0x00000008, 0x00000000, 0x00000000, 0x00000004), l(0x00000008, 0x00000000, 0x00000000, 0x00000018), r3.xxxw
 uvec4 t67=uvec4(bitfieldExtract((r3.xxxw).x,int((uvec4(0x00000008u,0x00000000u,0x00000000u,0x00000018u)).x),int((uvec4(0x00000008u,0x00000000u,0x00000000u,0x00000004u)).x)),bitfieldExtract((r3.xxxw).y,int((uvec4(0x00000008u,0x00000000u,0x00000000u,0x00000018u)).y),int((uvec4(0x00000008u,0x00000000u,0x00000000u,0x00000004u)).y)),bitfieldExtract((r3.xxxw).z,int((uvec4(0x00000008u,0x00000000u,0x00000000u,0x00000018u)).z),int((uvec4(0x00000008u,0x00000000u,0x00000000u,0x00000004u)).z)),bitfieldExtract((r3.xxxw).w,int((uvec4(0x00000008u,0x00000000u,0x00000000u,0x00000018u)).w),int((uvec4(0x00000008u,0x00000000u,0x00000000u,0x00000004u)).w)));
 r3.xw=t67.xw;
 // DXBC 68: utof r3.xw, r3.xxxw
 precise vec4 f68=vec4(r3.xxxw);
 uvec4 t68=floatBitsToUint(f68);
 r3.xw=t68.xw;
 // DXBC 69: and r2.xz, r2.xxzx, l(0x00ffffff, 0x00000000, 0x00ffffff, 0x00000000)
 uvec4 t69=(r2.xxzx&uvec4(0x00ffffffu,0x00000000u,0x00ffffffu,0x00000000u));
 r2.xz=t69.xz;
 // DXBC 70: utof r2.xz, r2.xxzx
 precise vec4 f70=vec4(r2.xxzx);
 uvec4 t70=floatBitsToUint(f70);
 r2.xz=t70.xz;
 // DXBC 71: mad r2.xw, r2.xxxx, l(0x35000001, 0x00000000, 0x00000000, 0x3f800000), l(0xc0800000, 0x00000000, 0x00000000, 0x3f000000)
 precise vec4 f71=fma(uintBitsToFloat(r2.xxxx),uintBitsToFloat(uvec4(0x35000001u,0x00000000u,0x00000000u,0x3f800000u)),uintBitsToFloat(uvec4(0xc0800000u,0x00000000u,0x00000000u,0x3f000000u)));
 uvec4 t71=floatBitsToUint(f71);
 r2.xw=t71.xw;
 // DXBC 72: add r1.w, r2.z, l(0x3f000000)
 precise vec4 f72=(uintBitsToFloat(uvec4(r2.z))+uintBitsToFloat(uvec4(0x3f000000u)));
 uvec4 t72=floatBitsToUint(f72);
 r1.w=t72.w;
 // DXBC 73: ftou r1.w, r1.w
 uvec4 t73=uvec4(uintBitsToFloat(uvec4(r1.w)));
 r1.w=t73.w;
 // DXBC 74: ge r2.z, l(0x00000000), r2.x
 uvec4 t74=mix(uvec4(0u),uvec4(0xffffffffu),greaterThanEqual(uintBitsToFloat(uvec4(0x00000000u)),uintBitsToFloat(uvec4(r2.x))));
 r2.z=t74.z;
 // DXBC 75: movc r0.x, r2.z, r0.x, r2.y
 uvec4 t75=mix(uvec4(r2.y),uvec4(r0.x),notEqual(uvec4(r2.z),uvec4(0u)));
 r0.x=t75.x;
 // DXBC 76: add r0.x, -r1.x, r0.x
 precise vec4 f76=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r1.x))))+uintBitsToFloat(uvec4(r0.x)));
 uvec4 t76=floatBitsToUint(f76);
 r0.x=t76.x;
 // DXBC 77: mad r0.x, r0.x, r2.x, -r1.y
 precise vec4 f77=fma(uintBitsToFloat(uvec4(r0.x)),uintBitsToFloat(uvec4(r2.x)),uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r1.y)))));
 uvec4 t77=floatBitsToUint(f77);
 r0.x=t77.x;
 // DXBC 78: ge r2.x, r0.z, l(0x00000000)
 uvec4 t78=mix(uvec4(0u),uvec4(0xffffffffu),greaterThanEqual(uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(0x00000000u))));
 r2.x=t78.x;
 // DXBC 79: movc r0.w, r2.x, r0.w, r2.y
 uvec4 t79=mix(uvec4(r2.y),uvec4(r0.w),notEqual(uvec4(r2.x),uvec4(0u)));
 r0.w=t79.w;
 // DXBC 80: add r0.w, -r1.x, r0.w
 precise vec4 f80=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r1.x))))+uintBitsToFloat(uvec4(r0.w)));
 uvec4 t80=floatBitsToUint(f80);
 r0.w=t80.w;
 // DXBC 81: mul r0.z, r0.z, r0.w
 precise vec4 f81=(uintBitsToFloat(uvec4(r0.z))*uintBitsToFloat(uvec4(r0.w)));
 uvec4 t81=floatBitsToUint(f81);
 r0.z=t81.z;
 // DXBC 82: mad r2.xz, r3.yyyy, l(0x35000001, 0x00000000, 0x3f800000, 0x00000000), l(0xc0800000, 0x00000000, 0x3f000000, 0x00000000)
 precise vec4 f82=fma(uintBitsToFloat(r3.yyyy),uintBitsToFloat(uvec4(0x35000001u,0x00000000u,0x3f800000u,0x00000000u)),uintBitsToFloat(uvec4(0xc0800000u,0x00000000u,0x3f000000u,0x00000000u)));
 uvec4 t82=floatBitsToUint(f82);
 r2.xz=t82.xz;
 // DXBC 83: add r0.w, r3.z, l(0x3f000000)
 precise vec4 f83=(uintBitsToFloat(uvec4(r3.z))+uintBitsToFloat(uvec4(0x3f000000u)));
 uvec4 t83=floatBitsToUint(f83);
 r0.w=t83.w;
 // DXBC 84: ftou r0.w, r0.w
 uvec4 t84=uvec4(uintBitsToFloat(uvec4(r0.w)));
 r0.w=t84.w;
 // DXBC 85: ishl r7.w, r0.w, l(0x0000001c)
 uvec4 t85=(uvec4(r0.w)<<(uvec4(0x0000001cu)&uvec4(31u)));
 r7.w=t85.w;
 // DXBC 86: ge r0.w, l(0x00000000), r2.x
 uvec4 t86=mix(uvec4(0u),uvec4(0xffffffffu),greaterThanEqual(uintBitsToFloat(uvec4(0x00000000u)),uintBitsToFloat(uvec4(r2.x))));
 r0.w=t86.w;
 // DXBC 87: movc r0.y, r0.w, r0.y, r2.y
 uvec4 t87=mix(uvec4(r2.y),uvec4(r0.y),notEqual(uvec4(r0.w),uvec4(0u)));
 r0.y=t87.y;
 // DXBC 88: add r0.y, -r1.x, r0.y
 precise vec4 f88=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r1.x))))+uintBitsToFloat(uvec4(r0.y)));
 uvec4 t88=floatBitsToUint(f88);
 r0.y=t88.y;
 // DXBC 89: mad r0.y, r0.y, r2.x, -r0.z
 precise vec4 f89=fma(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(r2.x)),uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r0.z)))));
 uvec4 t89=floatBitsToUint(f89);
 r0.y=t89.y;
 // DXBC 90: ftou r0.z, r2.z
 uvec4 t90=uvec4(uintBitsToFloat(uvec4(r2.z)));
 r0.z=t90.z;
 // DXBC 91: ishl r0.z, r0.z, l(0x00000008)
 uvec4 t91=(uvec4(r0.z)<<(uvec4(0x00000008u)&uvec4(31u)));
 r0.z=t91.z;
 // DXBC 92: mul r0.y, r0.y, cb0[154].w
 precise vec4 f92=(uintBitsToFloat(uvec4(r0.y))*uintBitsToFloat(uvec4(constants[154].w)));
 uvec4 t92=floatBitsToUint(f92);
 r0.y=t92.y;
 // DXBC 93: mad r0.x, r0.x, cb0[154].z, r0.y
 precise vec4 f93=fma(uintBitsToFloat(uvec4(r0.x)),uintBitsToFloat(uvec4(constants[154].z)),uintBitsToFloat(uvec4(r0.y)));
 uvec4 t93=floatBitsToUint(f93);
 r0.x=t93.x;
 // DXBC 94: mad r0.x, -r0.x, cb0[157].z, r4.y
 precise vec4 f94=fma(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r0.x)))),uintBitsToFloat(uvec4(constants[157].z)),uintBitsToFloat(uvec4(r4.y)));
 uvec4 t94=floatBitsToUint(f94);
 r0.x=t94.x;
 // DXBC 95: max r0.x, r0.x, cb0[114].y
 precise vec4 f95=max(uintBitsToFloat(uvec4(r0.x)),uintBitsToFloat(uvec4(constants[114].y)));
 uvec4 t95=floatBitsToUint(f95);
 r0.x=t95.x;
 // DXBC 96: min r0.x, r0.x, cb0[115].y
 precise vec4 f96=min(uintBitsToFloat(uvec4(r0.x)),uintBitsToFloat(uvec4(constants[115].y)));
 uvec4 t96=floatBitsToUint(f96);
 r0.x=t96.x;
 // DXBC 97: mad r0.y, -r5.y, l(0x3521999b), r0.x
 precise vec4 f97=fma(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r5.y)))),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(uvec4(r0.x)));
 uvec4 t97=floatBitsToUint(f97);
 r0.y=t97.y;
 // DXBC 98: mul_sat r0.x, r0.x, l(0x3dcac5b3)
 precise vec4 f98=clamp((uintBitsToFloat(uvec4(r0.x))*uintBitsToFloat(uvec4(0x3dcac5b3u))),vec4(0),vec4(1));
 uvec4 t98=floatBitsToUint(f98);
 r0.x=t98.x;
 // DXBC 99: mad r0.x, r0.x, l(0x4b7fffff), l(0x3f000000)
 precise vec4 f99=fma(uintBitsToFloat(uvec4(r0.x)),uintBitsToFloat(uvec4(0x4b7fffffu)),uintBitsToFloat(uvec4(0x3f000000u)));
 uvec4 t99=floatBitsToUint(f99);
 r0.x=t99.x;
 // DXBC 100: div r0.y, r0.y, cb0[157].z
 precise vec4 f100=(uintBitsToFloat(uvec4(r0.y))/uintBitsToFloat(uvec4(constants[157].z)));
 uvec4 t100=floatBitsToUint(f100);
 r0.y=t100.y;
 // DXBC 101: mad r2.xy, r3.xxxx, l(0x3c008081, 0x3f800000, 0x00000000, 0x00000000), l(0xbf800000, 0x3f000000, 0x00000000, 0x00000000)
 precise vec4 f101=fma(uintBitsToFloat(r3.xxxx),uintBitsToFloat(uvec4(0x3c008081u,0x3f800000u,0x00000000u,0x00000000u)),uintBitsToFloat(uvec4(0xbf800000u,0x3f000000u,0x00000000u,0x00000000u)));
 uvec4 t101=floatBitsToUint(f101);
 r2.xy=t101.xy;
 // DXBC 102: add r0.w, r3.w, l(0x3f000000)
 precise vec4 f102=(uintBitsToFloat(uvec4(r3.w))+uintBitsToFloat(uvec4(0x3f000000u)));
 uvec4 t102=floatBitsToUint(f102);
 r0.w=t102.w;
 // DXBC 103: ftou r0.xw, r0.xxxw
 uvec4 t103=uvec4(uintBitsToFloat(r0.xxxw));
 r0.xw=t103.xw;
 // DXBC 104: mov r6.w, r2.x
 uvec4 t104=uvec4(r2.x);
 r6.w=t104.w;
 // DXBC 105: ftou r1.xy, r2.ywyy
 uvec4 t105=uvec4(uintBitsToFloat(r2.ywyy));
 r1.xy=t105.xy;
 // DXBC 106: dp2 r2.x, r6.xwxx, r6.xwxx
 precise vec4 f106=vec4(dx_dp2(uintBitsToFloat(r6.xwxx),uintBitsToFloat(r6.xwxx)));
 uvec4 t106=floatBitsToUint(f106);
 r2.x=t106.x;
 // DXBC 107: ftou r2.y, r6.z
 uvec4 t107=uvec4(uintBitsToFloat(uvec4(r6.z)));
 r2.y=t107.y;
 // DXBC 108: imad r1.x, r1.x, l(0x00000100), r2.y
 uvec4 t108=(uvec4(r1.x)*uvec4(0x00000100u)+uvec4(r2.y));
 r1.x=t108.x;
 // DXBC 109: bfi r3.x, l(0x00000010), l(0x00000010), r1.y, r1.x
 uvec4 t109=uvec4(bitfieldInsert((uvec4(r1.x)).x,(uvec4(r1.y)).x,int((uvec4(0x00000010u)).x),int((uvec4(0x00000010u)).x)),bitfieldInsert((uvec4(r1.x)).y,(uvec4(r1.y)).y,int((uvec4(0x00000010u)).y),int((uvec4(0x00000010u)).y)),bitfieldInsert((uvec4(r1.x)).z,(uvec4(r1.y)).z,int((uvec4(0x00000010u)).z),int((uvec4(0x00000010u)).z)),bitfieldInsert((uvec4(r1.x)).w,(uvec4(r1.y)).w,int((uvec4(0x00000010u)).w),int((uvec4(0x00000010u)).w)));
 r3.x=t109.x;
 // DXBC 110: ushr r1.x, r1.y, l(0x00000010)
 uvec4 t110=(uvec4(r1.y)>>(uvec4(0x00000010u)&uvec4(31u)));
 r1.x=t110.x;
 // DXBC 111: or r3.y, r0.z, r1.x
 uvec4 t111=(uvec4(r0.z)|uvec4(r1.x));
 r3.y=t111.y;
 // DXBC 112: sqrt r0.z, r2.x
 precise vec4 f112=sqrt(uintBitsToFloat(uvec4(r2.x)));
 uvec4 t112=floatBitsToUint(f112);
 r0.z=t112.z;
 // DXBC 113: lt r0.yz, l(0x00000000, 0x3dcccccd, 0x3f000000, 0x00000000), r0.yyzy
 uvec4 t113=mix(uvec4(0u),uvec4(0xffffffffu),lessThan(uintBitsToFloat(uvec4(0x00000000u,0x3dcccccdu,0x3f000000u,0x00000000u)),uintBitsToFloat(r0.yyzy)));
 r0.yz=t113.yz;
 // DXBC 114: and r0.y, r0.y, r0.z
 uvec4 t114=(uvec4(r0.y)&uvec4(r0.z));
 r0.y=t114.y;
 // DXBC 115: and r0.y, r0.y, l(0x00ff0000)
 uvec4 t115=(uvec4(r0.y)&uvec4(0x00ff0000u));
 r0.y=t115.y;
 // DXBC 116: ushr r0.z, r1.w, l(0x00000008)
 uvec4 t116=(uvec4(r1.w)>>(uvec4(0x00000008u)&uvec4(31u)));
 r0.z=t116.z;
 // DXBC 117: ishl r1.x, r1.w, l(0x00000018)
 uvec4 t117=(uvec4(r1.w)<<(uvec4(0x00000018u)&uvec4(31u)));
 r1.x=t117.x;
 // DXBC 118: or r3.z, r0.x, r1.x
 uvec4 t118=(uvec4(r0.x)|uvec4(r1.x));
 r3.z=t118.z;
 // DXBC 119: iadd r0.x, r0.y, r0.z
 uvec4 t119=(uvec4(r0.y)+uvec4(r0.z));
 r0.x=t119.x;
 // DXBC 120: imad r3.w, r0.w, l(0x01000000), r0.x
 uvec4 t120=(uvec4(r0.w)*uvec4(0x01000000u)+uvec4(r0.x));
 r3.w=t120.w;
 // DXBC 121: mov r7.xyz, l(0x00000000,0x00000000,0x00000000,0x00000000)
 uvec4 t121=uvec4(0x00000000u,0x00000000u,0x00000000u,0x00000000u);
 r7.xyz=t121.xyz;
 // DXBC 122: iadd r0.xyzw, r7.xyzw, r3.xyzw
 uvec4 t122=(r7.xyzw+r3.xyzw);
 r0.xyzw=t122.xyzw;
 // DXBC 123: store_structured u0.xyzw, r1.z, l(0x00000000), r0.xyzw
 uvec4 t123=r0.xyzw;
 waterCells[(uvec4(r1.z)).x]=t123;
 // DXBC 124: ret
 return;
}
