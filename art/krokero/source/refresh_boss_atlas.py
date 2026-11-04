"""Bake surface detail onto a Blender boss without regenerating its UVs.

Open the original, untextured .blend and pass the output directory after --.
This preserves its mesh, rig, actions, and all other maps.
"""
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from boss_surfaces import Surface


def detail(material, hero, part):
    surface = Surface(material)
    base = surface.shader.inputs["Base Color"].links[0].from_socket
    if part == "Body":
        if hero == "Otti":
            surface.fur(.62)
        elif hero == "Krokero":
            surface.scales((1, 1, .82), 20, .52)
        else:
            surface.scales((1, 1, .92), 51, .43)
    elif hero == "Schili" and part == "Shell":
        metal = surface.shader.inputs["Metallic"].links[0].from_socket
        surface.horn()
        surface.keep_original(base, surface.math("GREATER_THAN", metal, .22))

def main():
    source = Path(bpy.data.filepath)
    staging = Path(sys.argv[sys.argv.index("--") + 1])
    hero = source.stem
    if hero not in ("Otti", "Schili", "Krokero"):
        raise ValueError(f"Unexpected boss source: {source.name}")
    staging.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    if scene.get("boss_surface_baked"):
        raise RuntimeError("Use the original atlas source to avoid applying the effect twice")
    old = bpy.data.images[f"{hero}_BaseColor"]
    texture = bpy.data.images.new(f"{hero}_SurfaceBake", width=old.size[0], height=old.size[1], alpha=False)
    texture.generated_color = (.15, .25, .13, 1)
    arms = [obj for obj in scene.objects if obj.type == "ARMATURE"]
    arm_states = [obj.data.pose_position for obj in arms]
    saved = []
    bpy.ops.object.select_all(action="DESELECT")
    for obj in scene.objects:
        if obj.type != "MESH" or not obj.name.startswith(hero + "_"):
            continue
        material = obj.data.materials[0]
        if not any(getattr(node, "image", None) == old for node in material.node_tree.nodes):
            continue
        bake_material = material.copy()
        obj.data.materials[0] = bake_material
        saved.append((obj, material, bake_material, obj.hide_render, obj.hide_viewport, obj.hide_get()))
        obj.hide_render = obj.hide_viewport = False
        obj.hide_set(False)
        obj.select_set(True)
        detail(bake_material, hero, obj.name.removeprefix(hero + "_"))
        tree = bake_material.node_tree
        emission = tree.nodes.new("ShaderNodeEmission")
        bsdf = tree.nodes.get("Principled BSDF")
        output = next(node for node in tree.nodes if node.type == "OUTPUT_MATERIAL")
        tree.links.new(bsdf.inputs["Base Color"].links[0].from_socket, emission.inputs["Color"])
        tree.links.new(emission.outputs[0], output.inputs["Surface"])
        target = tree.nodes.new("ShaderNodeTexImage")
        target.image = texture
        tree.nodes.active = target
    assert any(obj.name == f"{hero}_Body" for obj, *_ in saved)
    if hero == "Schili":
        assert any(obj.name == "Schili_Shell" for obj, *_ in saved)
    bpy.context.view_layer.objects.active = saved[0][0]
    for obj in arms:
        obj.data.pose_position = "REST"
    samples = scene.cycles.samples
    scene.cycles.samples = 1
    bpy.ops.object.bake(type="EMIT", margin=8, use_clear=False)
    scene.cycles.samples = samples
    for obj, pose in zip(arms, arm_states):
        obj.data.pose_position = pose
    for obj, material, bake_material, hidden_render, hidden_viewport, hidden in saved:
        obj.data.materials[0] = material
        obj.select_set(False)
        obj.hide_render, obj.hide_viewport = hidden_render, hidden_viewport
        obj.hide_set(hidden)
        bpy.data.materials.remove(bake_material)

    texture.file_format = "PNG"
    texture.filepath_raw = str(staging / f"{hero}_BaseColor.png")
    texture.save()
    texture.pack()
    texture.filepath = f"//textures/{hero}_BaseColor.png"
    old.user_remap(texture)
    bpy.data.images.remove(old)
    texture.name = f"{hero}_BaseColor"

    # Keep the review render separate from the saved source's camera and pose.
    scene["boss_surface_baked"] = True
    bpy.ops.wm.save_as_mainfile(filepath=str(staging / source.name))
    scene.render.resolution_percentage = 75
    scene.cycles.samples = 12
    scene.render.filepath = str(staging / f"{hero}_Surface.png")
    bpy.ops.render.render(write_still=True)
    if hero == "Schili":
        camera = scene.camera
        camera.location = (2.4, 5.5, 2.5)
        camera.rotation_euler = (Vector((0, .24, .87)) - camera.location).to_track_quat("-Z", "Y").to_euler()
        camera.data.ortho_scale = 1.9
        scene.render.filepath = str(staging / f"{hero}_Shell.png")
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    main()
