"""Krokero: continuous remeshed skin, weighted bone rig, editable gear and real actions.
Run with Blender --background --factory-startup --python this_file.
Coordinates: Z up, face -Y, metres. This is a custom NPC, not a Marketplace avatar.
"""
import bpy, math, json, sys, argparse
from pathlib import Path
from mathutils import Vector, Quaternion, Euler
from mathutils.kdtree import KDTree

ROOT = Path(__file__).resolve().parents[1]
for folder in ('exports', 'textures', 'previews'):
    (ROOT / folder).mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 24
scene.render.resolution_x = 1200
scene.render.resolution_y = 1200
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.fps = 30
scene.view_settings.view_transform = 'AgX'
scene.world.color = (0.15, 0.15, 0.15)

def linear(c):
    return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4

def rgb(hex):
    return tuple(linear(int(hex[i:i+2], 16) / 255) for i in (0, 2, 4))

def material(name, color, metallic=0, roughness=.5):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb(color), 1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = m.diffuse_color
    bs.inputs['Metallic'].default_value = metallic
    bs.inputs['Roughness'].default_value = roughness
    return m

skin = material('Jungle green', '408c49')
cream = material('Warm yellow green jaw', 'd3d68c')
ridge = material('Rounded forest ridges', '275838')
bronze = material('Worn bronze', 'b78645', .65, .38)
gold = material('Raised bronze edges', 'd4a45b', .65, .36)
patina = material('Subtle green patina', '5b9a83', .35, .65)
leather = material('Handmade leather', '69442d', 0, .7)
edge = material('Leather edging', 'b68552', 0, .7)
wood = material('Training wood', '986039', 0, .7)
wood_light = material('Wood end grain', 'c18b52', 0, .6)
red = material('Worn oxblood cloth', '9c3d32', 0, .85)
dark = material('Warm dark eyes and smile', '242a24', 0, .35)
white = material('Ivory catchlights and rounded teeth', 'fff0ce', 0, .35)
iris = material('Amber gold irises', 'e5a32b', .05, .25)
sclera = material('Soft warm sclera', 'f5dfaa', 0, .35)

body_sources, gear, shield_parts, club_parts = [], [], [], []
rigid_bind = {}

def finish(obj, name, mat, collection=None, bone=None):
    obj.name = name
    if mat: obj.data.materials.append(mat)
    for p in obj.data.polygons: p.use_smooth = True
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if collection is not None: collection.append(obj)
    if bone: rigid_bind[obj.name] = bone
    return obj

def ellipsoid(name, center, scale, mat, collection=None, bone=None, segments=20, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=center)
    obj = bpy.context.object
    obj.scale = scale
    return finish(obj, name, mat, collection, bone)

def segment(name, a, b, radius, mat, collection=None, bone=None, flatten=1):
    a, b = Vector(a), Vector(b)
    obj = ellipsoid(name, (a+b)/2, (radius, radius * flatten, (b-a).length/2 + radius*.35), mat, collection, bone)
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = Vector((0,0,1)).rotation_difference((b-a).normalized())
    return obj

def mesh(name, vertices, faces, mat, collection=None, bone=None):
    data = bpy.data.meshes.new(name)
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    return finish(obj, name, mat, collection, bone)

def curve(name, points, radius, mat, collection=gear, bone='Head'):
    c = bpy.data.curves.new(name, 'CURVE')
    c.dimensions, c.resolution_u = '3D', 8
    c.bevel_depth, c.bevel_resolution = radius, 2
    spl = c.splines.new('BEZIER')
    spl.bezier_points.add(len(points)-1)
    for bp, pt in zip(spl.bezier_points, points):
        bp.co = pt
        bp.handle_left_type = bp.handle_right_type = 'AUTO'
    obj = bpy.data.objects.new(name, c)
    scene.collection.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target='MESH')
    return finish(bpy.context.object, name, mat, collection, bone)

def cylinder(name, center, radius, depth, mat, collection, bone, axis=(0,0,1), vertices=32):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=center)
    obj = bpy.context.object
    obj.rotation_mode = 'QUATERNION'
    obj.rotation_quaternion = Vector((0,0,1)).rotation_difference(Vector(axis).normalized())
    bevel = obj.modifiers.new('Soft handmade edge', 'BEVEL')
    bevel.width, bevel.segments = .012, 2
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return finish(obj, name, mat, collection, bone)

def join(objects, name):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects: obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return obj

