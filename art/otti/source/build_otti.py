"""Otti: a genuinely skinned, flexible otter gladiator. Z up, facing -Y.
Run in Blender background. Modeling helpers are shared, anatomy and motion are new.
"""
import bpy,math,json,sys
from pathlib import Path
from mathutils import Vector,Quaternion,Euler
from mathutils.kdtree import KDTree
ROOT=Path(__file__).resolve().parents[1]
for folder in ('exports','textures','previews'): (ROOT/folder).mkdir(exist_ok=True)
helper=(ROOT.parent/'krokero/source/build_krokero.py').read_text(encoding='utf-8')
exec(helper[helper.index('def linear'):helper.index('# Skin volumes')])
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene;scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
scene.render.engine='CYCLES';scene.cycles.samples=20;scene.render.fps=60
scene.render.resolution_x=1100;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.view_settings.view_transform='AgX';scene.world.color=(.15,.17,.16)
skin=material('Chocolate otter fur','70452f',0,.65)
cream=material('Cream otter muzzle','ead8b0',0,.65)
dark=material('Dark nose and brows','30231f',0,.42)
inner=material('Velvet inner ears','4d3027',0,.7)
iris=material('Warm dark brown eyes','352117',0,.25)
white=material('Warm eye catchlights','fff2d8',0,.3)
bronze=material('Worn gladiator bronze','ad8048',.65,.42)
gold=material('Otti golden chains','d9ae59',.7,.36)
patina=material('Quiet bronze patina','648475',.35,.65)
leather=material('Worn leather','69432f',0,.75)
cloth=material('Otti oxblood cloth','943c36',0,.9)
wood=material('Warm wooden gladius','986a43',0,.65)
wood_light=material('Wooden blade bevel','c09262',0,.65)
cord_dark=material('Braided dark necklace','3c3028',0,.7)
body_sources=[];gear=[];shield_parts=[];sword_parts=[];sheathed_parts=[];rigid_bind={}

# Long-waisted mustelid silhouette: compact legs, broad webbed paws, rounded short muzzle.
ellipsoid('Otter hips',(0,.03,.92),(.32,.27,.30),skin,body_sources)
ellipsoid('Supple lower torso',(0,.025,1.20),(.305,.26,.40),skin,body_sources)
ellipsoid('Narrow flexible ribcage',(0,.0,1.52),(.36,.27,.35),skin,body_sources)
ellipsoid('Soft shoulders',(0,0,1.67),(.43,.245,.21),skin,body_sources)
segment('Otter neck',(0,0,1.72),(0,-.03,2.05),.20,skin,body_sources)
ellipsoid('Rounded otter head',(0,-.04,2.18),(.385,.305,.335),skin,body_sources,segments=28,rings=18)
ellipsoid('Broad short otter muzzle',(0,-.27,2.09),(.29,.21,.17),skin,body_sources,segments=24)
for sign,side in ((1,'L'),(-1,'R')):
    a=(sign*.39,0,1.66);b=(sign*.60,-.005,1.35);c=(sign*.73,-.10,1.06)
    segment('Upper forelimb '+side,a,b,.143,skin,body_sources)
    segment('Supple forearm '+side,b,c,.125,skin,body_sources)
    ellipsoid('Webbed forepaw '+side,(sign*.75,-.15,.99),(.16,.125,.15),skin,body_sources)
    for i in range(4):ellipsoid('Forepaw digit '+side,(sign*(.65+i*.063),-.23,.96),(.047,.07,.075),skin,body_sources,segments=12,rings=8)
    hip=(sign*.22,.03,.88);knee=(sign*.25,-.005,.55);ankle=(sign*.27,.02,.23)
    segment('Otter thigh '+side,hip,knee,.175,skin,body_sources)
    segment('Otter shin '+side,knee,ankle,.13,skin,body_sources)
    ellipsoid('Long webbed hind paw '+side,(sign*.27,-.10,.14),(.18,.28,.12),skin,body_sources)
    for j in range(4):ellipsoid('Hindpaw digit '+side,(sign*.27+(j-1.5)*.078,-.31,.105),(.052,.09,.06),skin,body_sources,segments=12,rings=8)

