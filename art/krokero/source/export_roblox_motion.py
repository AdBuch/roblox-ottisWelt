"""Convert authored Blender actions into transforms of the actual Studio-imported bones."""
import bpy, json, numpy as np, xml.etree.ElementTree as ET
from pathlib import Path
from mathutils import Matrix

root=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(root/'Krokero.blend'))
rig=bpy.data.objects['Krokero_Rig']
xml=ET.parse(root/'exports/Krokero_Studio.rbxmx')
rest={}; local={}; parents={}
def cf(node):
    m=np.eye(4)
    for i,a in enumerate('XYZ'): m[i,3]=float(node.find(a).text)
    for i in range(3):
        for j in range(3): m[i,j]=float(node.find(f'R{i}{j}').text)
    return m
def walk(item,parent_matrix,parent_bone=None):
    props=item.find('Properties'); name=props.find("*[@name='Name']").text
    transform=props.find("*[@name='CFrame']")
    world=parent_matrix@cf(transform) if transform is not None else parent_matrix
    if item.attrib['class']=='Bone':
        rest[name]=world; local[name]=cf(transform); parents[name]=parent_bone; parent_bone=name
    for child in item.findall('Item'): walk(child,world,parent_bone)
walk(xml.find('Item'),np.eye(4))
names=list(rest)
src=np.array([tuple(rig.data.bones[n].head_local) for n in names])
dst=np.array([rest[n][:3,3] for n in names])
x=src-src.mean(0); y=dst-dst.mean(0)
u,s,vt=np.linalg.svd(x.T@y); rot=vt.T@u.T
if np.linalg.det(rot)<0: vt[-1]*=-1; rot=vt.T@u.T
scale=np.sum((x@rot.T)*y)/np.sum(x*x)
c=np.eye(4); c[:3,:3]=scale*rot; c[:3,3]=dst.mean(0)-scale*rot@src.mean(0)
error=np.max(np.linalg.norm((c[:3,:3]@src.T).T+c[:3,3]-dst,axis=1))
assert error<.001, error
ci=np.linalg.inv(c)
out=['-- Generated from Krokero.blend and the actual imported rest skeleton.','return {']
out.append('bones={'+','.join(json.dumps(n) for n in names)+'},')
for clip in ('Kroko_Idle','Kroko_Walk','Kroko_ClubStrike','Kroko_Stagger'):
    act=bpy.data.actions[clip]; rig.animation_data.action=act
    end=int(act.frame_range[1]); frames=list(range(1,end+1,3))
    if frames[-1]!=end: frames.append(end)
    out.append(f'[{json.dumps(clip)}]={{duration={(end-1)/30},frames={{')
    for f in frames:
        bpy.context.scene.frame_set(f); bpy.context.view_layer.update()
        posed={n:c@np.array(rig.pose.bones[n].matrix)@np.linalg.inv(np.array(rig.data.bones[n].matrix_local))@ci@rest[n] for n in names}
        values=[]
        for n in names:
            p=parents[n]
            parent=posed[p] if p else rest[n]@np.linalg.inv(local[n])
            t=np.linalg.inv(local[n])@np.linalg.inv(parent)@posed[n]
            q=Matrix(t.tolist()).to_quaternion()
            v=[*t[:3,3],q.x,q.y,q.z,q.w]
            values.extend(f'{float(a):.6g}' if abs(a)>1e-7 else '0' for a in v)
        out.append('{'+f'{(f-1)/30:.6g},' + ','.join(values)+'},')
    out.append('}},')
out.append('}')
target=root.parents[1]/'src/shared/KrokoMotion.luau'
target.write_text('\n'.join(out),encoding='utf-8')
(root/'roblox-motion-validation.json').write_text(json.dumps({'calibration_max_error':float(error),'scale':float(scale),'bone_count':len(names),'clips':4},indent=2))
print('ROBLOX_MOTION_EXPORTED',target,'calibration error',error)
