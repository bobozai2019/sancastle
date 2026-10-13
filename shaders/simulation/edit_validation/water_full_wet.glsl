#[compute]
#version 450
layout(local_size_x=64) in;
struct InputCell { vec4 bed_water; vec4 flow; };
layout(set=0,binding=0,std430) readonly buffer Input { InputCell input_cells[]; };
layout(set=0,binding=1,std430) buffer Candidate { vec4 output_cells[]; };
layout(set=0,binding=3,std430) buffer Receipt { uint receipt[]; };
layout(push_constant,std430) uniform Params { uint size; float cell_size; uint pad0; uint pad1; } params;
shared vec4 v[64], f[64], o[64];
shared vec2 dry_loss[64];
shared uint bad,wet_count,full_row;
shared precise float eta,demand,dc,capacity,cc,actual,ac,sed,sc,qx,qxc,qz,qzc,loss_x,lxc,loss_z,lzc;
shared precise float residual,ec,wquant,wqc,squant,sqc,wabs,wac,sabs,sac,serror,sec;
uint count,lane; float area;
void add(inout float sum,inout float correction,float x) {
    precise float y=x-correction; precise float next=sum+y;
    correction=(next-sum)-y;sum=next;
}
bool finite(float x) { return !isnan(x)&&!isinf(x); }
bool wet(vec4 a,vec4 b) { return a.z>0.001&&b.z<0.5; }
float ulp(float x) { uint e=(floatBitsToUint(abs(x))>>23u)&255u;return e==0u?uintBitsToFloat(1u):exp2(float(int(e)-127-23)); }
vec4 before(uint j) { return vec4(input_cells[j].bed_water.zw,input_cells[j].flow.xy); }
void load_tile(uint base) {
    v[lane]=input_cells[base+lane].bed_water; f[lane]=input_cells[base+lane].flow;
    o[lane]=output_cells[base+lane];barrier();
}
void main() {
    count=params.size*params.size;lane=gl_LocalInvocationID.x;area=params.cell_size*params.cell_size;
    if(lane==0u) { bad=0u;wet_count=0u;full_row=0u;receipt[27]=0u; } barrier();
    for(uint j=lane;j<count;j+=64u) {
        vec4 a=input_cells[j].bed_water,b=input_cells[j].flow;
        if(!finite(a.x)||!finite(a.y)||!finite(a.z)||!finite(a.w)||!finite(b.x)||!finite(b.y)||!finite(b.z)||a.z<0.0||a.w<0.0) atomicOr(bad,1u);
    }
    // Every wet row segment reaches a wet vertical boundary. A complete wet
    // row connects both boundaries; this proves one component, even with holes.
    for(uint row=lane;row<params.size;row+=64u) {
        bool seen_dry=false,ended_dry=false;uint members=0u;
        for(uint x=0u;x<params.size;x++) {
            uint j=row*params.size+x;
            bool w=wet(input_cells[j].bed_water,input_cells[j].flow);
            if((x==0u||x+1u==params.size)&&!w) atomicOr(bad,1u);
            if(w) { members++;if(seen_dry) ended_dry=true; }
            else { if(ended_dry) atomicOr(bad,1u);seen_dry=true; }
        }
        atomicAdd(wet_count,members);
        if(members==params.size) atomicOr(full_row,1u);
    }
    barrier();if(bad!=0u||full_row==0u) return; // unsupported topology uses original BFS
    for(uint j=lane;j<count;j+=64u) output_cells[j]=before(j);
    if(lane==0u) {
        for(uint j=0u;j<32u;j++) receipt[j]=0u;
        receipt[27]=1u;receipt[2]=1u;receipt[11]=wet_count;
        eta=-3.402823466e38;demand=0.0;dc=0.0;capacity=0.0;cc=0.0;
        actual=0.0;ac=0.0;sed=0.0;sc=0.0;qx=0.0;qxc=0.0;qz=0.0;qzc=0.0;
        loss_x=0.0;lxc=0.0;loss_z=0.0;lzc=0.0;
    } barrier();
    for(uint base=0u;base<count;base+=64u) {
        load_tile(base);
        if(lane==0u) for(uint k=0u;k<64u;k++) if(wet(v[k],f[k])) eta=max(eta,v[k].x+v[k].z);
        barrier();
    }
    if(lane==0u) eta+=0.02;barrier();
    for(uint base=0u;base<count;base+=64u) {
        load_tile(base);
        if(lane==0u) for(uint k=0u;k<64u;k++) {
            if(!wet(v[k],f[k])) continue;
            if(v[k].y>v[k].x) add(demand,dc,min(v[k].z,max(0.0,v[k].y-v[k].x))*area);
            else add(capacity,cc,max(0.0,eta-v[k].y-v[k].z)*area);
        } barrier();
    }
    if(demand==0.0) { if(lane==0u) receipt[0]=1u;return; }
    if(lane==0u&&capacity<demand) receipt[3]=1u;barrier();
    for(uint base=0u;base<count;base+=64u) {
        load_tile(base);
        vec4 old=vec4(v[lane].zw,f[lane].xy);
        precise vec4 result=old; // match scalar oracle's propagated NoContraction
        float dry_x=0.0,dry_z=0.0;
        if(wet(v[lane],f[lane])&&v[lane].y>v[lane].x) {
            float fraction=min(demand,capacity)/demand;
            result.x=max(0.0,old.x-min(v[lane].z,max(0.0,v[lane].y-v[lane].x))*fraction);
            float depth=old.x-result.x,proportion=depth/old.x;
            result.yzw=old.yzw*(1.0-proportion);
            if(result.x<=0.001) { dry_x=result.z;dry_z=result.w;result.zw=vec2(0.0); }
        }
        o[lane]=result;dry_loss[lane]=vec2(dry_x,dry_z);barrier();
        if(lane==0u) for(uint k=0u;k<64u;k++) {
            if(!wet(v[k],f[k])||v[k].y<=v[k].x) continue;
            vec4 b=vec4(v[k].zw,f[k].xy),r=o[k];
            if(r.x<=0.001) { add(loss_x,lxc,dry_loss[k].x*area);add(loss_z,lzc,dry_loss[k].y*area); }
            add(actual,ac,(b.x-r.x)*area);add(sed,sc,(b.y-r.y)*area);
            add(qx,qxc,(b.z-r.z-dry_loss[k].x)*area);add(qz,qzc,(b.w-r.w-dry_loss[k].y)*area);
        } barrier();output_cells[base+lane]=o[lane];barrier();
    }
    for(uint j=lane;j<count;j+=64u) {
        vec4 a=input_cells[j].bed_water;
        if(!wet(a,input_cells[j].flow)) continue;
        if(a.y<=a.x&&capacity>0.0) {
            float room=max(0.0,eta-a.y-a.z)*area,share=room/capacity;
            output_cells[j]+=vec4(actual,sed,qx,qz)*share/area;
        }
        if(params.pad0==1u) output_cells[j].x=0.0;
    } barrier();
    if(lane==0u) { residual=0.0;ec=0.0; } barrier();
    for(uint base=0u;base<count;base+=64u) {
        load_tile(base);
        if(lane==0u) for(uint k=0u;k<64u;k++) if(wet(v[k],f[k])) add(residual,ec,(o[k].x-v[k].z)*area);
        barrier();
    }
    if(lane==0u) receipt[14]=floatBitsToUint(abs(residual));barrier();
    for(uint base=0u;base<count;base+=64u) {
        load_tile(base);
        if(lane==0u) for(uint k=0u;k<64u&&abs(residual)>1e-8;k++) {
            if(!wet(v[k],f[k])||v[k].y>v[k].x) continue;
            float old=o[k].x,limit=max(1e-7,8.0*ulp(max(abs(v[k].z),abs(old))));
            float step=clamp(-residual/area,-limit,limit);
            float corrected=clamp(old+step,v[k].z,max(v[k].z,eta-v[k].y));
            o[k].x=corrected;residual+=(corrected-old)*area;
            if(corrected!=old) receipt[15]++;
            receipt[16]=floatBitsToUint(max(uintBitsToFloat(receipt[16]),abs(corrected-old)));
        } barrier();output_cells[base+lane]=o[lane];barrier();
    }
    if(lane==0u) { wquant=0.0;wqc=0.0;squant=0.0;sqc=0.0;wabs=0.0;wac=0.0;sabs=0.0;sac=0.0;serror=0.0;sec=0.0;bad=0u; } barrier();
    for(uint base=0u;base<count;base+=64u) {
        load_tile(base);
        if(lane==0u) for(uint k=0u;k<64u;k++) {
            if(!wet(v[k],f[k])) continue;
            vec4 b=vec4(v[k].zw,f[k].xy),r=o[k];
            if(!finite(r.x)||!finite(r.y)||!finite(r.z)||!finite(r.w)||r.x<0.0||r.y<0.0) bad=1u;
            add(wquant,wqc,2.0*ulp(max(abs(b.x),abs(r.x)))*area);
            add(squant,sqc,2.0*ulp(max(abs(b.y),abs(r.y)))*area);
            add(wabs,wac,abs(r.x-b.x)*area);add(sabs,sac,abs(r.y-b.y)*area);add(serror,sec,(r.y-b.y)*area);
        } barrier();
    }
    if(lane==0u) {
        float u=5.9604644775390625e-8;
        float wb=max(1e-7,wquant+max(1e-8,(4.0*u+2.0*float(wet_count)*u*u)*wabs));
        float sb=max(1e-7,squant+max(1e-8,(4.0*u+2.0*float(wet_count)*u*u)*sabs));
        receipt[8]=floatBitsToUint(abs(residual));receipt[9]=floatBitsToUint(abs(serror));receipt[12]=floatBitsToUint(wb);
        if(abs(residual)>wb||abs(serror)>sb) bad=1u;
        if(bad!=0u) { receipt[0]=2u;receipt[1]=4u; }
        else { receipt[0]=1u;receipt[4]=floatBitsToUint(actual);receipt[5]=floatBitsToUint(max(0.0,demand-actual));receipt[6]=floatBitsToUint(loss_x);receipt[7]=floatBitsToUint(loss_z); }
    } barrier();
    if(bad!=0u) for(uint j=lane;j<count;j+=64u) output_cells[j]=before(j);
}