tail_points=[Vector(p) for p in [(0,.22,.96),(0,.55,.76),(0,.92,.52),(0,1.32,.32),(0,1.72,.21),(0,2.08,.19),(0,2.40,.22)]]
widths=[.255,.245,.215,.165,.115,.07,.015];vv=[];ff=[]
for i,(p,w) in enumerate(zip(tail_points,widths)):
    tangent=(tail_points[min(i+1,6)]-tail_points[max(i-1,0)]).normalized();up=Vector((1,0,0)).cross(tangent).normalized()
    for j in range(18):
        a=j*math.tau/18;vv.append(tuple(p+Vector((1,0,0))*math.cos(a)*w+up*math.sin(a)*w*.64))
for i in range(6):
    for j in range(18):ff.append((i*18+j,i*18+(j+1)%18,(i+1)*18+(j+1)%18,(i+1)*18+j))
ff.extend([tuple(reversed(range(18))),tuple(6*18+j for j in range(18))])
mesh('Strong flattened tapering otter tail',vv,ff,skin,body_sources)
body=join(body_sources,'Otti_Body')
remesh=body.modifiers.new('One continuous otter skin','REMESH');remesh.mode='VOXEL';remesh.voxel_size=.030;remesh.use_smooth_shade=True;bpy.ops.object.modifier_apply(modifier=remesh.name)
sm=body.modifiers.new('Soft sculpt surface','SMOOTH');sm.factor=.5;sm.iterations=5;bpy.ops.object.modifier_apply(modifier=sm.name)
body.data.calc_loop_triangles();dec=body.modifiers.new('Mobile skin budget','DECIMATE');dec.ratio=min(1,9000/len(body.data.loop_triangles));bpy.ops.object.modifier_apply(modifier=dec.name)
paint=body.data.color_attributes.new(name='SkinPaint',type='FLOAT_COLOR',domain='CORNER')
for loop in body.data.loops:
    p=body.data.vertices[loop.vertex_index].co
    front=max(0,min(1,(-p.y-.10)/.13));width=max(0,min(1,(.25-abs(p.x))/.09))
    vertical=max(0,min(1,(p.z-.78)/.16))*max(0,min(1,(2.0-p.z)/.10));blend=front*width*vertical
    brown=rgb('70452f');light=rgb('dfc79a');shade=.96+.04*math.sin(p.z*29+p.x*8)
    paint.data[loop.index].color=(*(brown[k]*shade*(1-blend)+light[k]*blend for k in range(3)),1)
vc=skin.node_tree.nodes.new('ShaderNodeVertexColor');vc.layer_name='SkinPaint';skin.node_tree.links.new(vc.outputs[0],skin.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])

# Otter identity: little round ears, full cream whisker pads, broad dark nose, expressive eyes.
ellipsoid('Cream lower muzzle',(0,-.29,1.995),(.25,.18,.095),cream,gear,'Jaw',segments=24)
for sign,side in ((1,'L'),(-1,'R')):
    ellipsoid('Rounded ear '+side,(sign*.32,.005,2.405),(.112,.073,.125),skin,gear,'Head')
    ellipsoid('Velvet ear inset '+side,(sign*.32,-.055,2.405),(.067,.023,.078),inner,gear,'Head')
    ellipsoid('Full otter whisker pad '+side,(sign*.12,-.365,2.075),(.16,.13,.105),cream,gear,'Head',segments=24)
    ellipsoid('Gentle eye rim '+side,(sign*.185,-.277,2.25),(.115,.065,.135),inner,gear,'Head')
    ellipsoid('Expressive dark eye '+side,(sign*.185,-.327,2.258),(.089,.038,.108),iris,gear,'Head',segments=24)
    ellipsoid('Eye catchlight '+side,(sign*.185-.025,-.362,2.30),(.023,.012,.026),white,gear,'Head',segments=12,rings=8)
    curve('Soft brow '+side,[(sign*.09,-.29,2.38),(sign*.19,-.30,2.405+(0.018 if side=='R' else 0)),(sign*.28,-.24,2.375)],.023,dark,gear,'Head')
    for i in range(3):
        curve('Otter whisker '+side,[(sign*.15,-.475,2.07-i*.015),(sign*.31,-.47,2.08+(i-1)*.04),(sign*(.48-i*.02),-.40,2.08+(i-1)*.065)],.0055,white,gear,'Head')
    curve('Playful otter smile '+side,[(0,-.457,2.01),(sign*.12,-.462,2.005),(sign*.21,-.397,2.025)],.006,dark,gear,'Jaw')
