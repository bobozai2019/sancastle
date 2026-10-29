shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D template_texture : filter_linear, repeat_disable;
uniform float height_m = 0.7;
uniform vec4 tint : source_color = vec4(0.25, 1.0, 0.55, 0.4);
varying vec2 template_uv;
void vertex() {
 template_uv=((VERTEX.xz+2.0)/4.0*64.0+0.5)/65.0;
 VERTEX.y=textureLod(template_texture,template_uv,0.0).r*height_m+0.025;
}
void fragment(){ALBEDO=tint.rgb;ALPHA=tint.a*step(0.5,texelFetch(template_texture,ivec2(floor(template_uv*65.0)),0).g);}
