"""Schili v2: original young tortoise mentor, authored from a fresh design.
Run in Blender background. Face -Y, Z up, one connected skin plus shell/gear/staff.
The small modeling and baking helpers are shared; anatomy and actions are new.
"""
import bpy, math, json
from pathlib import Path
from mathutils import Vector, Quaternion, Euler
ROOT=Path(__file__).resolve().parents[1]
for folder in ('exports','textures','previews'): (ROOT/folder).mkdir(exist_ok=True)
# Reuse only primitive mesh helpers and the proven atlas/export conventions.
helper=(ROOT.parents[0]/'krokero/source/build_krokero.py').read_text(encoding='utf-8')
exec(helper[helper.index('def linear'):helper.index('# Skin volumes')])
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
scene.render.engine='CYCLES'; scene.cycles.samples=24
scene.render.resolution_x=1100; scene.render.resolution_y=1100; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.fps=30
scene.view_settings.view_transform='AgX'; scene.world.color=(.16,.18,.15)
skin=material('Sage olive skin','899347',0,.65)
cream=material('Warm cream beak and plastron','e5d7a0',0,.65)
shell_dark=material('Shell dark seams','4f3726',0,.65)
shell_amber=material('Honey amber shell plates','ad7835',0,.58)
shell_olive=material('Olive amber shell plates','8c712e',0,.6)
bronze=material('Worn mentor bronze','b18b4b',.6,.42)
gold=material('Raised sun emblem','dfb764',.55,.4)
leather=material('Brown leather strap','704832',0,.72)
teal=material('Dark teal scarf','285c5d',0,.9)
ochre=material('Ochre belt cloth','bb8b37',0,.9)
wood=material('Warm wooden staff','8e613c',0,.67)
iris=material('Deep brown iris','553623',0,.27)
dark=material('Pupils brows and smile','302e20',0,.4)
white=material('Warm eye white','f5e8c9',0,.4)
for mat,colors,scale in [(skin,('737e3d','969f53'),19),(shell_amber,('93602e','b98540'),14),(shell_olive,('7e692e','9b803b'),14),(wood,('785030','a87849'),9)]:
    nt=mat.node_tree;noise=nt.nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=scale;noise.inputs['Detail'].default_value=2
    ramp=nt.nodes.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].position=.18;ramp.color_ramp.elements[0].color=(*rgb(colors[0]),1);ramp.color_ramp.elements[1].position=.82;ramp.color_ramp.elements[1].color=(*rgb(colors[1]),1)
    nt.links.new(noise.outputs['Fac'],ramp.inputs[0]);nt.links.new(ramp.outputs[0],nt.nodes.get('Principled BSDF').inputs['Base Color'])
gear=[]; body_sources=[]; shell_parts=[]; staff_parts=[]; rigid_bind={}

# A completely new silhouette: compact round torso, broad baby tortoise head, squat limbs.
ellipsoid('Round torso',(0,0,.88),(.35,.25,.43),skin,body_sources)
ellipsoid('Soft hips',(0,.015,.56),(.35,.24,.24),skin,body_sources)
segment('Short retractable neck',(0,-.02,1.08),(0,-.09,1.43),.175,skin,body_sources)
ellipsoid('Oversized friendly head',(0,-.105,1.55),(.435,.34,.355),skin,body_sources,segments=28,rings=18)
ellipsoid('Short turtle beak',(0,-.38,1.46),(.315,.235,.195),skin,body_sources,segments=24)
for sign,side in ((1,'L'),(-1,'R')):
    shoulder=(sign*.32,0,1.04); elbow=(sign*.48,-.035,.82); wrist=(sign*.56,-.11,.65)
    segment('Upper arm '+side,shoulder,elbow,.135,skin,body_sources)
    segment('Soft forearm '+side,elbow,wrist,.125,skin,body_sources)
    ellipsoid('Mitten palm '+side,(sign*.57,-.13,.59),(.15,.12,.14),skin,body_sources)
    for j in range(3): ellipsoid('Rounded finger '+side,(sign*(.49+j*.065),-.22,.58),(.055,.068,.065),skin,body_sources,segments=12,rings=8)
    hip=(sign*.23,.01,.56); knee=(sign*.26,-.02,.36); ankle=(sign*.29,-.015,.16)
    segment('Squat thigh '+side,hip,knee,.16,skin,body_sources)
    segment('Sturdy calf '+side,knee,ankle,.135,skin,body_sources)
    ellipsoid('Broad tortoise foot '+side,(sign*.29,-.10,.12),(.18,.25,.115),skin,body_sources)
    for j in range(3): ellipsoid('Rounded toe '+side,(sign*.29+(j-1)*.095,-.285,.09),(.06,.075,.06),cream,gear,'Foot.'+side,segments=12,rings=8)