# Skin volumes overlap and are fused below, including hands, toes and the tail base.
ellipsoid('Pelvic volume', (0,.04,1.12), (.40,.31,.34), skin, body_sources)
ellipsoid('Athletic torso', (0,0,1.53), (.49,.34,.51), skin, body_sources)
ellipsoid('Upper chest', (0,.015,1.78), (.55,.32,.26), skin, body_sources)
ellipsoid('Neck', (0,-.015,2.00), (.27,.26,.30), skin, body_sources)
ellipsoid('Broad young crocodile head', (0,-.015,2.38), (.51,.37,.37), skin, body_sources)
ellipsoid('Broad rounded snout', (0,-.46,2.32), (.46,.57,.22), skin, body_sources, segments=28)
ellipsoid('Snout bridge', (0,-.2,2.46), (.43,.36,.23), skin, body_sources)

for sign, side in ((1,'L'),(-1,'R')):
    shoulder=(sign*.49,0,1.79)
    elbow=(sign*.77,-.005,1.43)
    wrist=(sign*.92,-.10,1.10)
    segment('Upper arm '+side, shoulder, elbow, .205, skin, body_sources)
    ellipsoid('Elbow '+side, elbow, (.185,.18,.18), skin, body_sources)
    segment('Forearm '+side, elbow, wrist, .165, skin, body_sources)
    ellipsoid('Palm '+side, (sign*.96,-.10,1.01), (.18,.135,.18), skin, body_sources)
    for j in range(3):
        ellipsoid('Rounded finger '+side, (sign*(.86+j*.08),-.19,.99), (.062,.105,.105), skin, body_sources, segments=12, rings=8)
    hip=(sign*.245,.055,1.03)
    knee=(sign*.30,-.005,.63)
    ankle=(sign*.32,.035,.25)
    segment('Thigh '+side, hip, knee, .22, skin, body_sources)
    segment('Calf '+side, knee, ankle, .17, skin, body_sources)
    ellipsoid('Powerful foot '+side,(sign*.32,-.12,.18),(.21,.31,.15),skin,body_sources)
    for j in range(3):
        ellipsoid('Rounded toe '+side,(sign*.32+(j-1)*.12,-.34,.15),(.075,.12,.08),skin,body_sources,segments=12,rings=8)

tail_points=[Vector(p) for p in [(0,.23,1.09),(0,.58,.90),(0,.99,.61),(0,1.43,.39),(0,1.88,.27),(0,2.27,.25),(0,2.60,.29)]]
tail_widths=[.29,.285,.245,.19,.13,.075,.018]
v, f=[],[]
for i,(p,w) in enumerate(zip(tail_points,tail_widths)):
    tangent=(tail_points[min(i+1,6)]-tail_points[max(i-1,0)]).normalized()
    up=Vector((1,0,0)).cross(tangent).normalized()
    for j in range(16):
        a=j*math.tau/16
        v.append(tuple(p+Vector((1,0,0))*math.cos(a)*w+up*math.sin(a)*w*.75))
for i in range(6):
    for j in range(16): f.append((i*16+j,i*16+(j+1)%16,(i+1)*16+(j+1)%16,(i+1)*16+j))
f += [tuple(reversed(range(16))),tuple(6*16+j for j in range(16))]
mesh('Continuous tapered tail',v,f,skin,body_sources)
body=join(body_sources,'Krokero_Body')
remesh=body.modifiers.new('Fused continuous skin', 'REMESH')
remesh.mode='VOXEL'; remesh.voxel_size=.038; remesh.use_smooth_shade=True
bpy.ops.object.modifier_apply(modifier=remesh.name)
smooth=body.modifiers.new('Sculpt surface relaxation','SMOOTH')
smooth.factor=.55; smooth.iterations=5
bpy.ops.object.modifier_apply(modifier=smooth.name)
body.data.calc_loop_triangles()
dec=body.modifiers.new('Mobile mesh budget','DECIMATE')
dec.ratio=min(1,8800/max(1,len(body.data.loop_triangles)))
bpy.ops.object.modifier_apply(modifier=dec.name)
for p in body.data.polygons: p.use_smooth=True

# Hand-painted spatial colour, baked to a normal PNG atlas later.
col=body.data.color_attributes.new(name='SkinPaint',type='FLOAT_COLOR',domain='CORNER')
green,light,back=rgb('408c49'),rgb('c4cf7b'),rgb('326e40')
for loop in body.data.loops:
    p=body.data.vertices[loop.vertex_index].co
    belly=max(0,1-abs(p.x)/.36)*max(0,min(1,(-p.y-.11)/.13))
    belly*=max(0,min(1,(p.z-1.03)/.16))*max(0,min(1,(2.13-p.z)/.17))
    band=.94+.06*math.cos(p.z*44)
    shade=.96+.04*math.sin(p.z*3.2)
    base=tuple(green[k]*shade*(1-belly)+light[k]*band*belly for k in range(3))
    if p.y>.32 and p.z>1.0: base=tuple(base[k]*.8+back[k]*.2 for k in range(3))
    col.data[loop.index].color=(*base,1)
skin.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.55
vc=skin.node_tree.nodes.new('ShaderNodeVertexColor'); vc.layer_name='SkinPaint'
skin.node_tree.links.new(vc.outputs['Color'],skin.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])