ellipsoid('Broad rounded dark otter nose',(0,-.468,2.15),(.143,.077,.088),dark,gear,'Head',segments=24)

# Light Roman equipment allows visible waist and shoulder movement.
curve('Narrow leather harness',[(-.32,-.16,1.72),(-.18,-.253,1.58),(0,-.284,1.38),(.23,-.20,1.12)],.033,leather,gear,None)
for strand in range(2):
    points=[]
    for i in range(57):
        a=i*math.tau/56;r=.215+(.009 if strand else -.009)*math.sin(a*14)
        points.append((r*math.cos(a),-.01+r*math.sin(a),1.88+.012*math.cos(a*14+strand*math.pi)))
    curve('Braided Otti neck cord',points,.012,cream if strand else cord_dark,gear,'Neck')
for row in range(2):
    for i in range(19):
        u=i/18;x=(u-.5)*.53;z=1.79-row*.10-.17*math.sin(u*math.pi)
        y=-.235-.05*math.sin(u*math.pi)
        path=[(x+.018*math.cos(a*math.tau/12),y+(.007 if i%2 else .0)*math.cos(a*math.tau/12),z+.025*math.sin(a*math.tau/12)) for a in range(13)]
        curve('Golden chain link',path,.0065,gold,gear,None)
cylinder('Otti medallion',(0,-.30,1.48),.068,.025,gold,gear,'Spine',axis=(0,-1,0),vertices=24)
vv=[];ff=[];centre=Vector((-.40,0,1.65))
for j in range(7):
    phi=.03+j*math.pi/2/6
    for i in range(20):
        a=i*math.tau/20;vv.append(tuple(centre+Vector((.25*math.sin(phi)*math.cos(a),.235*math.sin(phi)*math.sin(a),.215*math.cos(phi)))))
for j in range(6):
    for i in range(20):ff.append((j*20+i,j*20+(i+1)%20,(j+1)*20+(i+1)%20,(j+1)*20+i))
mesh('Single bronze shoulder guard',vv,ff,bronze,gear,'UpperArm.R')
curve('Pauldron golden rim',[tuple(centre+Vector((.25*math.cos(i*math.tau/32),.235*math.sin(i*math.tau/32),0))) for i in range(33)],.014,gold,gear,'UpperArm.R')
for sign,side in ((1,'L'),(-1,'R')):
    a=Vector((sign*.63,-.02,1.29));b=Vector((sign*.69,-.07,1.15))
    cylinder('Bronze bracer '+side,(a+b)/2,.14,(a-b).length,bronze,gear,'Forearm.'+side,axis=b-a,vertices=20)
    for t in (.05,.95):cylinder('Bracer leather edge '+side,a.lerp(b,t),.145,.018,leather,gear,'Forearm.'+side,axis=b-a,vertices=20)
    ellipsoid('Small shin plate '+side,(sign*.265,-.10,.39),(.105,.04,.16),bronze,gear,'Shin.'+side)
