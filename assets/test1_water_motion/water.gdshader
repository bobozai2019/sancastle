shader_type spatial;
render_mode unshaded,cull_disabled,depth_draw_never;
uniform sampler2D water_field : filter_linear,repeat_disable;
uniform sampler2D normal_texture : filter_linear_mipmap,repeat_enable;
uniform sampler2D screen_texture : hint_screen_texture,filter_linear_mipmap,repeat_disable;
uniform float visual_clock=90.16482543945312;
uniform bool debug_flow=false;
varying vec3 world;
void vertex() {
 vec2 e=vec2(1.0/512.0,1.0/256.0);
 vec4 c=texture(water_field,UV),l=texture(water_field,UV-vec2(e.x,0)),r=texture(water_field,UV+vec2(e.x,0)),t=texture(water_field,UV-vec2(0,e.y)),b=texture(water_field,UV+vec2(0,e.y));
 float yl=l.w+max(l.z-.05,0.0),yr=r.w+max(r.z-.05,0.0),yt=t.w+max(t.z-.05,0.0),yb=b.w+max(b.z-.05,0.0);
 VERTEX.y=(yl+yr+yt+yb)*.25+0.001;
 NORMAL=normalize(vec3(-(yr-yl)/0.1171875,1.0,(yb-yt)/0.1171875));world=(MODEL_MATRIX*vec4(VERTEX,1)).xyz;
}
void fragment() {
 vec4 c=texture(water_field,UV);float h=max(c.z-.05,0.0);if(h<.00001) discard;
 vec2 flow=clamp(vec2(c.x,-c.y),vec2(-.5),vec2(.5));
 float phase=texture(normal_texture,world.xz*vec2(1,-1)*.05).b+.8*visual_clock;
 float a=fract(phase),b=fract(phase+.5);
 vec2 p=world.xz*vec2(1,-1);
 vec2 na=texture(normal_texture,(p-vec2(flow.x,-flow.y)*(2.0*b-1.0))*.2+vec2(.25)).rg;
 vec2 nb=texture(normal_texture,(p-vec2(flow.x,-flow.y)*(2.0*a-1.0))*.2-vec2(.25)).rg;
 vec2 detail=(mix(nb,na,2.0*abs(a-.5))*2.0-1.0)*smoothstep(.008,.065,h);
 NORMAL=normalize(NORMAL+(VIEW_MATRIX*vec4(detail.x,0,-detail.y,0)).xyz);
 vec2 distortion=detail*.005*smoothstep(0.0,.08,h);
 vec3 bottom=texture(screen_texture,clamp(SCREEN_UV+distortion,vec2(.001),vec2(.999))).rgb;
 float path=h/max(abs(dot(normalize(VIEW),NORMAL)),.25);
 vec3 transmission=exp(-vec3(6.0,.856013,.336771)*path);
 vec3 color=bottom*vec3(.75897,.883854,.968461)*transmission;
 float fresnel=pow(1.0-clamp(dot(normalize(VIEW),NORMAL),0.0,1.0),5.0);
 color=mix(color,vec3(.491905,.710566,.848088),fresnel*.12);
 vec3 nworld=normalize(mat3(INV_VIEW_MATRIX)*NORMAL);
 vec3 view_world=normalize(CAMERA_POSITION_WORLD-world);
 float glint=pow(max(dot(reflect(-normalize(vec3(-.40,.80,.30)),nworld),view_world),0.0),1500.0);
 color+=vec3(glint);
 if(debug_flow) color=mix(vec3(.05,.30,.8),vec3(.95,.35,.08),smoothstep(-.2,.2,c.x));
 ALBEDO=color;ROUGHNESS=.025;METALLIC=0.0;SPECULAR=.3;ALPHA=1.0;
}