# Separate lower jaw is skinned to a genuine jaw bone; eyes and eyebrows ride on Head.
ellipsoid('Cream lower jaw',(0,-.45,2.135),(.435,.535,.135),cream,gear,'Jaw',segments=28)
for sign,side in ((1,'L'),(-1,'R')):
    ellipsoid('Eye socket '+side,(sign*.345,-.19,2.59),(.215,.205,.215),skin,gear,'Head')
    ellipsoid('Warm sclera '+side,(sign*.345,-.323,2.61),(.161,.102,.174),sclera,gear,'Head')
    ellipsoid('Amber iris '+side,(sign*.345,-.407,2.61),(.113,.036,.124),iris,gear,'Head')
    ellipsoid('Round pupil '+side,(sign*.345,-.437,2.612),(.057,.018,.081),dark,gear,'Head')
    ellipsoid('Bright catchlight '+side,(sign*.345-.035,-.454,2.654),(.024,.012,.028),white,gear,'Head',segments=12,rings=8)
    curve('Expressive eyebrow '+side,[(sign*.18,-.335,2.77),(sign*.33,-.355,2.805),(sign*.50,-.29,2.77+(0.035 if side=='R' else -.015))],.040,ridge)
    ellipsoid('Nostril rim '+side,(sign*.25,-.883,2.445),(.091,.095,.046),ridge,gear,'Head')
    ellipsoid('Nostril '+side,(sign*.25,-.932,2.46),(.044,.037,.02),dark,gear,'Head',segments=12,rings=8)
    curve('Crooked grin '+side,[(sign*.045,-.989,2.205),(sign*.26,-.946,2.21),(sign*.405,-.79,2.245),(sign*.44,-.56,2.27+(0.025 if side=='R' else 0))],.009,dark)
    for xx,yy in ((.30,-.89),(.40,-.70)):
        ellipsoid('Small rounded tooth '+side,(sign*xx,yy,2.205),(.032,.035,.058),white,gear,'Head',segments=12,rings=8)

for i in range(5):
    ellipsoid('Rounded back scute', (0,.305,1.91-i*.16),(.072,.08,.11),ridge,gear,'Chest' if i<3 else 'Spine',segments=12,rings=8)
for i in range(6):
    a,b=tail_points[i:i+2]
    p=a.lerp(b,.50); p.z+=tail_widths[i]*.68
    ellipsoid('Tail scute %02d'%i,p,(.07*(1-i*.1),.12*(1-i*.09),.09*(1-i*.09)),ridge,gear,'Tail%02d'%(i+1),segments=12,rings=8)

# Harness ribbon follows the chest instead of a floating diagonal cuboid.
pts=[(-.43,-.205,1.93),(-.28,-.285,1.79),(-.08,-.335,1.60),(.13,-.34,1.38),(.29,-.265,1.19)]
pts=[tuple(Vector(pts[i]).lerp(Vector(pts[i+1]),j/4)) for i in range(len(pts)-1) for j in range(4)]+[pts[-1]]
vv=[]
for p in pts:
    for d in (-1,1): vv.append((p[0]+d*.047,p[1]-.03,p[2]-d*.044))
strap=mesh('Shoulder harness',vv,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(len(pts)-1)],leather,gear)
solid=strap.modifiers.new('Leather thickness','SOLIDIFY'); solid.thickness=.018
bpy.context.view_layer.objects.active=strap; bpy.ops.object.modifier_apply(modifier=solid.name)
for side in (-1,1):
    curve('Hand stitched harness',[(p[0]+side*.033,p[1]-.032,p[2]-side*.031) for p in pts],.005,edge,gear,None)

def band(name, center, rx, ry, width, mat, bone):
    vv,ff=[],[]
    for z in (-width/2,width/2):
        for i in range(40):
            a=i*math.tau/40
            vv.append((center[0]+rx*math.cos(a),center[1]+ry*math.sin(a),center[2]+z))
    for i in range(40): ff.append((i,(i+1)%40,(i+1)%40+40,i+40))
    return mesh(name,vv,ff,mat,gear,bone)

band('Broad leather belt',(0,.035,1.16),.445,.35,.12,leather,None)
for z in (1.11,1.21):
    curve('Belt stitched edge',[(.45*math.cos(a*math.tau/40),.035+.355*math.sin(a*math.tau/40),z) for a in range(41)],.005,edge,gear,None)
cylinder('Circular bronze emblem',(0,-.345,1.16),.10,.045,bronze,gear,'Pelvis',axis=(0,-1,0))
curve('Courage emblem', [(-.05,-.378,1.15),(0,-.38,1.205),(.05,-.378,1.15)],.011,gold,gear,'Pelvis')
for i in range(3):
    x=(i-1)*.105
    mesh('Red cloth panel',[(x-.065,-.299,1.10),(x+.065,-.299,1.10),(x+.07,-.34,.86+(i%2)*.025),(x-.055,-.34,.82)],[(0,1,2,3)],red,gear,'Pelvis')

