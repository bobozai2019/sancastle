#[compute]
#version 450
layout(local_size_x=1) in;
layout(set=0,binding=0,std430) readonly buffer Command { uint c[]; };
layout(set=0,binding=1,std430) readonly buffer Cells { vec4 cells[]; };
layout(set=0,binding=2,std430) buffer State { uint s[]; };
layout(set=0,binding=3,std430) buffer Receipt { uint r[]; };
layout(push_constant,std430) uniform Params { uint mode; uint x; uint z; uint width; uint height; uint pad0; uint pad1; uint pad2; } params;
uint cell_index(uint lane,uint n) { return (params.z+lane/params.width)*n+params.x+lane%params.width; }
void add(inout float sum,inout float correction,float value) {
    precise float y=value-correction;
    precise float next=sum+y;
    correction=(next-sum)-y;
    sum=next;
}
bool finite(float v) { return !isnan(v)&&!isinf(v); }
void reject(uint error,uint flags) {
    r[12]=2u; r[13]=error; r[22]=flags; r[14]=0u;
    r[8]=c[8]; r[9]=c[9];
    for(uint j=16u;j<=21u;j++) r[j]=0u;
    r[24]=0u;
}
float ulp(float v) {
    uint bits=floatBitsToUint(abs(v));
    uint exponent=(bits>>23u)&255u;
    return exponent==0u?uintBitsToFloat(1u):exp2(float(int(exponent)-127-23));
}
void main() {
    uint n=c[20], count=params.width*params.height;
    float area=uintBitsToFloat(c[19])*uintBitsToFloat(c[19]);
    float eps=uintBitsToFloat(c[22]);
    precise float sum=0.0, correction=0.0;
    if(params.mode==0u) {
        for(uint j=0u;j<32u;j++) r[j]=0u;
        for(uint j=0u;j<6u;j++) r[j]=c[j];
        r[6]=c[8]; r[7]=c[9]; r[8]=c[8]; r[9]=c[9];
        r[10]=c[6]; r[11]=c[7]; r[12]=1u;
        if(c[4]!=s[8]||c[5]!=s[9]) { reject(5u,8u); return; }
        if(c[8]!=s[10]||c[9]!=s[11]) { reject(7u,8u); return; }
        for(uint j=12u;j<=19u;j++) if(!finite(uintBitsToFloat(c[j]))) { reject(1u,1u); return; }
        float radius=uintBitsToFloat(c[16]), strength=uintBitsToFloat(c[17]), amount=uintBitsToFloat(c[18]);
        if(radius<=0.0||radius>4.0||strength<0.0||strength>1.0||amount<=0.0||c[10]>1u||c[11]>1u||c[21]>3u||c[28]>1u||(c[28]==1u&&c[10]!=1u)) { reject(1u,0u); return; }
        if(c[21]>=2u&&!finite(uintBitsToFloat(c[27]))) { reject(1u,1u);return; }
        if(c[21]>=2u&&abs(uintBitsToFloat(c[27]))>1.0) { reject(1u,0u);return; }
        float request=amount*strength;
        if(!finite(request)) { reject(1u,1u); return; }
        s[0]=floatBitsToUint(request); s[1]=s[0]; s[4]=0u;
        int xmin=int(n), zmin=int(n), xmax=-1, zmax=-1;
        for(uint lane=0u;lane<count;lane++) {
            uint i=cell_index(lane,n);
            vec4 cell=cells[i];
            if(!finite(cell.y)||cell.y<0.0) { reject(7u,cell.y<0.0?2u:1u); return; }
            if(cell.x<=0.0) continue;
            add(sum,correction,cell.x);
            int x=int(i%n),z=int(i/n);
            xmin=min(xmin,x); xmax=max(xmax,x); zmin=min(zmin,z); zmax=max(zmax,z);
            uint per=n/32u, cx=uint(x)/32u, cz=uint(z)/32u;
            uint chunk=cz*per+cx;
            r[20u+chunk/32u]|=1u<<(chunk%32u);
            if(x%32==0&&cx>0u) { uint k=chunk-1u; r[20u+k/32u]|=1u<<(k%32u); }
            if(z%32==0&&cz>0u) { uint k=chunk-per; r[20u+k/32u]|=1u<<(k%32u); }
            if(x%32==0&&z%32==0&&cx>0u&&cz>0u) { uint k=chunk-per-1u; r[20u+k/32u]|=1u<<(k%32u); }
            r[24]++;
        }
        s[2]=floatBitsToUint(sum);
        r[16]=uint(xmin); r[17]=uint(zmin); r[18]=uint(xmax-xmin+1); r[19]=uint(zmax-zmin+1);
        if(r[24]==0u) { reject(3u,0u); return; }
        if(c[10]==1u&&uintBitsToFloat(c[23])+eps<request) { reject(2u,0u); return; }
        return;
    }
    if(r[12]!=1u) return;
    if(params.mode==1u) {
        for(uint lane=0u;lane<count;lane++) { uint i=cell_index(lane,n); if(cells[i].x>0.0&&cells[i].y*area>eps) add(sum,correction,cells[i].x); }
        s[3]=floatBitsToUint(sum);
    } else if(params.mode==2u) {
        for(uint lane=0u;lane<count;lane++) { uint i=cell_index(lane,n); if(cells[i].x>0.0) add(sum,correction,cells[i].w); }
        s[1]=floatBitsToUint(uintBitsToFloat(s[1])-sum);
        s[4]=floatBitsToUint(uintBitsToFloat(s[4])+sum);
    } else {
        precise float quant=0.0,qc=0.0,absolute_sum=0.0,ac=0.0;
        uint changed=0u;
        for(uint lane=0u;lane<count;lane++) {
            uint i=cell_index(lane,n);
            vec4 cell=cells[i];
            if(cell.x<=0.0) continue;
            if(!finite(cell.y)||cell.y<0.0) { reject(7u,cell.y<0.0?2u:1u); return; }
            float delta=(cell.y-cell.z)*area;
            add(sum,correction,delta);
            add(absolute_sum,ac,abs(delta));
            // The frozen budget covers every weighted cell, including an increment
            // rounded back to before by R32F; changed-only loses that rounding term.
            changed++;
            add(quant,qc,2.0*ulp(max(abs(cell.y),abs(cell.z)))*area);
        }
        float actual=abs(sum);
        float nominal=c[10]==1u?uintBitsToFloat(s[0]):uintBitsToFloat(s[4]);
        float u=5.9604644775390625e-8;
        float reduction=max(1e-8,(4.0*u+2.0*float(changed)*u*u)*absolute_sum);
        float budget=max(1e-7,quant+reduction);
        if(!finite(actual)||abs(actual-nominal)>budget||(c[10]==1u&&actual>uintBitsToFloat(c[23])+eps)) { reject(7u,4u); return; }
        r[14]=floatBitsToUint(actual); r[15]=floatBitsToUint(nominal);
        r[8]=c[8]+1u; r[9]=c[9]+uint(r[8]==0u);
    }
}
