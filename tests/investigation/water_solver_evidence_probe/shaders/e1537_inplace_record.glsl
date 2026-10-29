#[compute]
#version 450
// Mechanical packed-uint lowering of frozen original DXBC, not original HLSL.
// Same logical in-place water alias and 32x32 threads. No intra-dispatch barrier added.
layout(local_size_x=32,local_size_y=32,local_size_z=1) in;
layout(set=0,binding=0,std430) buffer Water {uvec4 waterCells[];};
layout(set=0,binding=1,std430) readonly buffer Constants {uvec4 constants[];};
layout(set=0,binding=2,std430) readonly buffer Auxiliary {uvec4 auxiliaryCells[];};
layout(set=0,binding=3,rg16f) readonly uniform image2D sourceTexture;
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

 // DXBC 0: imad r0.x, vThreadID.y, cb0[155].x, vThreadID.x
 uvec4 t0=(uvec4(vThreadID.y)*uvec4(constants[155].x)+uvec4(vThreadID.x));
 r0.x=t0.x;
 // DXBC 1: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r1.xyzw, r0.x, l(0x00000000), u0.xyzw
 // Explicit stream substitution; original computed address is still recorded.
 uint streamSlot1=(vThreadID.y*512u+vThreadID.x)*2u+0u;
 observedStream[streamSlot1]=uvec4((uvec4(r0.x)).x,0u,15u,1u);
 uvec4 cell1=waterCells[(uvec4(r0.x)).x];
 uvec4 t1=uvec4(0u);
 t1.x=cell1.x;
 t1.y=cell1.y;
 t1.z=cell1.z;
 t1.w=cell1.w;
 r1.xyzw=t1.xyzw;
 uvec4 streamValue1=uvec4(0u);
 streamValue1.xyzw=r1.xyzw;
 observedStream[streamSlot1+1u]=streamValue1;
 // DXBC 2: itof r0.yz, vThreadID.xxyx
 precise vec4 f2=vec4(ivec4(vThreadID.xxyx));
 uvec4 t2=floatBitsToUint(f2);
 r0.yz=t2.yz;
 // DXBC 3: add r0.yz, r0.yyzy, l(0x00000000, 0x3f000000, 0x3f000000, 0x00000000)
 precise vec4 f3=(uintBitsToFloat(r0.yyzy)+uintBitsToFloat(uvec4(0x00000000u,0x3f000000u,0x3f000000u,0x00000000u)));
 uvec4 t3=floatBitsToUint(f3);
 r0.yz=t3.yz;
 // DXBC 4: itof r2.xy, cb0[155].xyxx
 precise vec4 f4=vec4(ivec4(constants[155].xyxx));
 uvec4 t4=floatBitsToUint(f4);
 r2.xy=t4.xy;
 // DXBC 5: div_sat r0.yz, r0.yyzy, r2.xxyx
 precise vec4 f5=clamp((uintBitsToFloat(r0.yyzy)/uintBitsToFloat(r2.xxyx)),vec4(0),vec4(1));
 uvec4 t5=floatBitsToUint(f5);
 r0.yz=t5.yz;
 // DXBC 6: itof r2.xy, cb0[157].xyxx
 precise vec4 f6=vec4(ivec4(constants[157].xyxx));
 uvec4 t6=floatBitsToUint(f6);
 r2.xy=t6.xy;
 // DXBC 7: mad r0.yw, r0.yyyz, r2.xxxy, l(0x00000000, 0xbf000000, 0x00000000, 0xbf000000)
 precise vec4 f7=fma(uintBitsToFloat(r0.yyyz),uintBitsToFloat(r2.xxxy),uintBitsToFloat(uvec4(0x00000000u,0xbf000000u,0x00000000u,0xbf000000u)));
 uvec4 t7=floatBitsToUint(f7);
 r0.yw=t7.yw;
 // DXBC 8: mul r0.z, r0.z, l(0x3d1ad42c)
 precise vec4 f8=(uintBitsToFloat(uvec4(r0.z))*uintBitsToFloat(uvec4(0x3d1ad42cu)));
 uvec4 t8=floatBitsToUint(f8);
 r0.z=t8.z;
 // DXBC 9: mad r0.z, cb0[113].z, l(0x41000000), r0.z
 precise vec4 f9=fma(uintBitsToFloat(uvec4(constants[113].z)),uintBitsToFloat(uvec4(0x41000000u)),uintBitsToFloat(uvec4(r0.z)));
 uvec4 t9=floatBitsToUint(f9);
 r0.z=t9.z;
 // DXBC 10: sincos r0.z, null, r0.z
 precise vec4 f10=uintBitsToFloat(uvec4(r0.z));
 r0.z=floatBitsToUint(sin(f10)).z;
 // DXBC 11: round_ni r2.xy, r0.ywyy
 precise vec4 f11=floor(uintBitsToFloat(r0.ywyy));
 uvec4 t11=floatBitsToUint(f11);
 r2.xy=t11.xy;
 // DXBC 12: frc r0.yw, r0.yyyw
 precise vec4 f12=fract(uintBitsToFloat(r0.yyyw));
 uvec4 t12=floatBitsToUint(f12);
 r0.yw=t12.yw;
 // DXBC 13: ftoi r2.xy, r2.xyxx
 uvec4 t13=uvec4(ivec4(uintBitsToFloat(r2.xyxx)));
 r2.xy=t13.xy;
 // DXBC 14: iadd r2.zw, r2.xxxy, l(0x00000000, 0x00000000, 0x00000001, 0x00000001)
 uvec4 t14=(r2.xxxy+uvec4(0x00000000u,0x00000000u,0x00000001u,0x00000001u));
 r2.zw=t14.zw;
 // DXBC 15: imax r2.zw, r2.zzzw, l(0x00000000, 0x00000000, 0x00000000, 0x00000000)
 uvec4 t15=uvec4(max(ivec4(r2.zzzw),ivec4(uvec4(0x00000000u,0x00000000u,0x00000000u,0x00000000u))));
 r2.zw=t15.zw;
 // DXBC 16: iadd r3.xy, cb0[157].xyxx, l(0xffffffff, 0xffffffff, 0x00000000, 0x00000000)
 uvec4 t16=(constants[157].xyxx+uvec4(0xffffffffu,0xffffffffu,0x00000000u,0x00000000u));
 r3.xy=t16.xy;
 // DXBC 17: imin r2.zw, r2.zzzw, r3.xxxy
 uvec4 t17=uvec4(min(ivec4(r2.zzzw),ivec4(r3.xxxy)));
 r2.zw=t17.zw;
 // DXBC 18: imad r2.z, r2.w, cb0[157].x, r2.z
 uvec4 t18=(uvec4(r2.w)*uvec4(constants[157].x)+uvec4(r2.z));
 r2.z=t18.z;
 // DXBC 19: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.zw, r2.z, l(0x00000004), t1.xxxy
 uvec4 cell19=auxiliaryCells[(uvec4(r2.z)).x];
 uvec4 t19=uvec4(0u);
 t19.z=cell19.y;
 t19.w=cell19.z;
 r2.zw=t19.zw;
 // DXBC 20: ushr r2.z, r2.z, l(0x0000000c)
 uvec4 t20=(uvec4(r2.z)>>(uvec4(0x0000000cu)&uvec4(31u)));
 r2.z=t20.z;
 // DXBC 21: bfi r2.z, l(0x0000000c), l(0x00000014), r2.w, r2.z
 uvec4 t21=uvec4(bitfieldInsert((uvec4(r2.z)).x,(uvec4(r2.w)).x,int((uvec4(0x00000014u)).x),int((uvec4(0x0000000cu)).x)),bitfieldInsert((uvec4(r2.z)).y,(uvec4(r2.w)).y,int((uvec4(0x00000014u)).y),int((uvec4(0x0000000cu)).y)),bitfieldInsert((uvec4(r2.z)).z,(uvec4(r2.w)).z,int((uvec4(0x00000014u)).z),int((uvec4(0x0000000cu)).z)),bitfieldInsert((uvec4(r2.z)).w,(uvec4(r2.w)).w,int((uvec4(0x00000014u)).w),int((uvec4(0x0000000cu)).w)));
 r2.z=t21.z;
 // DXBC 22: and r2.z, r2.z, l(0x003fffff)
 uvec4 t22=(uvec4(r2.z)&uvec4(0x003fffffu));
 r2.z=t22.z;
 // DXBC 23: iadd r4.xyzw, r2.xyxy, l(0x00000001, 0x00000000, 0x00000000, 0x00000001)
 uvec4 t23=(r2.xyxy+uvec4(0x00000001u,0x00000000u,0x00000000u,0x00000001u));
 r4.xyzw=t23.xyzw;
 // DXBC 24: imax r2.xy, r2.xyxx, l(0x00000000, 0x00000000, 0x00000000, 0x00000000)
 uvec4 t24=uvec4(max(ivec4(r2.xyxx),ivec4(uvec4(0x00000000u,0x00000000u,0x00000000u,0x00000000u))));
 r2.xy=t24.xy;
 // DXBC 25: imin r2.xy, r3.xyxx, r2.xyxx
 uvec4 t25=uvec4(min(ivec4(r3.xyxx),ivec4(r2.xyxx)));
 r2.xy=t25.xy;
 // DXBC 26: imad r2.x, r2.y, cb0[157].x, r2.x
 uvec4 t26=(uvec4(r2.y)*uvec4(constants[157].x)+uvec4(r2.x));
 r2.x=t26.x;
 // DXBC 27: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r2.xy, r2.x, l(0x00000004), t1.xyxx
 uvec4 cell27=auxiliaryCells[(uvec4(r2.x)).x];
 uvec4 t27=uvec4(0u);
 t27.x=cell27.y;
 t27.y=cell27.z;
 r2.xy=t27.xy;
 // DXBC 28: imax r4.xyzw, r4.xyzw, l(0x00000000, 0x00000000, 0x00000000, 0x00000000)
 uvec4 t28=uvec4(max(ivec4(r4.xyzw),ivec4(uvec4(0x00000000u,0x00000000u,0x00000000u,0x00000000u))));
 r4.xyzw=t28.xyzw;
 // DXBC 29: imin r3.xyzw, r3.xyxy, r4.xyzw
 uvec4 t29=uvec4(min(ivec4(r3.xyxy),ivec4(r4.xyzw)));
 r3.xyzw=t29.xyzw;
 // DXBC 30: imad r3.xy, r3.ywyy, cb0[157].xxxx, r3.xzxx
 uvec4 t30=(r3.ywyy*constants[157].xxxx+r3.xzxx);
 r3.xy=t30.xy;
 // DXBC 31: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.yz, r3.y, l(0x00000004), t1.xxyx
 uvec4 cell31=auxiliaryCells[(uvec4(r3.y)).x];
 uvec4 t31=uvec4(0u);
 t31.y=cell31.y;
 t31.z=cell31.z;
 r3.yz=t31.yz;
 // DXBC 32: ld_structured_indexable(structured_buffer, stride=16)(mixed,mixed,mixed,mixed) r3.xw, r3.x, l(0x00000004), t1.xxxy
 uvec4 cell32=auxiliaryCells[(uvec4(r3.x)).x];
 uvec4 t32=uvec4(0u);
 t32.x=cell32.y;
 t32.w=cell32.z;
 r3.xw=t32.xw;
 // DXBC 33: ushr r2.w, r3.y, l(0x0000000c)
 uvec4 t33=(uvec4(r3.y)>>(uvec4(0x0000000cu)&uvec4(31u)));
 r2.w=t33.w;
 // DXBC 34: bfi r2.w, l(0x0000000c), l(0x00000014), r3.z, r2.w
 uvec4 t34=uvec4(bitfieldInsert((uvec4(r2.w)).x,(uvec4(r3.z)).x,int((uvec4(0x00000014u)).x),int((uvec4(0x0000000cu)).x)),bitfieldInsert((uvec4(r2.w)).y,(uvec4(r3.z)).y,int((uvec4(0x00000014u)).y),int((uvec4(0x0000000cu)).y)),bitfieldInsert((uvec4(r2.w)).z,(uvec4(r3.z)).z,int((uvec4(0x00000014u)).z),int((uvec4(0x0000000cu)).z)),bitfieldInsert((uvec4(r2.w)).w,(uvec4(r3.z)).w,int((uvec4(0x00000014u)).w),int((uvec4(0x0000000cu)).w)));
 r2.w=t34.w;
 // DXBC 35: and r2.w, r2.w, l(0x003fffff)
 uvec4 t35=(uvec4(r2.w)&uvec4(0x003fffffu));
 r2.w=t35.w;
 // DXBC 36: utof r2.zw, r2.zzzw
 precise vec4 f36=vec4(r2.zzzw);
 uvec4 t36=floatBitsToUint(f36);
 r2.zw=t36.zw;
 // DXBC 37: mul r2.w, r2.w, l(0x35a00002)
 precise vec4 f37=(uintBitsToFloat(uvec4(r2.w))*uintBitsToFloat(uvec4(0x35a00002u)));
 uvec4 t37=floatBitsToUint(f37);
 r2.w=t37.w;
 // DXBC 38: mad r2.z, r2.z, l(0x35a00002), -r2.w
 precise vec4 f38=fma(uintBitsToFloat(uvec4(r2.z)),uintBitsToFloat(uvec4(0x35a00002u)),uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r2.w)))));
 uvec4 t38=floatBitsToUint(f38);
 r2.z=t38.z;
 // DXBC 39: mad r2.z, r0.y, r2.z, r2.w
 precise vec4 f39=fma(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(r2.z)),uintBitsToFloat(uvec4(r2.w)));
 uvec4 t39=floatBitsToUint(f39);
 r2.z=t39.z;
 // DXBC 40: ushr r2.w, r3.x, l(0x0000000c)
 uvec4 t40=(uvec4(r3.x)>>(uvec4(0x0000000cu)&uvec4(31u)));
 r2.w=t40.w;
 // DXBC 41: bfi r2.w, l(0x0000000c), l(0x00000014), r3.w, r2.w
 uvec4 t41=uvec4(bitfieldInsert((uvec4(r2.w)).x,(uvec4(r3.w)).x,int((uvec4(0x00000014u)).x),int((uvec4(0x0000000cu)).x)),bitfieldInsert((uvec4(r2.w)).y,(uvec4(r3.w)).y,int((uvec4(0x00000014u)).y),int((uvec4(0x0000000cu)).y)),bitfieldInsert((uvec4(r2.w)).z,(uvec4(r3.w)).z,int((uvec4(0x00000014u)).z),int((uvec4(0x0000000cu)).z)),bitfieldInsert((uvec4(r2.w)).w,(uvec4(r3.w)).w,int((uvec4(0x00000014u)).w),int((uvec4(0x0000000cu)).w)));
 r2.w=t41.w;
 // DXBC 42: and r2.w, r2.w, l(0x003fffff)
 uvec4 t42=(uvec4(r2.w)&uvec4(0x003fffffu));
 r2.w=t42.w;
 // DXBC 43: ushr r2.x, r2.x, l(0x0000000c)
 uvec4 t43=(uvec4(r2.x)>>(uvec4(0x0000000cu)&uvec4(31u)));
 r2.x=t43.x;
 // DXBC 44: bfi r2.x, l(0x0000000c), l(0x00000014), r2.y, r2.x
 uvec4 t44=uvec4(bitfieldInsert((uvec4(r2.x)).x,(uvec4(r2.y)).x,int((uvec4(0x00000014u)).x),int((uvec4(0x0000000cu)).x)),bitfieldInsert((uvec4(r2.x)).y,(uvec4(r2.y)).y,int((uvec4(0x00000014u)).y),int((uvec4(0x0000000cu)).y)),bitfieldInsert((uvec4(r2.x)).z,(uvec4(r2.y)).z,int((uvec4(0x00000014u)).z),int((uvec4(0x0000000cu)).z)),bitfieldInsert((uvec4(r2.x)).w,(uvec4(r2.y)).w,int((uvec4(0x00000014u)).w),int((uvec4(0x0000000cu)).w)));
 r2.x=t44.x;
 // DXBC 45: and r2.x, r2.x, l(0x003fffff)
 uvec4 t45=(uvec4(r2.x)&uvec4(0x003fffffu));
 r2.x=t45.x;
 // DXBC 46: utof r2.xw, r2.xxxw
 precise vec4 f46=vec4(r2.xxxw);
 uvec4 t46=floatBitsToUint(f46);
 r2.xw=t46.xw;
 // DXBC 47: mul r2.x, r2.x, l(0x35a00002)
 precise vec4 f47=(uintBitsToFloat(uvec4(r2.x))*uintBitsToFloat(uvec4(0x35a00002u)));
 uvec4 t47=floatBitsToUint(f47);
 r2.x=t47.x;
 // DXBC 48: mad r2.y, r2.w, l(0x35a00002), -r2.x
 precise vec4 f48=fma(uintBitsToFloat(uvec4(r2.w)),uintBitsToFloat(uvec4(0x35a00002u)),uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r2.x)))));
 uvec4 t48=floatBitsToUint(f48);
 r2.y=t48.y;
 // DXBC 49: mad r0.y, r0.y, r2.y, r2.x
 precise vec4 f49=fma(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(r2.y)),uintBitsToFloat(uvec4(r2.x)));
 uvec4 t49=floatBitsToUint(f49);
 r0.y=t49.y;
 // DXBC 50: add r2.x, -r0.y, r2.z
 precise vec4 f50=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r0.y))))+uintBitsToFloat(uvec4(r2.z)));
 uvec4 t50=floatBitsToUint(f50);
 r2.x=t50.x;
 // DXBC 51: mad r0.y, r0.w, r2.x, r0.y
 precise vec4 f51=fma(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(r2.x)),uintBitsToFloat(uvec4(r0.y)));
 uvec4 t51=floatBitsToUint(f51);
 r0.y=t51.y;
 // DXBC 52: mul r0.y, r0.y, l(0xbf38aa3b)
 precise vec4 f52=(uintBitsToFloat(uvec4(r0.y))*uintBitsToFloat(uvec4(0xbf38aa3bu)));
 uvec4 t52=floatBitsToUint(f52);
 r0.y=t52.y;
 // DXBC 53: exp r0.y, r0.y
 precise vec4 f53=exp2(uintBitsToFloat(uvec4(r0.y)));
 uvec4 t53=floatBitsToUint(f53);
 r0.y=t53.y;
 // DXBC 54: mul r0.w, cb0[125].x, cb0[158].y
 precise vec4 f54=(uintBitsToFloat(uvec4(constants[125].x))*uintBitsToFloat(uvec4(constants[158].y)));
 uvec4 t54=floatBitsToUint(f54);
 r0.w=t54.w;
 // DXBC 55: mul r0.w, r0.w, l(0x3a83126f)
 precise vec4 f55=(uintBitsToFloat(uvec4(r0.w))*uintBitsToFloat(uvec4(0x3a83126fu)));
 uvec4 t55=floatBitsToUint(f55);
 r0.w=t55.w;
 // DXBC 56: mul r0.y, r0.y, r0.w
 precise vec4 f56=(uintBitsToFloat(uvec4(r0.y))*uintBitsToFloat(uvec4(r0.w)));
 uvec4 t56=floatBitsToUint(f56);
 r0.y=t56.y;
 // DXBC 57: and r2.xy, r1.xzxx, l(0x000000ff, 0x00ffffff, 0x00000000, 0x00000000)
 uvec4 t57=(r1.xzxx&uvec4(0x000000ffu,0x00ffffffu,0x00000000u,0x00000000u));
 r2.xy=t57.xy;
 // DXBC 58: utof r2.xy, r2.xyxx
 precise vec4 f58=vec4(r2.xyxx);
 uvec4 t58=floatBitsToUint(f58);
 r2.xy=t58.xy;
 // DXBC 59: mul r0.w, r2.y, l(0x3521999b)
 precise vec4 f59=(uintBitsToFloat(uvec4(r2.y))*uintBitsToFloat(uvec4(0x3521999bu)));
 uvec4 t59=floatBitsToUint(f59);
 r0.w=t59.w;
 // DXBC 60: mad r0.y, -r0.y, cb0[157].z, r0.w
 precise vec4 f60=fma(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r0.y)))),uintBitsToFloat(uvec4(constants[157].z)),uintBitsToFloat(uvec4(r0.w)));
 uvec4 t60=floatBitsToUint(f60);
 r0.y=t60.y;
 // DXBC 61: mad r0.w, r2.y, l(0x3521999b), l(0xbd4ccccd)
 precise vec4 f61=fma(uintBitsToFloat(uvec4(r2.y)),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(uvec4(0xbd4ccccdu)));
 uvec4 t61=floatBitsToUint(f61);
 r0.w=t61.w;
 // DXBC 62: add r2.x, r2.x, l(0x3f000000)
 precise vec4 f62=(uintBitsToFloat(uvec4(r2.x))+uintBitsToFloat(uvec4(0x3f000000u)));
 uvec4 t62=floatBitsToUint(f62);
 r2.x=t62.x;
 // DXBC 63: max r0.w, r0.w, l(0x00000000)
 precise vec4 f63=max(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(0x00000000u)));
 uvec4 t63=floatBitsToUint(f63);
 r0.w=t63.w;
 // DXBC 64: ushr r3.xyzw, r1.xyzw, l(0x00000010, 0x00000008, 0x00000018, 0x0000001c)
 uvec4 t64=(r1.xyzw>>(uvec4(0x00000010u,0x00000008u,0x00000018u,0x0000001cu)&uvec4(31u)));
 r3.xyzw=t64.xyzw;
 // DXBC 65: bfi r1.yz, l(0x00000000, 0x00000010, 0x00000018, 0x00000000), l(0x00000000, 0x00000010, 0x00000008, 0x00000000), r1.yywy, r3.xxzx
 uvec4 t65=uvec4(bitfieldInsert((r3.xxzx).x,(r1.yywy).x,int((uvec4(0x00000000u,0x00000010u,0x00000008u,0x00000000u)).x),int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).x)),bitfieldInsert((r3.xxzx).y,(r1.yywy).y,int((uvec4(0x00000000u,0x00000010u,0x00000008u,0x00000000u)).y),int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).y)),bitfieldInsert((r3.xxzx).z,(r1.yywy).z,int((uvec4(0x00000000u,0x00000010u,0x00000008u,0x00000000u)).z),int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).z)),bitfieldInsert((r3.xxzx).w,(r1.yywy).w,int((uvec4(0x00000000u,0x00000010u,0x00000008u,0x00000000u)).w),int((uvec4(0x00000000u,0x00000010u,0x00000018u,0x00000000u)).w)));
 r1.yz=t65.yz;
 // DXBC 66: utof r2.yz, r3.yywy
 precise vec4 f66=vec4(r3.yywy);
 uvec4 t66=floatBitsToUint(f66);
 r2.yz=t66.yz;
 // DXBC 67: ubfe r3.xyz, l(0x00000008, 0x00000008, 0x00000004, 0x00000000), l(0x00000008, 0x00000010, 0x00000018, 0x00000000), r1.xwwx
 uvec4 t67=uvec4(bitfieldExtract((r1.xwwx).x,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).x),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).x)),bitfieldExtract((r1.xwwx).y,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).y),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).y)),bitfieldExtract((r1.xwwx).z,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).z),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).z)),bitfieldExtract((r1.xwwx).w,int((uvec4(0x00000008u,0x00000010u,0x00000018u,0x00000000u)).w),int((uvec4(0x00000008u,0x00000008u,0x00000004u,0x00000000u)).w)));
 r3.xyz=t67.xyz;
 // DXBC 68: utof r3.xyz, r3.xyzx
 precise vec4 f68=vec4(r3.xyzx);
 uvec4 t68=floatBitsToUint(f68);
 r3.xyz=t68.xyz;
 // DXBC 69: and r1.xy, r1.yzyy, l(0x00ffffff, 0x00ffffff, 0x00000000, 0x00000000)
 uvec4 t69=(r1.yzyy&uvec4(0x00ffffffu,0x00ffffffu,0x00000000u,0x00000000u));
 r1.xy=t69.xy;
 // DXBC 70: utof r1.xy, r1.xyxx
 precise vec4 f70=vec4(r1.xyxx);
 uvec4 t70=floatBitsToUint(f70);
 r1.xy=t70.xy;
 // DXBC 71: mad r0.w, r1.y, l(0x3521999b), r0.w
 precise vec4 f71=fma(uintBitsToFloat(uvec4(r1.y)),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(uvec4(r0.w)));
 uvec4 t71=floatBitsToUint(f71);
 r0.w=t71.w;
 // DXBC 72: mov r4.xy, vThreadID.xyxx
 uvec4 t72=vThreadID.xyxx;
 r4.xy=t72.xy;
 // DXBC 73: mov r4.zw, l(0x00000000,0x00000000,0x00000000,0x00000000)
 uvec4 t73=uvec4(0x00000000u,0x00000000u,0x00000000u,0x00000000u);
 r4.zw=t73.zw;
 // DXBC 74: ld_indexable(texture2d)(float,float,float,float) r1.z, r4.xyzw, t0.xzyw
 ivec4 coord74=ivec4(r4.xyzw);
 vec4 tex74=vec4(0);
 if(all(greaterThanEqual(coord74.xy,ivec2(0)))&&all(lessThan(coord74.xy,imageSize(sourceTexture)))&&coord74.w==0){tex74=vec4(imageLoad(sourceTexture,coord74.xy).rg,0.0,1.0);}
 uvec4 t74=floatBitsToUint(tex74.xzyw);
 r1.z=t74.z;
 // DXBC 75: ge r1.w, r0.w, r1.z
 uvec4 t75=mix(uvec4(0u),uvec4(0xffffffffu),greaterThanEqual(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(r1.z))));
 r1.w=t75.w;
 // DXBC 76: add r0.w, -r0.w, r1.z
 precise vec4 f76=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r0.w))))+uintBitsToFloat(uvec4(r1.z)));
 uvec4 t76=floatBitsToUint(f76);
 r0.w=t76.w;
 // DXBC 77: lt r0.w, r0.w, l(0x3dcccccd)
 uvec4 t77=mix(uvec4(0u),uvec4(0xffffffffu),lessThan(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(0x3dcccccdu))));
 r0.w=t77.w;
 // DXBC 78: mul r2.w, r1.y, l(0x3521999b)
 precise vec4 f78=(uintBitsToFloat(uvec4(r1.y))*uintBitsToFloat(uvec4(0x3521999bu)));
 uvec4 t78=floatBitsToUint(f78);
 r2.w=t78.w;
 // DXBC 79: lt r1.z, r2.w, r1.z
 uvec4 t79=mix(uvec4(0u),uvec4(0xffffffffu),lessThan(uintBitsToFloat(uvec4(r2.w)),uintBitsToFloat(uvec4(r1.z))));
 r1.z=t79.z;
 // DXBC 80: and r1.z, r1.z, r1.w
 uvec4 t80=(uvec4(r1.z)&uvec4(r1.w));
 r1.z=t80.z;
 // DXBC 81: and r0.w, r0.w, r1.z
 uvec4 t81=(uvec4(r0.w)&uvec4(r1.z));
 r0.w=t81.w;
 // DXBC 82: and r0.w, r0.w, l(0x3f800000)
 uvec4 t82=(uvec4(r0.w)&uvec4(0x3f800000u));
 r0.w=t82.w;
 // DXBC 83: mul r0.z, r0.w, r0.z
 precise vec4 f83=(uintBitsToFloat(uvec4(r0.w))*uintBitsToFloat(uvec4(r0.z)));
 uvec4 t83=floatBitsToUint(f83);
 r0.z=t83.z;
 // DXBC 84: mul r0.z, r0.z, cb0[157].z
 precise vec4 f84=(uintBitsToFloat(uvec4(r0.z))*uintBitsToFloat(uvec4(constants[157].z)));
 uvec4 t84=floatBitsToUint(f84);
 r0.z=t84.z;
 // DXBC 85: mad r0.y, r0.z, l(0x3e19999a), r0.y
 precise vec4 f85=fma(uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(0x3e19999au)),uintBitsToFloat(uvec4(r0.y)));
 uvec4 t85=floatBitsToUint(f85);
 r0.y=t85.y;
 // DXBC 86: sincos r0.z, null, cb0[113].z
 precise vec4 f86=uintBitsToFloat(uvec4(constants[113].z));
 r0.z=floatBitsToUint(sin(f86)).z;
 // DXBC 87: mul r0.z, r0.z, cb0[158].w
 precise vec4 f87=(uintBitsToFloat(uvec4(r0.z))*uintBitsToFloat(uvec4(constants[158].w)));
 uvec4 t87=floatBitsToUint(f87);
 r0.z=t87.z;
 // DXBC 88: max r0.z, r0.z, l(0xbf000000)
 precise vec4 f88=max(uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(0xbf000000u)));
 uvec4 t88=floatBitsToUint(f88);
 r0.z=t88.z;
 // DXBC 89: mad r0.w, -r1.y, l(0x3521999b), cb0[159].z
 precise vec4 f89=fma(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r1.y)))),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(uvec4(constants[159].z)));
 uvec4 t89=floatBitsToUint(f89);
 r0.w=t89.w;
 // DXBC 90: add r0.z, r0.z, r0.w
 precise vec4 f90=(uintBitsToFloat(uvec4(r0.z))+uintBitsToFloat(uvec4(r0.w)));
 uvec4 t90=floatBitsToUint(f90);
 r0.z=t90.z;
 // DXBC 91: max r0.z, r0.z, l(0x3d4ccccd)
 precise vec4 f91=max(uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(0x3d4ccccdu)));
 uvec4 t91=floatBitsToUint(f91);
 r0.z=t91.z;
 // DXBC 92: add r0.z, -r0.y, r0.z
 precise vec4 f92=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r0.y))))+uintBitsToFloat(uvec4(r0.z)));
 uvec4 t92=floatBitsToUint(f92);
 r0.z=t92.z;
 // DXBC 93: mul r0.w, r2.z, l(0x3d888889)
 precise vec4 f93=(uintBitsToFloat(uvec4(r2.z))*uintBitsToFloat(uvec4(0x3d888889u)));
 uvec4 t93=floatBitsToUint(f93);
 r0.w=t93.w;
 // DXBC 94: add r1.zw, r2.yyyz, l(0x00000000, 0x00000000, 0x3f000000, 0x3f000000)
 precise vec4 f94=(uintBitsToFloat(r2.yyyz)+uintBitsToFloat(uvec4(0x00000000u,0x00000000u,0x3f000000u,0x3f000000u)));
 uvec4 t94=floatBitsToUint(f94);
 r1.zw=t94.zw;
 // DXBC 95: ftou r1.zw, r1.zzzw
 uvec4 t95=uvec4(uintBitsToFloat(r1.zzzw));
 r1.zw=t95.zw;
 // DXBC 96: ishl r4.xy, r1.zwzz, l(0x00000008, 0x0000001c, 0x00000000, 0x00000000)
 uvec4 t96=(r1.zwzz<<(uvec4(0x00000008u,0x0000001cu,0x00000000u,0x00000000u)&uvec4(31u)));
 r4.xy=t96.xy;
 // DXBC 97: mad r0.y, r0.w, r0.z, r0.y
 precise vec4 f97=fma(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(r0.y)));
 uvec4 t97=floatBitsToUint(f97);
 r0.y=t97.y;
 // DXBC 98: add r0.z, cb0[159].z, cb0[159].x
 precise vec4 f98=(uintBitsToFloat(uvec4(constants[159].z))+uintBitsToFloat(uvec4(constants[159].x)));
 uvec4 t98=floatBitsToUint(f98);
 r0.z=t98.z;
 // DXBC 99: mad r0.z, -r1.y, l(0x3521999b), r0.z
 precise vec4 f99=fma(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r1.y)))),uintBitsToFloat(uvec4(0x3521999bu)),uintBitsToFloat(uvec4(r0.z)));
 uvec4 t99=floatBitsToUint(f99);
 r0.z=t99.z;
 // DXBC 100: add r1.xy, r1.xyxx, l(0x3f000000, 0x3f000000, 0x00000000, 0x00000000)
 precise vec4 f100=(uintBitsToFloat(r1.xyxx)+uintBitsToFloat(uvec4(0x3f000000u,0x3f000000u,0x00000000u,0x00000000u)));
 uvec4 t100=floatBitsToUint(f100);
 r1.xy=t100.xy;
 // DXBC 101: ftou r1.xy, r1.xyxx
 uvec4 t101=uvec4(uintBitsToFloat(r1.xyxx));
 r1.xy=t101.xy;
 // DXBC 102: add r0.z, -r0.y, r0.z
 precise vec4 f102=(uintBitsToFloat(floatBitsToUint(-uintBitsToFloat(uvec4(r0.y))))+uintBitsToFloat(uvec4(r0.z)));
 uvec4 t102=floatBitsToUint(f102);
 r0.z=t102.z;
 // DXBC 103: mad r0.z, r0.w, r0.z, r0.y
 precise vec4 f103=fma(uintBitsToFloat(uvec4(r0.w)),uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(r0.y)));
 uvec4 t103=floatBitsToUint(f103);
 r0.z=t103.z;
 // DXBC 104: lt r0.w, l(0x00000000), cb0[159].x
 uvec4 t104=mix(uvec4(0u),uvec4(0xffffffffu),lessThan(uintBitsToFloat(uvec4(0x00000000u)),uintBitsToFloat(uvec4(constants[159].x))));
 r0.w=t104.w;
 // DXBC 105: movc r0.y, r0.w, r0.z, r0.y
 uvec4 t105=mix(uvec4(r0.y),uvec4(r0.z),notEqual(uvec4(r0.w),uvec4(0u)));
 r0.y=t105.y;
 // DXBC 106: lt r0.z, l(0x3f866666), r3.z
 uvec4 t106=mix(uvec4(0u),uvec4(0xffffffffu),lessThan(uintBitsToFloat(uvec4(0x3f866666u)),uintBitsToFloat(uvec4(r3.z))));
 r0.z=t106.z;
 // DXBC 107: and r0.z, r0.z, l(0x3f800000)
 uvec4 t107=(uvec4(r0.z)&uvec4(0x3f800000u));
 r0.z=t107.z;
 // DXBC 108: mul r0.w, r3.z, l(0x3d888889)
 precise vec4 f108=(uintBitsToFloat(uvec4(r3.z))*uintBitsToFloat(uvec4(0x3d888889u)));
 uvec4 t108=floatBitsToUint(f108);
 r0.w=t108.w;
 // DXBC 109: add r2.yzw, r3.xxyz, l(0x00000000, 0x3f000000, 0x3f000000, 0x3f000000)
 precise vec4 f109=(uintBitsToFloat(r3.xxyz)+uintBitsToFloat(uvec4(0x00000000u,0x3f000000u,0x3f000000u,0x3f000000u)));
 uvec4 t109=floatBitsToUint(f109);
 r2.yzw=t109.yzw;
 // DXBC 110: ftou r2.xyzw, r2.xyzw
 uvec4 t110=uvec4(uintBitsToFloat(r2.xyzw));
 r2.xyzw=t110.xyzw;
 // DXBC 111: mul r0.z, r0.z, r0.w
 precise vec4 f111=(uintBitsToFloat(uvec4(r0.z))*uintBitsToFloat(uvec4(r0.w)));
 uvec4 t111=floatBitsToUint(f111);
 r0.z=t111.z;
 // DXBC 112: mad r0.y, r0.z, cb0[157].z, r0.y
 precise vec4 f112=fma(uintBitsToFloat(uvec4(r0.z)),uintBitsToFloat(uvec4(constants[157].z)),uintBitsToFloat(uvec4(r0.y)));
 uvec4 t112=floatBitsToUint(f112);
 r0.y=t112.y;
 // DXBC 113: max r0.y, r0.y, cb0[114].y
 precise vec4 f113=max(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(constants[114].y)));
 uvec4 t113=floatBitsToUint(f113);
 r0.y=t113.y;
 // DXBC 114: min r0.y, r0.y, cb0[115].y
 precise vec4 f114=min(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(constants[115].y)));
 uvec4 t114=floatBitsToUint(f114);
 r0.y=t114.y;
 // DXBC 115: mul_sat r0.y, r0.y, l(0x3dcac5b3)
 precise vec4 f115=clamp((uintBitsToFloat(uvec4(r0.y))*uintBitsToFloat(uvec4(0x3dcac5b3u))),vec4(0),vec4(1));
 uvec4 t115=floatBitsToUint(f115);
 r0.y=t115.y;
 // DXBC 116: mad r0.y, r0.y, l(0x4b7fffff), l(0x3f000000)
 precise vec4 f116=fma(uintBitsToFloat(uvec4(r0.y)),uintBitsToFloat(uvec4(0x4b7fffffu)),uintBitsToFloat(uvec4(0x3f000000u)));
 uvec4 t116=floatBitsToUint(f116);
 r0.y=t116.y;
 // DXBC 117: ftou r3.x, r0.y
 uvec4 t117=uvec4(uintBitsToFloat(uvec4(r0.y)));
 r3.x=t117.x;
 // DXBC 118: mov r3.y, l(0x00000000)
 uvec4 t118=uvec4(0x00000000u);
 r3.y=t118.y;
 // DXBC 119: ishl r5.x, r1.y, l(0x00000018)
 uvec4 t119=(uvec4(r1.y)<<(uvec4(0x00000018u)&uvec4(31u)));
 r5.x=t119.x;
 // DXBC 120: ushr r5.yz, r1.xxyx, l(0x00000000, 0x00000010, 0x00000008, 0x00000000)
 uvec4 t120=(r1.xxyx>>(uvec4(0x00000000u,0x00000010u,0x00000008u,0x00000000u)&uvec4(31u)));
 r5.yz=t120.yz;
 // DXBC 121: or r3.xz, r3.yyxy, r5.zzxz
 uvec4 t121=(r3.yyxy|r5.zzxz);
 r3.xz=t121.xz;
 // DXBC 122: or r3.y, r4.x, r5.y
 uvec4 t122=(uvec4(r4.x)|uvec4(r5.y));
 r3.y=t122.y;
 // DXBC 123: imad r0.y, r2.z, l(0x00010000), r3.x
 uvec4 t123=(uvec4(r2.z)*uvec4(0x00010000u)+uvec4(r3.x));
 r0.y=t123.y;
 // DXBC 124: imad r3.w, r2.w, l(0x01000000), r0.y
 uvec4 t124=(uvec4(r2.w)*uvec4(0x01000000u)+uvec4(r0.y));
 r3.w=t124.w;
 // DXBC 125: imad r0.y, r2.y, l(0x00000100), r2.x
 uvec4 t125=(uvec4(r2.y)*uvec4(0x00000100u)+uvec4(r2.x));
 r0.y=t125.y;
 // DXBC 126: bfi r3.x, l(0x00000010), l(0x00000010), r1.x, r0.y
 uvec4 t126=uvec4(bitfieldInsert((uvec4(r0.y)).x,(uvec4(r1.x)).x,int((uvec4(0x00000010u)).x),int((uvec4(0x00000010u)).x)),bitfieldInsert((uvec4(r0.y)).y,(uvec4(r1.x)).y,int((uvec4(0x00000010u)).y),int((uvec4(0x00000010u)).y)),bitfieldInsert((uvec4(r0.y)).z,(uvec4(r1.x)).z,int((uvec4(0x00000010u)).z),int((uvec4(0x00000010u)).z)),bitfieldInsert((uvec4(r0.y)).w,(uvec4(r1.x)).w,int((uvec4(0x00000010u)).w),int((uvec4(0x00000010u)).w)));
 r3.x=t126.x;
 // DXBC 127: mov r4.z, l(0x00000000)
 uvec4 t127=uvec4(0x00000000u);
 r4.z=t127.z;
 // DXBC 128: iadd r1.xyzw, r4.zzzy, r3.xyzw
 uvec4 t128=(r4.zzzy+r3.xyzw);
 r1.xyzw=t128.xyzw;
 // DXBC 129: store_structured u0.xyzw, r0.x, l(0x00000000), r1.xyzw
 uvec4 t129=r1.xyzw;
 waterCells[(uvec4(r0.x)).x]=t129;
 // DXBC 130: ret
 return;
}