# Curved single pauldron, with rolled rim, restrained patina and bronze rivets.
vv,ff=[],[]
center=Vector((-.53,.015,1.79))
for j in range(8):
    phi=.04+j*1.57/7
    for i in range(24):
        a=i*math.tau/24
        vv.append(tuple(center+Vector((.33*math.sin(phi)*math.cos(a),.32*math.sin(phi)*math.sin(a),.31*math.cos(phi)))))
for j in range(7):
    for i in range(24): ff.append((j*24+i,j*24+(i+1)%24,(j+1)*24+(i+1)%24,(j+1)*24+i))
mesh('Curved bronze shoulder guard',vv,ff,bronze,gear,'UpperArm.R')
curve('Pauldron rolled rim', [tuple(center+Vector((.33*math.cos(a*math.tau/32),.32*math.sin(a*math.tau/32),-.012))) for a in range(33)],.016,gold,gear,'UpperArm.R')
for i in range(7):
    a=i*math.tau/7
    ellipsoid('Pauldron rivet',center+Vector((.326*math.cos(a),.316*math.sin(a),.045)),(.023,.023,.024),gold,gear,'UpperArm.R',segments=10,rings=6)
for i in range(5):
    a=2.8+i*.27; phi=.65+i*.12
    p=center+Vector((.334*math.sin(phi)*math.cos(a),.324*math.sin(phi)*math.sin(a),.314*math.cos(phi)))
    patch=ellipsoid('Small patina patch',p,(.035,.025,.004),patina,gear,'UpperArm.R',segments=12,rings=8)
    patch.rotation_mode='QUATERNION'
    patch.rotation_quaternion=Vector((0,0,1)).rotation_difference((p-center).normalized())

for sign,side in ((1,'L'),(-1,'R')):
    a=Vector((sign*.81,-.04,1.34)); b=Vector((sign*.88,-.075,1.17))
    cylinder('Leather wrist guard '+side,(a+b)/2,.18,(a-b).length,leather,gear,'Forearm.'+side,axis=b-a,vertices=20)
    for t in (.05,.95):
        cylinder('Wrist binding '+side,a.lerp(b,t),.183,.022,edge,gear,'Forearm.'+side,axis=b-a,vertices=20)

# Shield and club stay individually selectable and can be equipped/hidden separately.
shield_center=Vector((1.00,-.38,1.12))
cylinder('Wooden shield',shield_center,.345,.075,wood,shield_parts,'Hand.L',axis=(0,-1,0),vertices=40)
cylinder('Bronze shield rim',shield_center+Vector((0,-.014,0)),.355,.026,bronze,shield_parts,'Hand.L',axis=(0,-1,0),vertices=40)
cylinder('Inset wood face',shield_center+Vector((0,-.033,0)),.321,.039,wood_light,shield_parts,'Hand.L',axis=(0,-1,0),vertices=40)
for x in (-.19,-.065,.065,.19):
    half=math.sqrt(.307**2-x*x)
    curve('Shield plank seam',[(1+x,-.438,1.12-half),(1+x,-.438,1.12+half)],.006,wood,shield_parts,'Hand.L')
cylinder('Shield bronze boss',shield_center+Vector((0,-.065,0)),.085,.055,bronze,shield_parts,'Hand.L',axis=(0,-1,0))
for i in range(10):
    a=i*math.tau/10
    ellipsoid('Shield rivet',shield_center+Vector((math.cos(a)*.337,-.034,math.sin(a)*.337)),(.014,.012,.014),gold,shield_parts,'Hand.L',segments=10,rings=6)
club_a=Vector((-.97,-.13,1.03)); club_b=Vector((-1.03,-.24,.24))
segment('Wooden training handle',club_a,club_b,.053,wood,club_parts,'Hand.R')
segment('Chunky carved training head',club_a.lerp(club_b,.55),club_b,.125,wood_light,club_parts,'Hand.R',flatten=.9)
for t in (.05,.14,.23):
    p=club_a.lerp(club_b,t)
    cylinder('Club leather grip',p,.061,.033,leather,club_parts,'Hand.R',axis=club_b-club_a,vertices=16)
cylinder('Club bronze binding',club_a.lerp(club_b,.59),.11,.045,bronze,club_parts,'Hand.R',axis=club_b-club_a,vertices=20)

# Bone structure. Root is at the origin and intentionally has no vertex influences.
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.object.armature_add(enter_editmode=True, location=(0,0,0))
arm=bpy.context.object; arm.name='Krokero_Rig'
eb=arm.data.edit_bones
eb.remove(eb[0])
spec={}
def bone(name,a,b,parent=None,deform=True):
    bb=eb.new(name); bb.head=a; bb.tail=b; bb.use_deform=deform
    if parent: bb.parent=eb[parent]
    spec[name]=(Vector(a),Vector(b))