body=join(body_sources,'Schili_Body')
remesh=body.modifiers.new('Continuous fused tortoise skin','REMESH'); remesh.mode='VOXEL';remesh.voxel_size=.026;remesh.use_smooth_shade=True
bpy.ops.object.modifier_apply(modifier=remesh.name)
sm=body.modifiers.new('Soft skin surface','SMOOTH');sm.factor=.5;sm.iterations=5;bpy.ops.object.modifier_apply(modifier=sm.name)
body.data.calc_loop_triangles();dec=body.modifiers.new('Skin mobile budget','DECIMATE');dec.ratio=min(1,7200/len(body.data.loop_triangles));bpy.ops.object.modifier_apply(modifier=dec.name)

# Face: round eyes, tiny snub beak, cheek pads, asymmetrical clever smile, no mammal ears.
ellipsoid('Cream smiling muzzle',(0,-.425,1.395),(.31,.212,.123),cream,gear,'Jaw',segments=24)
ellipsoid('Little tortoise beak',(0,-.615,1.48),(.175,.06,.083),cream,gear,'Head')
for sign,side in ((1,'L'),(-1,'R')):
    ellipsoid('Cheek '+side,(sign*.265,-.35,1.42),(.115,.11,.105),cream,gear,'Head')
    ellipsoid('Eye white '+side,(sign*.205,-.374,1.62),(.151,.085,.166),white,gear,'Head',segments=24)
    ellipsoid('Warm brown iris '+side,(sign*.205,-.447,1.625),(.104,.025,.116),iris,gear,'Head')
    ellipsoid('Dark large pupil '+side,(sign*.205,-.468,1.632),(.067,.014,.087),dark,gear,'Head')
    ellipsoid('Eye catchlight '+side,(sign*.205-.029,-.483,1.674),(.025,.009,.027),white,gear,'Head',segments=12,rings=8)
    curve('Clever brow '+side,[(sign*.08,-.405,1.77),(sign*.19,-.414,1.816+(0.025 if side=='R' else 0)),(sign*.33,-.35,1.773)],.026,dark,gear,'Head')
    ellipsoid('Tiny nostril '+side,(sign*.068,-.672,1.508),(.006,.003,.007),dark,gear,'Head',segments=10,rings=6)
curve('Knowing crooked smile',[(-.235,-.49,1.405),(-.11,-.608,1.38),(0,-.638,1.382),(.13,-.594,1.39),(.24,-.479,1.43)],.006,dark,gear,'Jaw')

# Belly is a plastron, not armor. Broad tiles keep it legible on mobile.
ellipsoid('Cream plastron',(0,-.225,.83),(.292,.10,.35),cream,gear,'Spine')
for z,w in ((.65,.20),(.82,.27),(.99,.23)):
    curve('Plastron segment',[(-w,-.285,z),(0,-.332,z-.015),(w,-.285,z)],.006,ochre,gear,'Spine')
curve('Plastron centre',[(0,-.327,.52),(0,-.337,.82),(0,-.30,1.15)],.005,ochre,gear,'Spine')

# Large domed shell, seven broad inset plates, golden rim and original sun/spiral emblem.
vv=[];ff=[];rings=16;sides=40
for inner_side in (False,True):
    for j in range(rings+1):
        phi=.001+(math.pi/2-.001)*j/rings
        for i in range(sides):
            a=i*math.tau/sides
            vv.append((.59*math.sin(phi)*math.cos(a),.16+(.405 if inner_side else .43)*math.cos(phi),.86+.68*math.sin(phi)*math.sin(a)))
