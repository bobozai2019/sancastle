#[compute]
#version 450
layout(local_size_x=1) in;
// Setup-only probe input: old bed/new bed/h/sediment, qx/qz/obstacle/reserved.
struct InputCell { vec4 bed_water; vec4 flow; };
layout(set=0,binding=0,std430) readonly buffer Input { InputCell input_cells[]; };
layout(set=0,binding=1,std430) buffer Candidate { vec4 output_cells[]; };
// label, BFS queue, component head, tail, row-major next; each segment has N cells.
layout(set=0,binding=2,std430) buffer Scratch { int scratch[]; };
layout(set=0,binding=3,std430) buffer Receipt { uint receipt[]; };
layout(push_constant,std430) uniform Params { uint size; float cell_size; uint pad0; uint pad1; } params;
uint count;
float area;
void add(inout float sum,inout float correction,float v) {
    precise float y=v-correction;
    precise float next=sum+y;
    correction=(next-sum)-y;
    sum=next;
}
bool finite(float v) { return !isnan(v)&&!isinf(v); }
float ulp(float v) {
    uint e=(floatBitsToUint(abs(v))>>23u)&255u;
    return e==0u?uintBitsToFloat(1u):exp2(float(int(e)-127-23));
}
vec4 before(uint i) { return vec4(input_cells[i].bed_water.zw,input_cells[i].flow.xy); }
bool wet(uint i) { return input_cells[i].bed_water.z>0.001&&input_cells[i].flow.z<0.5; }
float demand_depth(uint i) { vec4 v=input_cells[i].bed_water; return min(v.z,max(0.0,v.y-v.x)); }
void reject(uint error) {
    for(uint i=0u;i<count;i++) output_cells[i]=before(i);
    receipt[0]=2u; receipt[1]=error;
}
void main() {
    if(params.pad1==2u&&receipt[27]==1u) return; // proven full-wet candidate already processed
    count=params.size*params.size; area=params.cell_size*params.cell_size;
    for(uint j=0u;j<32u;j++) receipt[j]=0u;
    for(uint i=0u;i<count;i++) {
        output_cells[i]=before(i); scratch[i]=-1; scratch[2u*count+i]=-1; scratch[3u*count+i]=-1; scratch[4u*count+i]=-1;
        vec4 v=input_cells[i].bed_water, f=input_cells[i].flow;
        if(!finite(v.x)||!finite(v.y)||!finite(v.z)||!finite(v.w)||!finite(f.x)||!finite(f.y)||!finite(f.z)) { reject(1u); return; }
        if(v.z<0.0||v.w<0.0) { reject(2u); return; }
    }
    if(params.pad1==1u) { receipt[0]=1u; return; } // velocity-only: preserve depth and carried sand
    uint components=0u;
    for(uint seed=0u;seed<count;seed++) {
        if(scratch[seed]>=0||!wet(seed)) continue;
        uint head=0u,tail=1u;
        scratch[count]=int(seed); scratch[seed]=int(components);
        while(head<tail) {
            uint i=uint(scratch[count+head++]);
            int neighbors[4]=int[4](i%params.size>0u?int(i)-1:-1,i%params.size+1u<params.size?int(i)+1:-1,
                i>=params.size?int(i-params.size):-1,i+params.size<count?int(i+params.size):-1);
            for(uint k=0u;k<4u;k++) {
                int j=neighbors[k];
                if(j>=0&&scratch[j]<0&&wet(uint(j))) {
                    if(tail>=count) { reject(8u); return; }
                    scratch[j]=int(components); scratch[count+tail++]=j;
                }
            }
        }
        receipt[11]=max(receipt[11],tail);
        components++;
    }
    // Linked lists are assembled in row-major order, independent of BFS visitation.
    for(uint i=0u;i<count;i++) {
        int label=scratch[i]; if(label<0) continue;
        int tail=scratch[3u*count+uint(label)];
        if(tail<0) scratch[2u*count+uint(label)]=int(i);
        else scratch[4u*count+uint(tail)]=int(i);
        scratch[3u*count+uint(label)]=int(i);
    }
    precise float total_moved=0.0,mc=0.0,total_retained=0.0,rc=0.0,loss_x=0.0,lxc=0.0,loss_z=0.0,lzc=0.0;
    for(uint component=0u;component<components;component++) {
        float eta=-3.402823466e38;
        for(int j=scratch[2u*count+component];j>=0;j=scratch[4u*count+uint(j)]) {
            vec4 v=input_cells[j].bed_water; eta=max(eta,v.x+v.z);
        }
        eta+=0.02;
        precise float demand=0.0,dc=0.0,capacity=0.0,cc=0.0;
        for(int j=scratch[2u*count+component];j>=0;j=scratch[4u*count+uint(j)]) {
            vec4 v=input_cells[j].bed_water;
            if(v.y>v.x) add(demand,dc,demand_depth(uint(j))*area);
            else add(capacity,cc,max(0.0,eta-v.y-v.z)*area);
        }
        float moved=min(demand,capacity), fraction=demand>0.0?moved/demand:0.0;
        if(demand==0.0) continue;
        if(capacity<demand) receipt[3]=1u;
        precise float actual=0.0,ac=0.0,sed=0.0,sc=0.0,qx=0.0,qxc=0.0,qz=0.0,qzc=0.0;
        for(int j=scratch[2u*count+component];j>=0;j=scratch[4u*count+uint(j)]) {
            uint i=uint(j); vec4 v=input_cells[i].bed_water;
            if(v.y<=v.x) continue;
            vec4 old=before(i), result=old;
            result.x=max(0.0,old.x-demand_depth(i)*fraction);
            float actual_depth=old.x-result.x, proportion=actual_depth/old.x;
            result.yzw=old.yzw*(1.0-proportion);
            float dry_x=0.0,dry_z=0.0;
            if(result.x<=0.001) {
                dry_x=result.z; dry_z=result.w; result.zw=vec2(0.0);
                add(loss_x,lxc,dry_x*area); add(loss_z,lzc,dry_z*area);
            }
            output_cells[i]=result;
            add(actual,ac,actual_depth*area); add(sed,sc,(old.y-result.y)*area);
            add(qx,qxc,(old.z-result.z-dry_x)*area); add(qz,qzc,(old.w-result.w-dry_z)*area);
        }
        for(int j=scratch[2u*count+component];j>=0;j=scratch[4u*count+uint(j)]) {
            uint i=uint(j); vec4 v=input_cells[i].bed_water;
            if(v.y>v.x||capacity<=0.0) continue;
            float room=max(0.0,eta-v.y-v.z)*area;
            float share=room/capacity;
            output_cells[i]+=vec4(actual,sed,qx,qz)*share/area;
        }
        // Residual is calculated from R32F-equivalent candidates, then bounded
        // by available receiver room. No donor or other wet component is used.
        // Test-only corruption, default zero; validates rejection without sinks.
        if(params.pad0==1u) {
            for(int j=scratch[2u*count+component];j>=0;j=scratch[4u*count+uint(j)]) output_cells[j].x=0.0;
        }
        precise float residual=0.0,ec=0.0;
        for(int j=scratch[2u*count+component];j>=0;j=scratch[4u*count+uint(j)]) add(residual,ec,(output_cells[j].x-before(uint(j)).x)*area);
        receipt[14]=floatBitsToUint(max(uintBitsToFloat(receipt[14]),abs(residual)));
        for(int j=scratch[2u*count+component];j>=0&&abs(residual)>1e-8;j=scratch[4u*count+uint(j)]) {
            uint i=uint(j); vec4 v=input_cells[i].bed_water;
            if(v.y>v.x) continue;
            float old=output_cells[i].x;
            // Preserve the frozen per-cell distribution budget as well as the
            // volume budget: one cell must not absorb a whole component's ULPs.
            float limit=max(1e-7,8.0*ulp(max(abs(v.z),abs(old))));
            float step=clamp(-residual/area,-limit,limit);
            float corrected=clamp(old+step,v.z,max(v.z,eta-v.y));
            output_cells[i].x=corrected;
            residual+=(corrected-old)*area;
            if(corrected!=old) receipt[15]++;
            receipt[16]=floatBitsToUint(max(uintBitsToFloat(receipt[16]),abs(corrected-old)));
        }
        precise float water_quant=0.0,wqc=0.0,sed_quant=0.0,sqc=0.0,water_abs=0.0,wac=0.0,sed_abs=0.0,sac=0.0,sed_error=0.0,sec=0.0;
        uint touched=0u;
        for(int j=scratch[2u*count+component];j>=0;j=scratch[4u*count+uint(j)]) {
            vec4 old=before(uint(j)), value=output_cells[j];
            if(!finite(value.x)||!finite(value.y)||!finite(value.z)||!finite(value.w)||value.x<0.0||value.y<0.0) { reject(4u); return; }
            touched++;
            add(water_quant,wqc,2.0*ulp(max(abs(old.x),abs(value.x)))*area);
            add(sed_quant,sqc,2.0*ulp(max(abs(old.y),abs(value.y)))*area);
            add(water_abs,wac,abs(value.x-old.x)*area); add(sed_abs,sac,abs(value.y-old.y)*area);
            add(sed_error,sec,(value.y-old.y)*area);
        }
        float u=5.9604644775390625e-8;
        float water_budget=max(1e-7,water_quant+max(1e-8,(4.0*u+2.0*float(touched)*u*u)*water_abs));
        float sed_budget=max(1e-7,sed_quant+max(1e-8,(4.0*u+2.0*float(touched)*u*u)*sed_abs));
        receipt[8]=floatBitsToUint(max(uintBitsToFloat(receipt[8]),abs(residual)));
        receipt[9]=floatBitsToUint(max(uintBitsToFloat(receipt[9]),abs(sed_error)));
        receipt[12]=floatBitsToUint(max(uintBitsToFloat(receipt[12]),water_budget));
        if(abs(residual)>water_budget||abs(sed_error)>sed_budget) { reject(4u); return; }
        add(total_moved,mc,actual); add(total_retained,rc,max(0.0,demand-actual));
    }
    receipt[0]=1u; receipt[2]=components;
    receipt[4]=floatBitsToUint(total_moved); receipt[5]=floatBitsToUint(total_retained);
    receipt[6]=floatBitsToUint(loss_x); receipt[7]=floatBitsToUint(loss_z);
}