curve('Leather waist belt',[(.335*math.cos(i*math.tau/48),.03+.275*math.sin(i*math.tau/48),.97) for i in range(49)],.026,leather,gear,'Pelvis')
for i in range(5):
    a=math.pi+(i+.5)*math.pi/5;x=.31*math.cos(a);y=.03+.26*math.sin(a)
    ob=mesh('Short oxblood skirt tab',[(x-.045,y,.97),(x+.045,y,.97),(x+.052,y-.025,.77),(x-.042,y-.025,.75)],[(0,1,2,3)],cloth,gear,'Pelvis')
    bpy.context.view_layer.objects.active=ob;solid=ob.modifiers.new('Cloth thickness','SOLIDIFY');solid.thickness=.01;bpy.ops.object.modifier_apply(modifier=solid.name)

# Wooden practice gladius and a light red-paneled wooden shield.
hand=Vector((-.75,-.15,1.04))
cylinder('Wooden sword grip',hand+Vector((0,0,.015)),.043,.24,leather,sword_parts,'Hand.R',vertices=16)
ellipsoid('Bronze practice guard',hand+Vector((0,0,-.095)),(.16,.055,.035),bronze,sword_parts,'Hand.R')
vv=[(-.75+x,-.15+y,z) for y in (-.028,.028) for x,z in [(-.10,.94),(.10,.94),(.083,.30),(0,.19),(-.083,.30)]]
mesh('Chunky wooden gladius blade',vv,[(0,4,3,2,1),(5,6,7,8,9)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)],wood,sword_parts,'Hand.R')
curve('Raised wood blade ridge',[(-.75,-.181,.9),(-.75,-.181,.3)],.012,wood_light,sword_parts,'Hand.R')
sc=Vector((.77,-.30,1.11))
cylinder('Round wooden shield',sc,.315,.065,wood,shield_parts,'Hand.L',axis=(0,-1,0),vertices=40)
cylinder('Bronze shield rim',sc+Vector((0,-.02,0)),.324,.025,bronze,shield_parts,'Hand.L',axis=(0,-1,0),vertices=40)
cylinder('Dark red shield panels',sc+Vector((0,-.037,0)),.29,.031,cloth,shield_parts,'Hand.L',axis=(0,-1,0),vertices=40)
for x in (-.16,-.05,.06,.17):
    half=math.sqrt(.28**2-x*x);curve('Shield wood seam',[(sc.x+x,-.358,sc.z-half),(sc.x+x,-.358,sc.z+half)],.006,wood_light,shield_parts,'Hand.L')
cylinder('Golden shield boss',sc+Vector((0,-.065,0)),.075,.055,gold,shield_parts,'Hand.L',axis=(0,-1,0))
segment('Leather scabbard',(.33,.02,1.02),(.38,.04,.47),.065,leather,sheathed_parts,'Pelvis',flatten=.6)
cylinder('Sheathed sword hilt',(.33,.02,1.10),.04,.17,leather,sheathed_parts,'Pelvis',vertices=16)
ellipsoid('Sheathed bronze guard',(.33,.02,1.025),(.13,.045,.026),bronze,sheathed_parts,'Pelvis')

# Flexible otter rig: four body joints, neck/head/jaw, full limbs, six tail joints.
bpy.ops.object.select_all(action='DESELECT');bpy.ops.object.armature_add(enter_editmode=True)
arm=bpy.context.object;arm.name='Otti_Rig';eb=arm.data.edit_bones;eb.remove(eb[0]);spec={}
def bone(name,a,b,parent=None,deform=True):
    bb=eb.new(name);bb.head=a;bb.tail=b;bb.use_deform=deform
    if parent:bb.parent=eb[parent]
    spec[name]=(Vector(a),Vector(b))