for inside in (0,1):
    offset=inside*(rings+1)*sides
    for j in range(rings):
        for i in range(sides):
            face=(offset+j*sides+i,offset+(j+1)*sides+i,offset+(j+1)*sides+(i+1)%sides,offset+j*sides+(i+1)%sides)
            ff.append(tuple(reversed(face)) if inside else face)
mesh('Open domed tortoise shell',vv,ff,shell_dark,shell_parts,'Shell')
def shell_surface(u,v):
    x,z=u*.575,v*.665
    return Vector((x,.16+.43*math.sqrt(max(.01,1-(x/.59)**2-(z/.68)**2))+.006,.86+z))
def plate(name,points,mat):
    centre=sum((Vector(p) for p in points),Vector((0,0)))/len(points)
    points=[centre+(Vector(p)-centre)*.94 for p in points]
    vv=[tuple(shell_surface(*centre)+Vector((0,.012,0)))];ff=[]
    # Concentric polygons follow the actual dome, not a flat shell decal.
    for layer in range(1,6):
        for p in points: vv.append(tuple(shell_surface(*(centre.lerp(p,layer/5)))+Vector((0,.014,0))))
    n=len(points)
    for j in range(n): ff.append((0,1+j,1+(j+1)%n))
    for layer in range(4):
        a=1+layer*n;b=a+n
        for j in range(n): ff.append((a+j,b+j,b+(j+1)%n,a+(j+1)%n))
    mesh(name,vv,[tuple(reversed(f)) for f in ff],mat,shell_parts,'Shell')
    path=[]
    for i,p in enumerate(points):
        q=points[(i+1)%n]
        path.extend(tuple(shell_surface(*p.lerp(q,j/5))+Vector((0,.019,0))) for j in range(5))
    path.append(path[0]);curve(name+' raised border',path,.008,bronze,shell_parts,'Shell')
angles=[math.pi/6+i*math.tau/6 for i in range(6)]
inner=[(.43*math.cos(a),.43*math.sin(a)) for a in angles]
plate('Central hexagonal shell scute',inner,shell_amber)
for i in range(6):
    a,b=angles[i],angles[(i+1)%6]
    if b<a:b+=math.tau
    poly=[inner[i],(.95*math.cos(a),.95*math.sin(a)),(.98*math.cos((a+b)/2),.98*math.sin((a+b)/2)),(.95*math.cos(b),.95*math.sin(b)),inner[(i+1)%6]]
    plate('Outer shell scute %02d'%i,poly,shell_amber if i%2 else shell_olive)
curve('Bronze shell rim',[(.59*math.cos(i*math.tau/64),.16,.86+.68*math.sin(i*math.tau/64)) for i in range(65)],.029,gold,shell_parts,'Shell')
spiral=[]
for i in range(55):
    a=i/54*math.tau*1.5;r=.02+.10*i/54;spiral.append((r*math.cos(a),.618,.86+r*math.sin(a)))
curve('Shell wisdom spiral',spiral,.013,gold,shell_parts,'Shell')
for i in range(6):
    a=i*math.tau/6
    curve('Sun ray',[(.155*math.cos(a),.605,.86+.155*math.sin(a)),(.20*math.cos(a),.600,.86+.20*math.sin(a))],.009,gold,shell_parts,'Shell')

