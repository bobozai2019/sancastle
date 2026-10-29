shader_type canvas_item;
uniform sampler2D foam_state: filter_nearest;
uniform sampler2D front_state: filter_nearest;
uniform sampler2D gravel_state: filter_nearest;
uniform int mode=0;
void fragment(){
 if(mode==0){vec2 v=texelFetch(foam_state,ivec2(192,128),0).rg;COLOR=vec4(v,0,1);}
 else if(mode==1){vec2 v=texelFetch(front_state,ivec2(192,128),0).rg;COLOR=vec4(v.x/32.0,v.y,0,1);}
 else {vec4 v=texelFetch(gravel_state,ivec2(17,0),0);COLOR=vec4(v.x/32.0+0.5,v.z/32.0+0.5,v.w,1);}
}
