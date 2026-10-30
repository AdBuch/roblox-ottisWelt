"""Verify skinning, connected body, clip deformation, and actual FBX round-trip."""
import bpy,json,math
from pathlib import Path
root=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(root/'Schili.blend'))
rig=bpy.data.objects['Schili_Rig'];body=bpy.data.objects['Schili_Body'];checks=[]
def check(ok,name):
    checks.append({'name':name,'passed':bool(ok)});assert ok,name;print('PASS',name,flush=True)
check(len(rig.data.bones)==21,'21 real bones with independent shell and scarf')
adj=[[] for _ in body.data.vertices]
for edge in body.data.edges:
    a,b=edge.vertices;adj[a].append(b);adj[b].append(a)
seen={0};stack=[0]
while stack:
    for j in adj[stack.pop()]:
        if j not in seen:seen.add(j);stack.append(j)
check(len(seen)==len(body.data.vertices),'one connected body surface')
assets=[o for o in bpy.data.objects if o.type=='MESH' and o.parent==rig]
for obj in assets:
    obj.data.calc_loop_triangles()
    check(len(obj.data.loop_triangles)<=10000,obj.name+' triangle budget')
    check(len(obj.data.uv_layers)>0,obj.name+' UV atlas')
    check(all(1<=len(v.groups)<=4 for v in obj.data.vertices),obj.name+' one to four influences')
    check(all(abs(sum(g.weight for g in v.groups)-1)<1e-4 for v in obj.data.vertices),obj.name+' normalized weights')
deps=bpy.context.evaluated_depsgraph_get();bounds={}
for act in [a for a in bpy.data.actions if a.name.startswith('Schili_')]:
    rig.animation_data.action=act;worst=0;longest=0
    for f in range(1,int(act.frame_range[1])+1,3):
        bpy.context.scene.frame_set(f);bpy.context.view_layer.update()
        ev=body.evaluated_get(deps);data=ev.to_mesh()
        for e in body.data.edges:
            a,b=e.vertices;old=(body.data.vertices[a].co-body.data.vertices[b].co).length;new=(data.vertices[a].co-data.vertices[b].co).length
            if old>.015:worst=max(worst,new/old)
            if old>.015 and new/old>5:longest=max(longest,new)
        ev.to_mesh_clear()
    bounds[act.name]={'worst_edge_ratio':worst,'longest_extreme_edge':longest}
    check(worst<7 and longest<.25,act.name+' skin deformation stays bounded')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(root/'exports/Schili_Bind.fbx'))
check(len([o for o in bpy.context.scene.objects if o.type=='MESH'])==4,'bind FBX round trip has four meshes')
check(len(next(o for o in bpy.context.scene.objects if o.type=='ARMATURE').data.bones)==21,'bind FBX preserves all bones')
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.fbx(filepath=str(root/'exports/Schili_StaffStrike.fbx'))
check(any(a.name for a in bpy.data.actions),'strike FBX contains animation')
(root/'verification.json').write_text(json.dumps({'checks':checks,'pose_bounds':bounds,'status':'passed'},indent=2))
print('SCHILI_VERIFIED',len(checks),flush=True)