# A narrow forehead band and tiny sun emblem, no franchise mask or Jedi robe.
curve('Bronze forehead band',[(.328*math.cos(a),-.105+.257*math.sin(a),1.795) for a in [math.pi+i*math.pi/32 for i in range(33)]],.022,bronze,gear,'Head')
cylinder('Forehead sun disc',(0,-.38,1.81),.065,.022,bronze,gear,'Head',axis=(0,-1,0))
curve('Forehead spiral',[(.039*i/30*math.cos(i/30*math.tau*1.35),-.398,1.81+.039*i/30*math.sin(i/30*math.tau*1.35)) for i in range(31)],.006,gold,gear,'Head')
curve('Teal scarf neck wrap',[(.19*math.cos(i*math.tau/40),-.03+.175*math.sin(i*math.tau/40),1.22+.015*math.sin(i*math.tau/40)) for i in range(41)],.043,teal,gear,'Neck')
ellipsoid('Scarf knot',(.18,-.14,1.23),(.065,.052,.055),teal,gear,'Neck')
mesh('Short scarf tail',[(.18,-.13,1.23),(.26,-.14,1.21),(.35,-.12,1.02),(.25,-.15,1.06)],[(0,1,2,3)],teal,gear,'Scarf')
curve('Leather shoulder strap',[(-.29,-.16,1.12),(-.16,-.277,1.01),(0,-.342,.88),(.17,-.287,.72),(.28,-.18,.61)],.032,leather,gear,'Spine')
curve('Ochre rope belt',[(.35*math.cos(i*math.tau/40),.01+.26*math.sin(i*math.tau/40),.63) for i in range(41)],.023,ochre,gear,'Pelvis')
mesh('Ochre belt flap',[(.05,-.275,.66),(.16,-.26,.66),(.20,-.29,.40),(.09,-.31,.43)],[(0,1,2,3)],ochre,gear,'Pelvis')
ellipsoid('Small leather pouch',(-.31,-.18,.64),(.092,.07,.12),leather,gear,'Pelvis')
cylinder('Belt medallion',(.04,-.289,.64),.047,.025,bronze,gear,'Pelvis',axis=(0,-1,0))
for sign,side in ((1,'L'),(-1,'R')):
    a=Vector((sign*.48,-.04,.81));b=Vector((sign*.54,-.09,.69))
    cylinder('Small bronze bracer '+side,(a+b)/2,.14,(a-b).length,bronze,gear,'Forearm.'+side,axis=b-a,vertices=20)
    for t in (.03,.97):cylinder('Bracer rim '+side,a.lerp(b,t),.146,.018,gold,gear,'Forearm.'+side,axis=b-a,vertices=20)

# Single staff, independently skinned to the hand. Tall enough to read as a mentor's staff.
staff_a=Vector((-.59,-.19,.06));staff_b=Vector((-.59,-.19,1.98))
segment('Wooden staff shaft',staff_a,staff_b,.031,wood,staff_parts,'Hand.R')
for t in (.02,.98):cylinder('Staff bronze cap',staff_a.lerp(staff_b,t),.048,.10,bronze,staff_parts,'Hand.R',vertices=20)
for t in (.31,.34,.37):cylinder('Staff teal binding',staff_a.lerp(staff_b,t),.037,.035,teal,staff_parts,'Hand.R',vertices=16)

# New tortoise skeleton: no crocodile tail. Shell and scarf have their own bones.
bpy.ops.object.select_all(action='DESELECT');bpy.ops.object.armature_add(enter_editmode=True)
arm=bpy.context.object;arm.name='Schili_Rig';eb=arm.data.edit_bones;eb.remove(eb[0]);spec={}
def bone(name,a,b,parent=None,deform=True):
    bb=eb.new(name);bb.head=a;bb.tail=b;bb.use_deform=deform
    if parent:bb.parent=eb[parent]
    spec[name]=(Vector(a),Vector(b))
bone('Root',(0,0,0),(0,0,.15),deform=False)
bone('Pelvis',(0,0,.56),(0,0,.75),'Root')
bone('Spine',(0,0,.75),(0,0,1.05),'Pelvis')
bone('Chest',(0,0,1.05),(0,-.02,1.20),'Spine')
bone('Neck',(0,-.02,1.20),(0,-.08,1.40),'Chest')
bone('Head',(0,-.08,1.40),(0,-.10,1.78),'Neck')
bone('Jaw',(0,-.24,1.43),(0,-.55,1.39),'Head')
bone('Shell',(0,.20,.82),(0,.27,1.20),'Pelvis')
bone('Scarf',(.18,-.13,1.23),(.30,-.13,1.05),'Neck')
for sign,side in ((1,'L'),(-1,'R')):
    bone('UpperArm.'+side,(sign*.32,0,1.04),(sign*.48,-.035,.82),'Chest')
    bone('Forearm.'+side,(sign*.48,-.035,.82),(sign*.56,-.11,.65),'UpperArm.'+side)
    bone('Hand.'+side,(sign*.56,-.11,.65),(sign*.57,-.15,.54),'Forearm.'+side)
    bone('Thigh.'+side,(sign*.23,.01,.56),(sign*.26,-.02,.36),'Pelvis')
    bone('Shin.'+side,(sign*.26,-.02,.36),(sign*.29,-.015,.16),'Thigh.'+side)
    bone('Foot.'+side,(sign*.29,-.015,.16),(sign*.29,-.20,.10),'Shin.'+side)
