#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=2,std430) readonly buffer Cells {uint v[];};
layout(set=0,binding=3,std430) writeonly buffer Scratch {uint s[];};
layout(push_constant,std430) uniform Push {uint n,x,z,w,h,index,phase,reserved;}p;
void add(float value,inout float sum,inout float correction){float y=value-correction;float t=sum+y;correction=(t-sum)-y;sum=t;}
float ulp(float x){uint b=floatBitsToUint(abs(x));uint e=(b>>23u)&255u;return e==0u?uintBitsToFloat(1u):exp2(float(int(e)-127-23));}
void main(){uint block=gl_WorkGroupID.x,k=block*16u;float volume=0,qsum=0,abssum=0,c0=0,c1=0,c2=0,maxdelta=0,removed=0,left=0,right=0,c3=0,c4=0,c5=0;uint count=0,touched=0,minx=p.n,minz=p.n,maxx=0,maxz=0,lo=0,hi=0,flags=0;
 for(uint j=0;j<256u;j++){uint i=block*256u+j;if(i>=p.n*p.n)break;float a=uintBitsToFloat(v[i*16u]),b=uintBitsToFloat(v[i*16u+1u]);uint bits=v[i*16u+15u];flags|=bits&~15u;float delta=b-a;add(delta*0.015625,volume,c0);add(abs(delta)*0.015625,abssum,c2);
  add(max(-delta,0.0)*0.015625,removed,c3);if((bits&4u)!=0u)add(max(delta,0.0)*0.015625,left,c4);if((bits&8u)!=0u)add(max(delta,0.0)*0.015625,right,c5);
  if((bits&1u)!=0u){touched++;add(2.0*ulp(max(abs(a),abs(b)))*0.015625,qsum,c1);}
  if(delta!=0){uint xx=i%p.n,zz=i/p.n;count++;minx=min(minx,xx);minz=min(minz,zz);maxx=max(maxx,xx);maxz=max(maxz,zz);maxdelta=max(maxdelta,abs(delta));uint chunk=(zz/32u)*8u+xx/32u;if(chunk<32u)lo|=1u<<chunk;else hi|=1u<<(chunk-32u);}
 }
 s[k]=floatBitsToUint(volume);s[k+1]=floatBitsToUint(removed);s[k+2]=floatBitsToUint(qsum);s[k+3]=floatBitsToUint(abssum);s[k+4]=floatBitsToUint(maxdelta);s[k+5]=count;s[k+6]=minx;s[k+7]=minz;s[k+8]=maxx;s[k+9]=maxz;s[k+10]=lo;s[k+11]=hi;s[k+12]=flags;s[k+13]=touched;s[k+14]=floatBitsToUint(left);s[k+15]=floatBitsToUint(right);}
