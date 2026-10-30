"""Preview actual skinned animation and visualize the real skeleton, no asset edits."""
import bpy,math
from pathlib import Path
from mathutils import Vector
root=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(root/'Krokero.blend'))
scene=bpy.context.scene; rig=bpy.data.objects['Krokero_Rig']
scene.render.resolution_x=640; scene.render.resolution_y=640
scene.cycles.samples=12
folder=root/'previews/walk_frames'; folder.mkdir(exist_ok=True)
rig.animation_data.action=bpy.data.actions['Kroko_Walk']
for frame in range(1,31,2):
    scene.frame_set(frame)
    scene.render.filepath=str(folder/f'{frame:03}.png')
    bpy.ops.render.render(write_still=True)

# A separate render generated from pose bone positions makes the delivered rig visible.
rig.animation_data.action=bpy.data.actions['Kroko_Idle']; scene.frame_set(1)
for name in ('Krokero_Details','Krokero_Shield','Krokero_TrainingClub'):
    bpy.data.objects[name].hide_render=True
body=bpy.data.objects['Krokero_Body']
mat=bpy.data.materials.new('PREVIEW_ONLY_translucent_skin'); mat.use_nodes=True
nt=mat.node_tree;nt.nodes.clear()
out=nt.nodes.new('ShaderNodeOutputMaterial');mix=nt.nodes.new('ShaderNodeMixShader')
trans=nt.nodes.new('ShaderNodeBsdfTransparent');bs=nt.nodes.new('ShaderNodeBsdfPrincipled')
bs.inputs['Base Color'].default_value=(.11,.32,.19,1);bs.inputs['Roughness'].default_value=.6
mix.inputs[0].default_value=.16
nt.links.new(trans.outputs[0],mix.inputs[1]);nt.links.new(bs.outputs[0],mix.inputs[2]);nt.links.new(mix.outputs[0],out.inputs[0])
body.data.materials.clear();body.data.materials.append(mat)
bone_mat=bpy.data.materials.new('PREVIEW_ONLY_bone_cyan');bone_mat.use_nodes=True
bs=bone_mat.node_tree.nodes.get('Principled BSDF')
bs.inputs['Base Color'].default_value=(.08,.7,1,1)
bs.inputs['Emission Color'].default_value=(.04,.45,.8,1);bs.inputs['Emission Strength'].default_value=.5
for pb in rig.pose.bones:
    a=rig.matrix_world@pb.head;b=rig.matrix_world@pb.tail
    bpy.ops.mesh.primitive_cylinder_add(vertices=10,radius=.014,depth=(b-a).length,location=(a+b)/2)
    obj=bpy.context.object;obj.name='PREVIEW_BONE_'+pb.name
    obj.rotation_mode='QUATERNION';obj.rotation_quaternion=Vector((0,0,1)).rotation_difference((b-a).normalized())
    obj.data.materials.append(bone_mat)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=8,radius=.028,location=a)
    bpy.context.object.data.materials.append(bone_mat)
scene.render.resolution_x=1000;scene.render.resolution_y=1000;scene.cycles.samples=24
scene.render.filepath=str(root/'previews/Krokero_skeleton.png')
bpy.ops.render.render(write_still=True)
print('MOTION_REVIEW_COMPLETE',flush=True)