bpy.ops.object.mode_set(mode='OBJECT');arm.show_in_front=True
for n in ('Jaw','Shell','Scarf'): arm.data.bones[n].use_deform=False
bpy.ops.object.select_all(action='DESELECT');body.select_set(True);arm.select_set(True);bpy.context.view_layer.objects.active=arm
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
for v in body.data.vertices:
    if v.co.z>1.32 or (v.co.z>1.20 and v.co.y<-.22):
        for g in body.vertex_groups:g.remove([v.index])
        body.vertex_groups['Head'].add([v.index],1,'REPLACE')
for n in ('Jaw','Shell','Scarf'):arm.data.bones[n].use_deform=True
for mod in body.modifiers:
    if mod.type=='ARMATURE':mod.use_deform_preserve_volume=False
def rigid(obj,name):
    obj.vertex_groups.new(name=name).add(list(range(len(obj.data.vertices))),1,'REPLACE')
    obj.parent=arm;mod=obj.modifiers.new('Bone skinning','ARMATURE');mod.object=arm
for obj in gear+shell_parts+staff_parts:
    if obj.name in ('Short scarf tail','Ochre belt flap'):
        bpy.context.view_layer.objects.active=obj
        solid=obj.modifiers.new('Cloth thickness','SOLIDIFY');solid.thickness=.009
        bpy.ops.object.modifier_apply(modifier=solid.name)
    rigid(obj,rigid_bind[obj.name])
details=join(gear,'Schili_Details');shell_obj=join(shell_parts,'Schili_Shell');staff_obj=join(staff_parts,'Schili_Staff')
assets=[body,details,shell_obj,staff_obj]
for obj in assets:
    obj.parent=arm;mods=[m for m in obj.modifiers if m.type=='ARMATURE']
    for mod in mods[1:]:obj.modifiers.remove(mod)
    obj.data.calc_loop_triangles()
    if len(obj.data.loop_triangles)>9000:
        bpy.context.view_layer.objects.active=obj;dec=obj.modifiers.new('Mobile triangle budget','DECIMATE');dec.ratio=8800/len(obj.data.loop_triangles);bpy.ops.object.modifier_apply(modifier=dec.name)
    for v in obj.data.vertices:
        weights=sorted([(g.weight,g.group) for g in v.groups if g.weight>1e-6],reverse=True)[:4]
        assert weights,(obj.name,v.index)
        for g in obj.vertex_groups:g.remove([v.index])
        total=sum(w for w,_ in weights)
        for w,g in weights:obj.vertex_groups[g].add([v.index],w/total,'REPLACE')

# Reuse the material bake, never the earlier character's anatomy or animation.
bake=helper[helper.index('# One packed UV atlas'):helper.index('def clear_pose')]
exec(bake.replace('Krokero','Schili').replace('KROKERO','SCHILI'))
exec(helper[helper.index('def clear_pose'):helper.index('actions={}')] )
actions={}
def action(name,length,sampler):
    clear_pose();arm.animation_data_create();arm.animation_data.action=None
    act=bpy.data.actions.new(name);act.use_fake_user=True;arm.animation_data.action=act
    for f in range(1,length+1,2):clear_pose();sampler((f-1)/(length-1));key(f)
    clear_pose();sampler(1);key(length);actions[name]=(act,length)
def idle(t):
    a=math.sin(t*math.tau);pose('Chest',(a*1.8,0,0));pose('Head',(0,a*2,a*2))
    pose('Forearm.R',(-10,0,-5));pose('Forearm.L',(-16,0,0));pose('Scarf',(a*6,0,0))