bone('Root',(0,0,0),(0,0,.2),deform=False)
bone('Pelvis',(0,.04,1.02),(0,.02,1.30),'Root')
bone('Spine',(0,.02,1.30),(0,0,1.57),'Pelvis')
bone('Chest',(0,0,1.57),(0,0,1.89),'Spine')
bone('Neck',(0,0,1.89),(0,-.02,2.15),'Chest')
bone('Head',(0,-.02,2.15),(0,-.04,2.64),'Neck')
bone('Jaw',(0,-.08,2.18),(0,-.78,2.12),'Head')
for sign,side in ((1,'L'),(-1,'R')):
    bone('UpperArm.'+side,(sign*.49,0,1.79),(sign*.77,-.005,1.43),'Chest')
    bone('Forearm.'+side,(sign*.77,-.005,1.43),(sign*.92,-.10,1.10),'UpperArm.'+side)
    bone('Hand.'+side,(sign*.92,-.10,1.10),(sign*.96,-.13,.94),'Forearm.'+side)
    bone('Thigh.'+side,(sign*.245,.055,1.03),(sign*.30,-.005,.63),'Pelvis')
    bone('Shin.'+side,(sign*.30,-.005,.63),(sign*.32,.035,.25),'Thigh.'+side)
    bone('Foot.'+side,(sign*.32,.035,.25),(sign*.32,-.32,.15),'Shin.'+side)
for i in range(6): bone('Tail%02d'%(i+1),tail_points[i],tail_points[i+1],'Pelvis' if i==0 else 'Tail%02d'%i)
bpy.ops.object.mode_set(mode='OBJECT')
arm.show_in_front=True
arm.data.display_type='OCTAHEDRAL'

def dist_segment(p,a,b):
    t=max(0,min(1,(p-a).dot(b-a)/(b-a).length_squared))
    return (p-a.lerp(b,t)).length

def skin_object(obj, fixed=None):
    groups={name:obj.vertex_groups.new(name=name) for name in spec if name!='Root'}
    for vert in obj.data.vertices:
        p=obj.matrix_world@vert.co
        if fixed:
            groups[fixed].add([vert.index],1,'REPLACE'); continue
        # Soft leather inherits the actual body's heat weights, not proximity to an unrelated arm.
        if 'body_tree' in globals():
            neighbors=body_tree.find_n(p,3)
            weights={}
            for _,index,distance in neighbors:
                factor=1/(distance+.015)**2
                for group in body.data.vertices[index].groups:
                    name=body.vertex_groups[group.group].name
                    if name in groups: weights[name]=weights.get(name,0)+group.weight*factor
            chosen=sorted(weights.items(),key=lambda item:item[1],reverse=True)[:4]
            total=sum(weight for _,weight in chosen)
            for name,weight in chosen: groups[name].add([vert.index],weight/total,'REPLACE')
            continue
        # Continuous distance fields avoid arbitrary spatial seams at wrists, hips and tail base.
        candidates=[n for n in spec if n not in ('Root','Jaw')]
        values={n:1/(.055+dist_segment(p,*spec[n]))**6 for n in candidates}
        if p.z>2.0:
            blend=max(0,min(1,(p.z-2.0)/.2)); blend=blend*blend*(3-2*blend)
            total_value=sum(values.values())
            values={n:v/total_value*(1-blend) for n,v in values.items()}
            values['Head']+=blend
        scored=sorted(((w,n) for n,w in values.items()),reverse=True)[:4]
        total=sum(w for w,n in scored)
        for w,n in scored:
            if w/total>.0001: groups[n].add([vert.index],w/total,'REPLACE')
    # Normalize after discarding very small weights.
    bpy.context.view_layer.objects.active=obj
    obj.parent=arm
    mod=obj.modifiers.new('Real bone skinning','ARMATURE'); mod.object=arm; mod.use_deform_preserve_volume=False

# Blender's bone-heat solver respects connected surface topology, especially where a resting
# wrist is close to the hip. Linear skinning matches the deformation exported in the FBX.
bpy.ops.object.select_all(action='DESELECT')
body.select_set(True); arm.select_set(True); bpy.context.view_layer.objects.active=arm
arm.data.bones['Jaw'].use_deform=False
bpy.ops.object.parent_set(type='ARMATURE_AUTO')
arm.data.bones['Jaw'].use_deform=True
for modifier in body.modifiers:
    if modifier.type=='ARMATURE': modifier.use_deform_preserve_volume=False
