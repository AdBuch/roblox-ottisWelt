"""Procedural surface detail baked into the existing boss UV atlases."""

import bpy


class Surface:
    def __init__(self, material):
        self.tree = material.node_tree
        self.shader = self.tree.nodes.get("Principled BSDF")
        self.position = self.node("ShaderNodeTexCoord").outputs["Object"]

    def node(self, name):
        return self.tree.nodes.new(name)

    def set(self, socket, value):
        if isinstance(value, bpy.types.NodeSocket):
            self.tree.links.new(value, socket)
        else:
            socket.default_value = value

    def math(self, operation, a, b):
        node = self.node("ShaderNodeMath")
        node.operation = operation
        self.set(node.inputs[0], a)
        self.set(node.inputs[1], b)
        return node.outputs[0]

    def stretch(self, axes):
        node = self.node("ShaderNodeVectorMath")
        node.operation = "MULTIPLY"
        self.set(node.inputs[0], self.position)
        self.set(node.inputs[1], axes)
        return node.outputs[0]

    def noise(self, vector, scale, detail=2):
        node = self.node("ShaderNodeTexNoise")
        self.set(node.inputs["Vector"], vector)
        node.inputs["Scale"].default_value = scale
        node.inputs["Detail"].default_value = detail
        return node.outputs["Fac"]

    def ramp(self, value, stops):
        node = self.node("ShaderNodeValToRGB")
        self.set(node.inputs[0], value)
        elements = node.color_ramp.elements
        for index, (position, multiplier) in enumerate(stops):
            element = elements[index] if index < 2 else elements.new(position)
            element.position = position
            element.color = (multiplier, multiplier, multiplier, 1)
        return node.outputs["Color"]

    def multiply_color(self, factor):
        base = self.shader.inputs["Base Color"]
        original = base.links[0].from_socket if base.is_linked else tuple(base.default_value)
        node = self.node("ShaderNodeMixRGB")
        node.blend_type = "MULTIPLY"
        node.inputs[0].default_value = 1
        self.set(node.inputs[1], original)
        self.set(node.inputs[2], factor)
        self.set(base, node.outputs[0])

    def keep_original(self, original, mask):
        base = self.shader.inputs["Base Color"]
        node = self.node("ShaderNodeMixRGB")
        self.set(node.inputs[0], mask)
        self.set(node.inputs[1], base.links[0].from_socket)
        self.set(node.inputs[2], original)
        self.set(base, node.outputs[0])

    def scales(self, axes, density, contrast):
        vector = self.stretch(axes)
        edge = self.node("ShaderNodeTexVoronoi")
        edge.feature = "DISTANCE_TO_EDGE"
        self.set(edge.inputs["Vector"], vector)
        edge.inputs["Scale"].default_value = density
        profile = self.ramp(edge.outputs["Distance"], [
            (0, 1 - contrast), (.065, 1 - contrast * .7),
            (.14, 1 + contrast * .22), (.30, 1),
        ])
        self.multiply_color(profile)
        self.multiply_color(self.ramp(self.noise(vector, density * .72), [(.1, .84), (.9, 1.12)]))

    def fur(self, contrast):
        # Long, broken fibres over a broader variation in the coat.
        fibres = self.noise(self.stretch((1, .84, .22)), 76, 2)
        tufts = self.noise(self.stretch((1, 1, .42)), 19, 3)
        grain = self.math("ADD", self.math("MULTIPLY", fibres, .73),
                          self.math("MULTIPLY", tufts, .27))
        self.multiply_color(self.ramp(grain, [
            (.22, 1 - contrast), (.48, .95), (.63, 1.12), (.81, 1 + contrast * .63),
        ]))

    def horn(self):
        grain = self.noise(self.stretch((.39, .72, 1)), 38, 3)
        growth = self.node("ShaderNodeTexWave")
        growth.wave_type = "RINGS"
        growth.rings_direction = "Y"
        coordinates = self.node("ShaderNodeVectorMath")
        coordinates.operation = "SUBTRACT"
        self.set(coordinates.inputs[0], self.position)
        self.set(coordinates.inputs[1], (0, .16, .86))
        self.set(growth.inputs["Vector"], coordinates.outputs[0])
        growth.inputs["Scale"].default_value = 15
        growth.inputs["Distortion"].default_value = 3
        self.multiply_color(self.ramp(growth.outputs["Fac"], [(.08, .87), (.86, 1.05)]))
        self.multiply_color(self.ramp(grain, [(.16, .72), (.84, 1.19)]))

        # Tapered pale rims with a dark, weathered core. The strokes run across
        # the rear scutes in model space, so they continue over UV island seams.
        axes = self.node("ShaderNodeSeparateXYZ")
        self.set(axes.inputs[0], self.position)
        x, y, z = (axes.outputs[key] for key in "XYZ")
        for cx, cz, slope, length, width in [
            (-.28, 1.08, .94, .165, .019), (-.245, 1.015, .84, .127, .013),
            (.32, .73, -.74, .124, .017), (.365, .69, -.71, .088, .012),
        ]:
            dx = self.math("SUBTRACT", x, cx)
            line = self.math("ADD", cz, self.math("MULTIPLY", dx, slope))
            distance = self.math("ABSOLUTE", self.math("SUBTRACT", z, line), 0)
            end = self.math("DIVIDE", self.math("ABSOLUTE", dx, 0), length)
            across = self.math("DIVIDE", distance, width)
            shape = self.math("ADD", across, self.math("MULTIPLY", end, end))
            rear = self.math("GREATER_THAN", y, .30)
            shape = self.math("ADD", shape, self.math("SUBTRACT", 1, rear))
            self.multiply_color(self.ramp(shape, [
                (0, .31), (.20, .51), (.50, 1.45), (.86, 1.14), (1, 1),
            ]))