def walk(t):
    a=math.sin(t*math.tau);pose('Pelvis',(0,0,a*4),(0,0,abs(a)*.023))
    for s,side in ((1,'L'),(-1,'R')):
        pose('Thigh.'+side,(s*a*27,0,0));pose('Shin.'+side,(max(0,-s*a)*34,0,0));pose('Foot.'+side,(-max(0,-s*a)*16,0,0))
        pose('UpperArm.'+side,(-s*a*9,0,0));pose('Forearm.'+side,(-14,0,0))
    pose('Head',(0,0,-a*3));pose('Shell',(0,0,-a*2));pose('Scarf',(a*12,0,a*5))
def smoothkeys(t,keys):
    for a,b in zip(keys,keys[1:]):
        if a[0]<=t<=b[0]:
            u=(t-a[0])/(b[0]-a[0]);u=u*u*(3-2*u)
            return [v*(1-u)+w*u for v,w in zip(a[1:],b[1:])]
    return list(keys[-1][1:])
def strike(t):
    # Patience, compact draw-back, quick diagonal staff counter, visible return.
    shoulder,elbow,twist,lean=smoothkeys(t,[(0,-12,-10,0,0),(.50,30,-72,-24,-8),(.67,-68,-8,28,8),(.80,-58,-5,22,5),(1,-12,-10,0,0)])
    pose('UpperArm.R',(shoulder,0,-12));pose('Forearm.R',(elbow,0,0));pose('Chest',(lean,0,twist))
    pose('UpperArm.L',(-30,0,22));pose('Forearm.L',(-70,0,0));pose('Head',(-lean*.4,0,-twist*.5));pose('Scarf',(twist*.6,0,0))
def feint(t):
    a=math.sin(t*math.pi);pose('Head',(0,-12*a,-9*a));pose('UpperArm.R',(22*a,0,-10*a));pose('Forearm.R',(-50*a,0,0));pose('Chest',(-5*a,0,-12*a));pose('UpperArm.L',(-20*a,0,18*a))
def sweep(t):
    twist,shoulder,elbow=smoothkeys(t,[(0,0,-10,-10),(.50,-52,-25,-65),(.72,58,-55,-8),(1,0,-10,-10)])
    pose('Chest',(0,0,twist));pose('UpperArm.R',(shoulder,0,-40));pose('Forearm.R',(elbow,0,0));pose('Head',(0,0,-twist*.5));pose('Pelvis',(0,0,twist*.16))
def guard(t):
    a=min(1,t/.35);a=a*a*(3-2*a)
    pose('Pelvis',(-8*a,0,0),(0,0,-.16*a));pose('Chest',(25*a,0,0));pose('Neck',(-16*a,0,0),(0,.15*a,-.18*a))
    pose('Head',(-8*a,0,0),(0,.06*a,-.07*a));pose('Shell',(30*a,0,0),(0,-.12*a,.18*a))
    for side in ('L','R'):pose('UpperArm.'+side,(-55*a,0,(-1 if side=='L' else 1)*20*a));pose('Forearm.'+side,(-75*a,0,0));pose('Thigh.'+side,(-42*a,0,0));pose('Shin.'+side,(65*a,0,0));pose('Foot.'+side,(-23*a,0,0))
def rush(t):
    a=math.sin(t*math.tau);pose('Pelvis',(-12,0,a*3),(0,0,abs(a)*.03));pose('Chest',(8,0,0));pose('Head',(-8,0,0));pose('Scarf',(22,0,a*8))
    for sign,side in ((1,'L'),(-1,'R')):pose('Thigh.'+side,(sign*a*38,0,0));pose('Shin.'+side,(max(0,-sign*a)*44,0,0));pose('UpperArm.'+side,(-28,0,0));pose('Forearm.'+side,(-65,0,0))
def stagger(t):
    a=math.sin(t*math.pi)*max(.0,1-t*.7);pose('Chest',(-18*a,0,8*a));pose('Head',(-12*a,0,-12*a));pose('UpperArm.L',(-30*a,0,18*a));pose('Jaw',(7*a,0,0))