body_tree=KDTree(len(body.data.vertices))
for vertex in body.data.vertices: body_tree.insert(body.matrix_world@vertex.co,vertex.index)
body_tree.balance()
for obj in gear+shield_parts+club_parts:
    if skin in obj.data.materials[:] and not obj.data.color_attributes.get('SkinPaint'):
        paint=obj.data.color_attributes.new(name='SkinPaint',type='FLOAT_COLOR',domain='CORNER')
        for value in paint.data: value.color=(*green,1)
    skin_object(obj,rigid_bind.get(obj.name))

# Join rigid details AFTER weighting; vertex groups and the armature modifier are retained.
details=join(gear,'Krokero_Details')
shield_obj=join(shield_parts,'Krokero_Shield')
club_obj=join(club_parts,'Krokero_TrainingClub')
assets=[body,details,shield_obj,club_obj]
for obj in assets:
    obj.parent=arm
    # Joining objects can preserve multiple identical armature modifiers: keep one.
    mods=[m for m in obj.modifiers if m.type=='ARMATURE']
    for m in mods[1:]: obj.modifiers.remove(m)
    obj.data.calc_loop_triangles()
    if len(obj.data.loop_triangles)>9500:
        bpy.context.view_layer.objects.active=obj
        budget=obj.modifiers.new('Equipment mobile budget','DECIMATE')
        budget.ratio=9000/len(obj.data.loop_triangles)
        bpy.ops.object.modifier_apply(modifier=budget.name)
    # A decimated vertex can inherit both endpoints' influences. Prune and normalize explicitly.
    for vert in obj.data.vertices:
        weights=sorted([(g.weight,g.group) for g in vert.groups if g.weight>1e-6],reverse=True)[:4]
        for group in obj.vertex_groups: group.remove([vert.index])
        total=sum(w for w,_ in weights)
        for weight,index in weights: obj.vertex_groups[index].add([vert.index],weight/total,'REPLACE')
    obj['asset_role']='skin' if obj==body else 'equipment_or_face'
    obj['forward_axis']='-Y'

# One packed UV atlas shared by the four skinned meshes.
bpy.ops.object.select_all(action='DESELECT')
for obj in assets: obj.select_set(True)
bpy.context.view_layer.objects.active=body
bpy.ops.object.mode_set(mode='EDIT')
bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.015)
bpy.ops.uv.pack_islands(margin=.012,rotate=True)
bpy.ops.object.mode_set(mode='OBJECT')
atlas=bpy.data.images.new('Krokero_BaseColor',width=2048,height=2048,alpha=False)
atlas.generated_color=(.15,.25,.13,1)
all_mats=set(m for obj in assets for m in obj.data.materials)
saved=[]
for m in all_mats:
    nt=m.node_tree; out=next(n for n in nt.nodes if n.type=='OUTPUT_MATERIAL')
    original=out.inputs['Surface'].links[0].from_socket
    bs=nt.nodes.get('Principled BSDF')
    emission=nt.nodes.new('ShaderNodeEmission')
    base=bs.inputs['Base Color']
    if base.is_linked: nt.links.new(base.links[0].from_socket,emission.inputs['Color'])
    else: emission.inputs['Color'].default_value=base.default_value
    nt.links.new(emission.outputs[0],out.inputs['Surface'])
    tex=nt.nodes.new('ShaderNodeTexImage'); tex.image=atlas
    nt.nodes.active=tex
    saved.append((nt,out,original,emission,tex))
scene.render.bake.use_clear=False
scene.render.bake.margin=8
scene.cycles.samples=1
print('KROKERO: baking UV base colour atlas',flush=True)
bpy.ops.object.bake(type='EMIT')
atlas.filepath_raw=str(ROOT/'textures/Krokero_BaseColor.png'); atlas.file_format='PNG'; atlas.save()
maps={}
for property_name,file_name in (('Metallic','Krokero_Metalness'),('Roughness','Krokero_Roughness')):
    image=bpy.data.images.new(file_name,width=2048,height=2048,alpha=False)
    image.colorspace_settings.name='Non-Color'
    image.generated_color=(0,0,0,1)
    for nt,out,original,emission,target in saved:
        for link in list(emission.inputs['Color'].links): nt.links.remove(link)
        value=nt.nodes.get('Principled BSDF').inputs[property_name].default_value
        emission.inputs['Color'].default_value=(value,value,value,1)
        target.image=image
    bpy.ops.object.bake(type='EMIT')
    image.filepath_raw=str(ROOT/'textures'/f'{file_name}.png'); image.file_format='PNG'; image.save(); image.pack()
    maps[property_name]=image
for nt,out,original,emission,tex in saved:
    nt.links.new(original,out.inputs['Surface']); nt.nodes.remove(emission); nt.nodes.remove(tex)
