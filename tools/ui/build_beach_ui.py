"""Build original vector UI assets and apply static beach scene styling."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/ui/beach'
OUT.mkdir(parents=True, exist_ok=True)
def write(path, text):
    path.write_text(text, encoding='utf-8')

# Original, deliberately slightly irregular ink silhouettes, not extracted art.
drawings = {
 'Dig':'<path fill="#cab16c" d="M8 49 Q19 31 30 43 L48 52Z"/><path fill="#9cbec0" d="m16 29 10-10 10 11-7 11q-10 1-13-12Z"/><path d="m30 25 14-15m-4-5 10 10"/>',
 'Fill':'<path fill="#e1bd68" d="m7 50 18-21 10 11 6-4 15 15Z"/><path d="M44 6v20m-7-7 7 8 7-8"/>',
 'Castle':'<path fill="#d8b66b" d="m10 51 3-32h9v7h7v-9h8v9h7v-7h8l3 32Z"/><path fill="#fff5d6" d="M26 51V39q6-10 12 0v12"/><path d="M30 16V5"/><path fill="#e38159" d="m31 5 13 4-13 5Z"/>',
 'Shovel':'<path fill="#98b7b3" d="m10 37 12-8 12 13-12 13q-12 0-12-18Z"/><path d="m27 34 14-17"/><path fill="#dfb66b" d="m36 8 8-4 9 8-6 9Z"/>',
 'Wall':'<path fill="#d5b16a" d="m9 47 5-29 36-6 5 30-37 10Z"/><path d="m14 18 8 8 28-6M22 26l-4 26m10-27-2 24m13-26 2 23M20 36l33-5"/>',
 'SuspendedSand':'<path fill="#d7b66e" d="m17 8 24 3-5 16-20-4Z"/><path d="m22 31-3 3m12-1 1 3m-8 5 1 2m13-7 2 3"/><path stroke="#258e91" d="M7 49q7-8 15 0t16 0 17 0"/>',
 'GravelDrop':'<path fill="#b2b2a1" d="m7 44 8-10 11 4 1 13-13 3Zm26-4 12-7 10 10-5 10-13-1ZM25 13l11-4 9 8-5 11-13-2Z"/>',
 'Smooth':'<path fill="#dbba72" d="M7 47q12-22 25-8t25 6v8H7Z"/><path d="M12 19h39m-7-6 8 6-8 6M20 15v8"/>',
 'Compact':'<path fill="#dec18b" d="M14 37h36v13H14Z"/><path d="M32 11v24m-9-10 9 10 9-10M9 55h46"/>',
 'bottle':'<path fill="#a1d5c8" d="m25 15-7 11 3 27h23l3-27-8-11V8H25Z"/><path fill="#e5bc77" d="M24 6h16v8H24Z"/><path fill="#fff3d4" d="M20 31h25v13H20Z"/>',
 'plank':'<path fill="#c49b61" d="m8 24 39-12 9 27-39 13Z"/><path d="m17 29 29-9M21 43l28-10m-17-8-6 9 10-2"/>',
 'stick':'<path fill="#be9862" d="m9 48 18-22 5-17 7 2-2 15 13-5 3 7-19 8-17 17Z"/>',
 'wave':'<path fill="#81c9c3" d="M7 48q16 1 19-20T49 15q-18 0-13 16t20 8v14H7Z"/><path d="M9 56h44"/>',
 'travel':'<path fill="#ecd99e" d="m7 15 16-6 18 7 15-6v39l-15 6-18-7-16 6Z"/><path d="M23 9v39m18-32v39"/><path stroke="#258e91" d="m15 31 17-7 15 12"/>',
}
for name, body in drawings.items():
    write(OUT / (name+'.svg'), '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><g stroke="#34382f" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" fill="none">'+body+'</g></svg>')
write(OUT/'paper.svg', '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"><path fill="#faf3d9" stroke="#b9b397" stroke-width="1" d="M5 4 39 6 82 3 123 5 125 45 123 85 125 123 83 125 42 123 4 125 5 83 3 45Z"/><path stroke="#bfc3aa" d="M21 7v114"/>'+''.join(f'<circle cx="12" cy="{y}" r="2.7" fill="#999f87"/>' for y in range(16,120,13))+'</svg>')

def style(name, color, border, radius=12):
    return f'\n[sub_resource type="StyleBoxFlat" id="{name}"]\n' + '\n'.join([
        'content_margin_left = 10.0','content_margin_right = 10.0','content_margin_top = 7.0','content_margin_bottom = 7.0',
        f'bg_color = Color({color})',*[f'border_width_{s} = 2' for s in ('left','top','right','bottom')],f'border_color = Color({border})',
        *[f'corner_radius_{s} = {radius}' for s in ('top_left','top_right','bottom_left','bottom_right')],
        'shadow_color = Color(0.17, 0.19, 0.14, 0.18)','shadow_size = 3','shadow_offset = Vector2(0, 2)'])+'\n'
theme='''[gd_resource type="Theme" load_steps=9 format=3]
[ext_resource type="Texture2D" path="res://assets/ui/beach/paper.svg" id="paper"]
[sub_resource type="SystemFont" id="font"]
font_names = PackedStringArray("Microsoft YaHei UI")
allow_system_fallback = false
[sub_resource type="StyleBoxTexture" id="paper"]
texture = ExtResource("paper")
texture_margin_left = 25.0
texture_margin_right = 9.0
texture_margin_top = 9.0
texture_margin_bottom = 9.0
content_margin_left = 12.0
content_margin_right = 4.0
content_margin_top = 4.0
content_margin_bottom = 4.0
'''
for args in [('normal','0.94, 0.84, 0.58, 1','0.83, 0.72, 0.46, 1'),('hover','1, 0.93, 0.70, 1','0.25, 0.46, 0.40, 1'),('pressed','0.30, 0.78, 0.70, 1','0.12, 0.37, 0.32, 1'),('disabled','0.85, 0.83, 0.72, 1','0.73, 0.73, 0.63, 1'),('focus','0.98, 0.94, 0.78, 0','0.19, 0.52, 0.46, 1')]:
    theme+=style(*args)
theme+='\n[resource]\ndefault_font = SubResource("font")\ndefault_font_size = 14\nPanelContainer/styles/panel = SubResource("paper")\nPopupMenu/styles/panel = SubResource("paper")\n'
for kind in ['Button','OptionButton','MenuButton']:
    for state in ['normal','hover','pressed','disabled','focus']:
        theme+=f'{kind}/styles/{state} = SubResource("{state}")\n'
    theme+=f'{kind}/styles/hover_pressed = SubResource("pressed")\n'
    for state in ['font_color','font_hover_color','font_pressed_color','font_focus_color','font_hover_pressed_color']:
        theme+=f'{kind}/colors/{state} = Color(0.18, 0.22, 0.18, 1)\n'
    theme+=f'{kind}/colors/font_disabled_color = Color(0.43, 0.44, 0.38, 1)\n'
theme+='Label/colors/font_color = Color(0.22, 0.26, 0.21, 1)\nPopupMenu/colors/font_color = Color(0.18, 0.22, 0.18, 1)\nPopupMenu/colors/font_hover_color = Color(0.12, 0.29, 0.25, 1)\nPopupMenu/styles/hover = SubResource("hover")\n'
write(OUT/'beach_theme.tres', theme)

def setprop(block,key,value):
    pat=r'^'+re.escape(key)+r' = .*?$'
    if re.search(pat,block,re.M): return re.sub(pat,lambda _:key+' = '+value,block,flags=re.M)
    return block.rstrip()+'\n'+key+' = '+value+'\n\n'
paths=['scenes/components/beach_ui.tscn','scenes/components/floating_props_panel.tscn']
for rel in paths:
    path=ROOT/rel
    text=path.read_text(encoding='utf-8')
    backup=ROOT/'test_output/ui_restyle'/path.name
    backup.parent.mkdir(parents=True, exist_ok=True)
    if not backup.exists(): write(backup,text)
    text=re.sub(r' load_steps=\d+','',text,count=1)
    resources='[ext_resource type="Theme" path="res://assets/ui/beach/beach_theme.tres" id="beach_theme"]\n'
    for name in drawings: resources+=f'[ext_resource type="Texture2D" path="res://assets/ui/beach/{name}.svg" id="icon_{name}"]\n'
    text=re.sub(r'^\[ext_resource [^\n]*id="(?:beach_theme|icon_[^"]+)"\]\n','',text,flags=re.M)
    first=text.index('\n')
    text=text[:first+1]+resources+text[first+1:]
    chunks=re.split(r'(?=^\[)',text,flags=re.M)
    for i,b in enumerate(chunks):
        if not b.startswith('[node '):continue
        header=b.split('\n')[0]
        name=re.search(r'name="([^"]+)"',header)[1]
        is_brush='ShapeBrushPanel' in header or rel.endswith('brush_tool_panel.tscn')
        if (name in ['EditPanel','ShapeBrushPanel','FloatingPropsPanel','SceneSwitcher','ToggleUI','StatusLabel']):
            b=setprop(b,'theme','ExtResource("beach_theme")')
            b=re.sub(r'^theme_override_styles/panel = .*\n','',b,flags=re.M)
        if name=='ShapeBrushPanel':
            for k,v in {'anchor_left':'0.5','anchor_right':'0.5','anchor_top':'1.0','anchor_bottom':'1.0','offset_left':'-356.0','offset_right':'356.0','offset_top':'-188.0','offset_bottom':'-18.0','grow_horizontal':'2','grow_vertical':'0','custom_minimum_size':'Vector2(712, 0)'}.items(): b=setprop(b,k,v)
        if name=='Tools' and is_brush:b=setprop(b,'columns','9')
        if name in drawings and is_brush:
            for k,v in {'icon':f'ExtResource("icon_{name}")','icon_alignment':'1','vertical_icon_alignment':'0','expand_icon':'true','theme_override_constants/icon_max_width':'42','custom_minimum_size':'Vector2(68, 78)','theme_override_font_sizes/font_size':'13'}.items():b=setprop(b,k,v)
        if name=='Title' and is_brush:b=setprop(b,'text','"沙滩工具"');b=setprop(b,'theme_override_font_sizes/font_size','16')
        if name in ['Help','BrushStatus'] and is_brush:b=setprop(b,'theme_override_font_sizes/font_size','12')
        if name=='EditPanel':
            b=setprop(b,'offset_left','-324.0');b=setprop(b,'offset_top','66.0');b=setprop(b,'offset_bottom','400.0')
        if name=='ParameterWindows':b=setprop(b,'flat','false')
        if name=='Targets':
            b=setprop(b,'popup/item_1/text','"潮汐沙滩 · test1"')
            b=setprop(b,'custom_minimum_size','Vector2(0, 38)')
        if name=='Switch':b=setprop(b,'text','"出发"')
        if name=='TriggerWave':b=setprop(b,'icon','ExtResource("icon_wave")');b=setprop(b,'theme_override_constants/icon_max_width','28');b=setprop(b,'expand_icon','true')
        if name=='Title' and '/EditPanel/' in header:b=setprop(b,'text','"沙滩旅行"')
        if name=='FloatingPropsPanel':
            for k,v in {'offset_left':'18.0','offset_top':'100.0','offset_right':'322.0','offset_bottom':'400.0'}.items():b=setprop(b,k,v)
        if name in ['Slot1','Slot2','Slot3']:
            icon={'Slot1':'bottle','Slot2':'plank','Slot3':'stick'}[name]
            for k,v in {'icon':f'ExtResource("icon_{icon}")','icon_alignment':'1','vertical_icon_alignment':'0','expand_icon':'true','theme_override_constants/icon_max_width':'40','custom_minimum_size':'Vector2(86, 94)'}.items():b=setprop(b,k,v)
        if name=='Title' and rel.endswith('floating_props_panel.tscn'):b=setprop(b,'text','"海边拾趣"')
        if name=='StatusLabel':
            b=setprop(b,'theme_override_font_sizes/font_size','14')
            b=setprop(b,'mouse_filter','2')
        chunks[i]=b
    write(path,''.join(chunks))

print('Built original beach UI assets and styled the shared UI base and prop panel.')