def bow(t):
    a=math.sin(t*math.pi);pose('Chest',(18*a,0,0));pose('Head',(12*a,0,-8*a));pose('UpperArm.L',(-28*a,0,22*a));pose('Forearm.L',(-65*a,0,0))
for name,length,fn in [('Idle',91,idle),('Walk',37,walk),('StaffStrike',49,strike),('Feint',31,feint),('StaffSweep',55,sweep),('ShellGuard',31,guard),('Rush',25,rush),('Stagger',37,stagger),('Bow',61,bow)]:action('Schili_'+name,length,fn)
arm.animation_data.action=None;clear_pose();bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
for obj in assets+[arm]:obj.select_set(True)
bpy.context.view_layer.objects.active=arm
kwargs=dict(use_selection=True,object_types={'ARMATURE','MESH'},add_leaf_bones=False,use_armature_deform_only=False,apply_scale_options='FBX_SCALE_UNITS',axis_forward='-Z',axis_up='Y',path_mode='COPY',embed_textures=True,use_mesh_modifiers=True)
bpy.ops.export_scene.fbx(filepath=str(ROOT/'exports/Schili_Bind.fbx'),bake_anim=False,**kwargs)
report={'character':'Schilibitzli / Schili','bones':list(spec),'meshes':{},'animations':{}}
for obj in assets:
    obj.data.calc_loop_triangles();report['meshes'][obj.name]={'triangles':len(obj.data.loop_triangles),'vertices':len(obj.data.vertices),'max_influences':max(len(v.groups) for v in obj.data.vertices)}
for name,(act,length) in actions.items():
    arm.animation_data.action=act;scene.frame_start=1;scene.frame_end=length
    bpy.ops.export_scene.fbx(filepath=str(ROOT/'exports'/f'{name}.fbx'),bake_anim=True,bake_anim_use_all_actions=False,bake_anim_use_nla_strips=False,bake_anim_simplify_factor=0,**kwargs)
    report['animations'][name]={'frames':length,'fps':30}
arm.animation_data.action=actions['Schili_Idle'][0];scene.frame_start=1;scene.frame_end=91;scene.frame_set(1)
floor_mat=material('Warm studio floor','e1cda4',0,.8)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.015));floor=bpy.context.object;floor.name='PREVIEW_ONLY_floor';floor.data.materials.append(floor_mat)
for name,pos,energy,size,color in [('key',(-3,-4,5),420,4,(1,.86,.68)),('fill',(3,-1,3),240,3,(.78,.9,1)),('rim',(0,3,4),450,3,(1,.87,.65))]:
    data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.shape='DISK';data.size=size;data.color=color
    ob=bpy.data.objects.new('PREVIEW_ONLY_'+name,data);scene.collection.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector((0,0,1))-ob.location).to_track_quat('-Z','Y').to_euler()
data=bpy.data.cameras.new('Review Camera');camera=bpy.data.objects.new('Review Camera',data);scene.collection.objects.link(camera);scene.camera=camera;data.type='ORTHO';data.ortho_scale=2.75
def camera_at(pos,target=(0,0,1)):
    camera.location=pos;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
camera_at((-3,-6,2.8));scene.cycles.samples=24
scene.render.filepath=str(ROOT/'previews/Schili_hero.png')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Schili.blend'))
(ROOT/'validation.json').write_text(json.dumps(report,indent=2))
for name,pos,clip,frame in [('hero',(-3,-6,2.8),'Idle',1),('front',(0,-6,2.2),'Idle',1),('back',(3,5,2.8),'Idle',1),('guard',(-3,-6,2.5),'ShellGuard',31),('strike',(-3,-6,2.5),'StaffStrike',33)]:
    camera_at(pos);arm.animation_data.action=actions['Schili_'+clip][0];scene.frame_set(frame)
    scene.render.filepath=str(ROOT/'previews'/f'Schili_{name}.png');bpy.ops.render.render(write_still=True)
arm.animation_data.action=actions['Schili_Idle'][0];scene.frame_set(1);camera_at((-3,-6,2.8))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Schili.blend'))
print('SCHILI_COMPLETE',json.dumps(report),flush=True)