atlas_mat=material('Krokero UV atlas','ffffff',0,.53)
tex=atlas_mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=atlas
atlas_mat.node_tree.links.new(tex.outputs['Color'],atlas_mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
for property_name,image in maps.items():
    node=atlas_mat.node_tree.nodes.new('ShaderNodeTexImage'); node.image=image
    atlas_mat.node_tree.links.new(node.outputs['Color'],atlas_mat.node_tree.nodes.get('Principled BSDF').inputs[property_name])
for obj in assets:
    obj.data.materials.clear(); obj.data.materials.append(atlas_mat)
    for polygon in obj.data.polygons: polygon.material_index=0
atlas.pack()

def clear_pose():
    for pb in arm.pose.bones:
        pb.rotation_mode='QUATERNION'; pb.rotation_quaternion=Quaternion(); pb.location=(0,0,0); pb.scale=(1,1,1)

def pose(name, angles=(0,0,0), loc=None):
    pb=arm.pose.bones[name]
    rest=arm.data.bones[name].matrix_local.to_quaternion()
    world=Euler(tuple(math.radians(a) for a in angles),'XYZ').to_quaternion()
    pb.rotation_quaternion=rest.inverted()@world@rest
    if loc is not None: pb.location=rest.inverted()@Vector(loc)

def key(frame):
    for pb in arm.pose.bones:
        pb.keyframe_insert(data_path='rotation_quaternion',frame=frame,group=pb.name)
        pb.keyframe_insert(data_path='location',frame=frame,group=pb.name)

actions={}
def action(name,length,sampler):
    clear_pose(); arm.animation_data_create(); arm.animation_data.action=None
    act=bpy.data.actions.new(name); act.use_fake_user=True
    arm.animation_data.action=act
    for f in range(1,length+1,3):
        clear_pose(); sampler((f-1)/(length-1)); key(f)
    clear_pose(); sampler(1); key(length)
    actions[name]=(act,length)

def idle(t):
    a=math.sin(t*math.tau)
    pose('Chest',(a*1.6,0,0)); pose('Head',(0,0,a*1.2))
    pose('Forearm.R',(-8,0,0)); pose('Forearm.L',(-15,0,0))
    for i in range(6): pose('Tail%02d'%(i+1),(0,0,math.sin(t*math.tau-i*.4)*3))

def walk(t):
    a=math.sin(t*math.tau)
    pose('Pelvis',(0,0,a*3), (0,0,abs(a)*.025))
    for sign,side in ((1,'L'),(-1,'R')):
        pose('Thigh.'+side,(sign*a*22,0,0))
        pose('Shin.'+side,(max(0,-sign*a)*33,0,0))
        pose('Foot.'+side,(-max(0,-sign*a)*12,0,0))
        pose('UpperArm.'+side,(-sign*a*12,0,0))
        pose('Forearm.'+side,(-12,0,0))
    for i in range(6): pose('Tail%02d'%(i+1),(0,0,math.sin(t*math.tau-i*.5)*5))

def strike(t):
    # Three readable beats: wind-up, decisive strike, vulnerable recovery.
    keys=[(0,0,0,0),(.40,82,-14,12),(.57,-70,24,-18),(.78,-40,12,-10),(1,0,0,0)]
    for i in range(len(keys)-1):
        a,b=keys[i:i+2]
        if a[0]<=t<=b[0]:
            u=(t-a[0])/(b[0]-a[0]); u=u*u*(3-2*u)
            arm_angle=a[1]*(1-u)+b[1]*u; twist=a[2]*(1-u)+b[2]*u; lean=a[3]*(1-u)+b[3]*u
            pose('UpperArm.R',(arm_angle,0,0)); pose('Forearm.R',(-20,0,0))
            pose('Chest',(lean*.4,0,twist)); pose('Pelvis',(lean*.25,0,0))
            pose('UpperArm.L',(-18,0,-10)); pose('Forearm.L',(-25,0,0))
            pose('Head',(-lean*.35,0,-twist*.4))
            for j in range(6): pose('Tail%02d'%(j+1),(0,0,-twist*.13))
            break

def stagger(t):
    a=math.sin(min(1,t/.4)*math.pi/2)*max(0,1-(max(0,t-.4)/.6))
    pose('Chest',(-a*18,0,a*8)); pose('Head',(-a*12,0,-a*6))
    pose('UpperArm.R',(-a*20,0,a*10)); pose('Jaw',(a*4,0,0))

action('Kroko_Idle',61,idle)
action('Kroko_Walk',31,walk)
action('Kroko_ClubStrike',46,strike)
action('Kroko_Stagger',31,stagger)

# Validate the skin contract and independently export one animation track per FBX.
arm.animation_data.action=None; clear_pose(); bpy.context.view_layer.update()
report={'character':'Krokero / Kroko','format':'custom skinned NPC','blender':bpy.app.version_string,'bones':list(spec),'meshes':{},'animations':{}}
for obj in assets:
    obj.data.calc_loop_triangles()
    max_weights=max((len([g for g in v.groups if g.weight>1e-5]) for v in obj.data.vertices),default=0)
    unweighted=sum(not any(g.weight>1e-5 for g in v.groups) for v in obj.data.vertices)
    assert max_weights<=4 and unweighted==0,(obj.name,max_weights,unweighted)
    assert all(abs(s-1)<1e-6 for s in obj.scale)
    report['meshes'][obj.name]={'vertices':len(obj.data.vertices),'triangles':len(obj.data.loop_triangles),'max_bone_influences':max_weights,'unweighted_vertices':unweighted}
bpy.ops.object.select_all(action='DESELECT')
for obj in assets+[arm]: obj.select_set(True)
bpy.context.view_layer.objects.active=arm
export_kwargs=dict(use_selection=True,object_types={'ARMATURE','MESH'},add_leaf_bones=False,use_armature_deform_only=False,apply_scale_options='FBX_SCALE_UNITS',axis_forward='-Z',axis_up='Y',path_mode='COPY',embed_textures=True,use_mesh_modifiers=True)
print('KROKERO: export bind mesh',flush=True)
bpy.ops.export_scene.fbx(filepath=str(ROOT/'exports/Krokero_Bind.fbx'),bake_anim=False,**export_kwargs)
for name,(act,length) in actions.items():
    arm.animation_data.action=act; scene.frame_start=1; scene.frame_end=length
    bpy.ops.export_scene.fbx(filepath=str(ROOT/'exports'/f'{name}.fbx'),bake_anim=True,bake_anim_use_all_actions=False,bake_anim_use_nla_strips=False,bake_anim_simplify_factor=0,**export_kwargs)
    report['animations'][name]={'frames':length,'fps':30,'file':name+'.fbx'}
arm.animation_data.action=actions['Kroko_Idle'][0]
scene.frame_start=1; scene.frame_end=61; scene.frame_set(1)

# Presentation only: neutral backdrop, three soft lights and orthographic review cameras.
stage_mat=material('Studio backdrop','263c37',0,.8)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,.015))
floor=bpy.context.object; floor.name='PREVIEW_ONLY_floor'; floor.data.materials.append(stage_mat)
def light(name,position,energy,size,color):
    data=bpy.data.lights.new(name,'AREA'); data.energy=energy; data.shape='DISK'; data.size=size; data.color=color
    obj=bpy.data.objects.new(name,data); scene.collection.objects.link(obj); obj.location=position
    obj.rotation_euler=(Vector((0,0,1.3))-obj.location).to_track_quat('-Z','Y').to_euler()