bone('Root',(0,0,0),(0,0,.15),deform=False)
bone('Pelvis',(0,.03,.90),(0,.02,1.12),'Root')
bone('Lumbar',(0,.02,1.12),(0,0,1.34),'Pelvis')
bone('Spine',(0,0,1.34),(0,0,1.56),'Lumbar')
bone('Chest',(0,0,1.56),(0,0,1.78),'Spine')
bone('Neck',(0,0,1.78),(0,-.025,2.01),'Chest')
bone('Head',(0,-.025,2.01),(0,-.04,2.37),'Neck')
bone('Jaw',(0,-.20,2.025),(0,-.40,2.0),'Head')
for sign,side in ((1,'L'),(-1,'R')):
    bone('UpperArm.'+side,(sign*.39,0,1.66),(sign*.60,-.005,1.35),'Chest')
    bone('Forearm.'+side,(sign*.60,-.005,1.35),(sign*.73,-.10,1.06),'UpperArm.'+side)
    bone('Hand.'+side,(sign*.73,-.10,1.06),(sign*.75,-.17,.94),'Forearm.'+side)
    bone('Thigh.'+side,(sign*.22,.03,.88),(sign*.25,-.005,.55),'Pelvis')
    bone('Shin.'+side,(sign*.25,-.005,.55),(sign*.27,.02,.23),'Thigh.'+side)
    bone('Foot.'+side,(sign*.27,.02,.23),(sign*.27,-.26,.12),'Shin.'+side)
for i in range(6):bone('Tail%02d'%(i+1),tail_points[i],tail_points[i+1],'Pelvis' if i==0 else 'Tail%02d'%i)
bpy.ops.object.mode_set(mode='OBJECT');arm.show_in_front=True
arm.data.bones['Jaw'].use_deform=False
bpy.ops.object.select_all(action='DESELECT');body.select_set(True);arm.select_set(True);bpy.context.view_layer.objects.active=arm;bpy.ops.object.parent_set(type='ARMATURE_AUTO')
arm.data.bones['Jaw'].use_deform=True
for v in body.data.vertices:
    if v.co.z>2.02 or (v.co.z>1.94 and v.co.y<-.22):
        for g in body.vertex_groups:g.remove([v.index])
        body.vertex_groups['Head'].add([v.index],1,'REPLACE')
for mod in body.modifiers:
    if mod.type=='ARMATURE':mod.use_deform_preserve_volume=False
body_tree=KDTree(len(body.data.vertices))
for v in body.data.vertices:body_tree.insert(v.co,v.index)
body_tree.balance()
# Reuse only the skin-weight helper, with this otter's own skeleton and connected skin.
exec(helper[helper.index('def dist_segment'):helper.index('# Blender\'s bone-heat')])
for obj in gear+shield_parts+sword_parts+sheathed_parts:
    if skin in obj.data.materials[:]:
        color=obj.data.color_attributes.new(name='SkinPaint',type='FLOAT_COLOR',domain='CORNER')
        for value in color.data:value.color=(*rgb('70452f'),1)
    skin_object(obj,rigid_bind.get(obj.name))
details=join(gear,'Otti_Details');shield_obj=join(shield_parts,'Otti_Shield');sword_obj=join(sword_parts,'Otti_Sword');sheathed_obj=join(sheathed_parts,'Otti_Sheathed')
assets=[body,details,shield_obj,sword_obj,sheathed_obj]
for obj in assets:
    obj.parent=arm;mods=[m for m in obj.modifiers if m.type=='ARMATURE']
    for mod in mods[1:]:obj.modifiers.remove(mod)
    obj.data.calc_loop_triangles()
    if len(obj.data.loop_triangles)>9500:
        bpy.context.view_layer.objects.active=obj;dec=obj.modifiers.new('Details triangle budget','DECIMATE');dec.ratio=9000/len(obj.data.loop_triangles);bpy.ops.object.modifier_apply(modifier=dec.name)
    for v in obj.data.vertices:
        weights=sorted([(g.weight,g.group) for g in v.groups if g.weight>1e-6],reverse=True)[:4]
        assert weights,(obj.name,v.index)
        for g in obj.vertex_groups:g.remove([v.index])
        total=sum(w for w,_ in weights)
        for w,g in weights:obj.vertex_groups[g].add([v.index],w/total,'REPLACE')
