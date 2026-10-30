"""Independent .blend geometry/skin check plus an actual FBX re-import check."""
import bpy, json, math
from pathlib import Path
root=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(root/'Krokero.blend'))
rig=bpy.data.objects['Krokero_Rig']
body=bpy.data.objects['Krokero_Body']
results={'checks':[],'pose_bounds':{}}
def check(ok,name):
    results['checks'].append({'name':name,'passed':bool(ok)})
    assert ok,name
    print('PASS',name,flush=True)

check(len(rig.data.bones)==25,'25 real bones including root, jaw and six tail bones')
check(not rig.data.bones['Root'].use_deform,'root has no deformation influences')
adj=[[] for _ in body.data.vertices]
for e in body.data.edges:
    a,b=e.vertices; adj[a].append(b); adj[b].append(a)
visited=set(); components=0
for i in range(len(adj)):
    if i in visited: continue
    components+=1; stack=[i]; visited.add(i)
    while stack:
        for j in adj[stack.pop()]:
            if j not in visited: visited.add(j); stack.append(j)
check(components==1,'body is one connected surface, not intersecting primitive objects')
for obj in [o for o in bpy.data.objects if o.type=='MESH' and o.parent==rig]:
    obj.data.calc_loop_triangles()
    check(len(obj.data.loop_triangles)<=10000,obj.name+' stays under 10000 triangles')
    check(len(obj.data.uv_layers)>0,obj.name+' has UV coordinates')
    check(any(m.type=='ARMATURE' and m.object==rig for m in obj.modifiers),obj.name+' has a real armature modifier')
    check(all(1<=sum(g.weight>1e-5 for g in v.groups)<=4 for v in obj.data.vertices),obj.name+' has one to four skin influences on every vertex')
    check(all(abs(sum(g.weight for g in v.groups)-1)<1e-4 for v in obj.data.vertices),obj.name+' weights are normalized')

deps=bpy.context.evaluated_depsgraph_get()
for name in ('Kroko_Idle','Kroko_Walk','Kroko_ClubStrike','Kroko_Stagger'):
    rig.animation_data.action=bpy.data.actions[name]
    worst=0; minz=math.inf; maxz=-math.inf; stretched_length=0
    for frame in range(1,int(rig.animation_data.action.frame_range[1])+1,3):
        bpy.context.scene.frame_set(frame)
        evaluated=body.evaluated_get(deps)
        data=evaluated.to_mesh()
        for e in body.data.edges:
            a,b=e.vertices
            old=(body.data.vertices[a].co-body.data.vertices[b].co).length
            new=(data.vertices[a].co-data.vertices[b].co).length
            if old>.01: worst=max(worst,new/old)
            if old>.01 and new/old>5: stretched_length=max(stretched_length,new)
        minz=min(minz,min(v.co.z for v in data.vertices))
        maxz=max(maxz,max(v.co.z for v in data.vertices))
        evaluated.to_mesh_clear()
    results['pose_bounds'][name]={'worst_edge_stretch':worst,'min_z':minz,'max_z':maxz,'longest_edge_with_ratio_over_5':stretched_length}
    print('POSE_BOUNDS',name,results['pose_bounds'][name],flush=True)
    check(worst<5,name+' has no extreme stretched skin triangles')

# Import exported bind and attack into a clean Blender scene: validates actual deliverables.
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(root/'exports/Krokero_Bind.fbx'))
imported=[o for o in bpy.context.scene.objects if o.type=='ARMATURE']
check(len(imported)==1,'FBX bind re-import contains exactly one skeleton')
check(len(imported[0].data.bones)>=25,'FBX preserves bone hierarchy')
meshes=[o for o in bpy.context.scene.objects if o.type=='MESH']
check(len(meshes)==4,'FBX preserves four skinned mesh objects')
check(all(any(m.type=='ARMATURE' for m in o.modifiers) for o in meshes),'FBX preserves skinning on all meshes')
check(any(i.has_data and i.size[0]==2048 for i in bpy.data.images),'FBX embedded atlas texture is readable')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(root/'exports/Kroko_ClubStrike.fbx'))
check(len(bpy.data.actions)>=1,'attack FBX contains animation data')
rig=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
check(rig.animation_data is not None and rig.animation_data.action is not None,'attack FBX binds its animation to the imported rig')
results['status']='passed'
(root/'verification.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
print('KROKERO_VALIDATED',len(results['checks']),flush=True)