light('PREVIEW_ONLY_key',(-3.5,-4.5,6),650,4,(1,.86,.68))
light('PREVIEW_ONLY_fill',(4,-1,4),450,4,(.72,.88,1))
light('PREVIEW_ONLY_rim',(0,4,5),800,3,(.8,1,.88))
camera_data=bpy.data.cameras.new('Review Camera')
camera=bpy.data.objects.new('Review Camera',camera_data); scene.collection.objects.link(camera); scene.camera=camera
camera_data.type='ORTHO'; camera_data.ortho_scale=4.35
def camera_at(position,target=(0,.35,1.35)):
    camera.location=position; camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler()
camera_at((-4.5,-7,3.5))
scene.cycles.samples=32
scene.render.filepath=str(ROOT/'previews/Krokero_hero.png')
for area in bpy.context.screen.areas if bpy.context.screen else []:
    if area.type=='VIEW_3D':
        area.spaces.active.region_3d.view_perspective='CAMERA'
        area.spaces.active.shading.type='MATERIAL'
arm.show_in_front=False
bpy.ops.object.select_all(action='DESELECT'); body.select_set(True); bpy.context.view_layer.objects.active=body
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Krokero.blend'))
(ROOT/'validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('KROKERO: rendering hero',flush=True)
bpy.ops.render.render(write_still=True)
camera_at((0,-7,2.7),(0,0,1.38)); camera_data.ortho_scale=3.5
scene.render.filepath=str(ROOT/'previews/Krokero_front.png'); bpy.ops.render.render(write_still=True)
camera_at((5,5,3.5),(0,.6,1.2)); camera_data.ortho_scale=4.5
scene.render.filepath=str(ROOT/'previews/Krokero_back.png'); bpy.ops.render.render(write_still=True)
camera_at((-4.5,-7,3.5)); camera_data.ortho_scale=4.35
arm.animation_data.action=actions['Kroko_ClubStrike'][0]; scene.frame_set(19)
scene.render.filepath=str(ROOT/'previews/Krokero_strike.png'); bpy.ops.render.render(write_still=True)
arm.animation_data.action=actions['Kroko_Idle'][0]; scene.frame_set(1)
camera_at((-4.5,-7,3.5)); scene.render.filepath=str(ROOT/'previews/Krokero_hero.png')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Krokero.blend'))
print('KROKERO_COMPLETE',json.dumps(report),flush=True)