exec(helper[helper.index('# One packed UV atlas'):helper.index('def clear_pose')].replace('Krokero','Otti').replace('KROKERO','OTTI'))
sys.path.insert(0,str(ROOT/'source'))
from otti_actions import build_actions
actions=build_actions(arm,scene)
arm.animation_data.action=None
for pb in arm.pose.bones:pb.matrix_basis.identity()
bpy.context.view_layer.update();bpy.ops.object.select_all(action='DESELECT')
for obj in assets+[arm]:obj.select_set(True)
bpy.context.view_layer.objects.active=arm
kwargs=dict(use_selection=True,object_types={'ARMATURE','MESH'},add_leaf_bones=False,use_armature_deform_only=False,apply_scale_options='FBX_SCALE_UNITS',axis_forward='-Z',axis_up='Y',path_mode='COPY',embed_textures=True,use_mesh_modifiers=True)
bpy.ops.export_scene.fbx(filepath=str(ROOT/'exports/Otti_Bind.fbx'),bake_anim=False,**kwargs)
scene.frame_start=1;scene.frame_end=121
bpy.ops.export_scene.fbx(filepath=str(ROOT/'exports/Otti_Animations.fbx'),bake_anim=True,bake_anim_use_all_actions=True,bake_anim_use_nla_strips=False,bake_anim_simplify_factor=0,**kwargs)
report={'character':'Otti / otter gladiator','fps':60,'bones':list(spec),'meshes':{},'animations':{name:{'frames':length,'fps':60} for name,(act,length) in actions.items()}}
for obj in assets:
    obj.data.calc_loop_triangles();report['meshes'][obj.name]={'triangles':len(obj.data.loop_triangles),'vertices':len(obj.data.vertices),'max_influences':max(len(v.groups) for v in obj.data.vertices)}
arm.animation_data.action=actions['Otti_BipedIdle'][0];scene.frame_set(1)
floor_mat=material('Warm neutral backdrop','b8a78b',0,.8)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.01));floor=bpy.context.object;floor.name='PREVIEW_ONLY_floor';floor.data.materials.append(floor_mat)
for name,pos,power,size,color in [('key',(-4,-5,6),650,4,(1,.86,.69)),('fill',(4,-1,4),400,4,(.76,.89,1)),('rim',(0,4,5),700,3,(1,.89,.69))]:
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    ob=bpy.data.objects.new('PREVIEW_ONLY_'+name,data);scene.collection.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector((0,.3,1.2))-ob.location).to_track_quat('-Z','Y').to_euler()
data=bpy.data.cameras.new('Review Camera');camera=bpy.data.objects.new('Review Camera',data);scene.collection.objects.link(camera);scene.camera=camera;data.type='ORTHO';data.ortho_scale=3.8
def camera_at(pos,target=(0,.35,1.15)):
    camera.location=pos;camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
camera_at((-4,-6,3));scene.render.filepath=str(ROOT/'previews/Otti_hero.png')
(ROOT/'validation.json').write_text(json.dumps(report,indent=2));bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Otti.blend'))
for name,pos,clip,frame in [('hero',(-4,-6,3),'BipedIdle',1),('back',(4,6,3),'BipedIdle',1),('quad',(-4,-6,3),'QuadIdle',1),('bound',(-4,-6,3),'QuadRun',10),('slash',(-4,-6,3),'Slash',26),('guard',(-4,-6,3),'Guard',31)]:
    camera_at(pos);arm.animation_data.action=actions['Otti_'+clip][0];scene.frame_set(frame)
    sword_obj.hide_render=sheathed_obj.hide_render=False
    if clip.startswith('Quad'):sword_obj.hide_render=True
    else:sheathed_obj.hide_render=True
    scene.render.filepath=str(ROOT/'previews'/f'Otti_{name}.png');bpy.ops.render.render(write_still=True)
sword_obj.hide_render=False;sheathed_obj.hide_render=True
arm.animation_data.action=actions['Otti_BipedIdle'][0];scene.frame_set(1);camera_at((-4,-6,3));bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Otti.blend'))
print('OTTI_COMPLETE',json.dumps(report),flush=True)
