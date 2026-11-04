"""Build every original 3D asset for Trailblazer Dash.

Run headless:

    blender -b -P Blender/build_assets.py

Outputs editable .blend files next to this script and GLBs into Assets/Models/.
Everything is authored from primitives and procedural placement, so the source
is reproducible rather than a binary black box.
"""

import math
import os
import sys

import bpy
from mathutils import Euler, Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS = os.path.join(ROOT, "Assets", "Models")
BLEND_DIR = os.path.join(ROOT, "Blender")
os.makedirs(os.path.join(MODELS, "props"), exist_ok=True)
os.makedirs(os.path.join(MODELS, "characters"), exist_ok=True)

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

MATS = {}


def srgb(hex_value):
    value = hex_value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def mat(name, color, rough=0.65, metal=0.0, emission=None, strength=0.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    rgb = srgb(color) if isinstance(color, str) else color
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emission:
        er = srgb(emission) if isinstance(emission, str) else emission
        bsdf.inputs["Emission Color"].default_value = (*er, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength or 1.0
    MATS[name] = m
    return m


def _paint(obj, m, name, flat=False):
    obj.name = name
    obj.data.materials.clear()
    if m is not None:
        obj.data.materials.append(m)
    if flat:
        for poly in obj.data.polygons:
            poly.use_smooth = False
    return obj


def box(name, size, loc, m, rot=(0, 0, 0), flat=False):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _paint(o, m, name, flat)


def sphere(name, radius, loc, m, scale=(1, 1, 1), subdiv=2, flat=False):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius, location=loc)
    o = bpy.context.object
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _paint(o, m, name, flat)


def cyl(name, radius, depth, loc, m, verts=10, rot=(0, 0, 0), flat=False):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth,
                                        location=loc, rotation=rot)
    return _paint(bpy.context.object, m, name, flat)


def cone(name, r1, r2, depth, loc, m, verts=10, rot=(0, 0, 0), flat=True):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth,
                                    location=loc, rotation=rot)
    return _paint(bpy.context.object, m, name, flat)


def torus(name, major, minor, loc, m, rot=(0, 0, 0), segments=16, minor_segments=6):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=segments, minor_segments=minor_segments,
                                     location=loc, rotation=rot)
    return _paint(bpy.context.object, m, name)


def jitter(obj, amount, seed):
    """Push vertices around with a stable hash so low-poly rocks feel hand-cut."""
    for index, v in enumerate(obj.data.vertices):
        n = math.sin((index + seed) * 12.9898) * 43758.5453
        a = (n - math.floor(n)) - 0.5
        n2 = math.sin((index + seed) * 78.233) * 12345.678
        b = (n2 - math.floor(n2)) - 0.5
        n3 = math.sin((index + seed) * 37.719) * 9876.543
        c = (n3 - math.floor(n3)) - 0.5
        v.co += Vector((a, b, c)) * amount


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    joined = bpy.context.object
    joined.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return joined


def export(obj_or_list, path, animations=False):
    objs = obj_or_list if isinstance(obj_or_list, (list, tuple)) else [obj_or_list]
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]

    rna = bpy.ops.export_scene.gltf.get_rna_type().properties
    kwargs = {
        "filepath": path,
        "export_format": "GLB",
        "use_selection": True,
        "export_apply": True,
        "export_yup": True,
        "export_animations": animations,
        "export_animation_mode": "ACTIONS",
        "export_skins": animations,
        "export_materials": "EXPORT",
        "export_cameras": False,
        "export_lights": False,
    }
    kwargs = {k: v for k, v in kwargs.items() if k in rna}
    bpy.ops.export_scene.gltf(**kwargs)
    print("exported", os.path.relpath(path, ROOT))


# --------------------------------------------------------------------------
# Pip — the original Trailblazer
# --------------------------------------------------------------------------

TEAL = "#2f7d78"
TEAL_DARK = "#245f5c"
MUSTARD = "#e8a33d"
CREAM = "#efe3c6"
BROWN = "#6f4a33"
BROWN_DARK = "#4a2f22"
SKIN = "#e2b18c"
HAIR = "#3a2a24"
CORAL = "#e2674f"
LEAF = "#4f9d69"


def build_pip():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    m_teal = mat("pip_jacket", TEAL, 0.6)
    m_teal_dark = mat("pip_trousers", TEAL_DARK, 0.7)
    m_mustard = mat("pip_accent", MUSTARD, 0.55)
    m_cream = mat("pip_hat", CREAM, 0.75)
    m_brown = mat("pip_leather", BROWN, 0.7)
    m_brown_dark = mat("pip_boot", BROWN_DARK, 0.65)
    m_skin = mat("pip_skin", SKIN, 0.75)
    m_hair = mat("pip_hair", HAIR, 0.8)
    m_coral = mat("pip_scarf", CORAL, 0.7)
    m_dark = mat("pip_eye", "#241a18", 0.4)

    bones = {
        "Root": ((0, 0, 0.0), (0, 0, 0.18), None),
        "Hips": ((0, 0, 0.70), (0, 0, 0.90), "Root"),
        "Spine": ((0, 0, 0.90), (0, 0, 1.20), "Hips"),
        "Head": ((0, 0, 1.20), (0, 0, 1.55), "Spine"),
        "Arm.L": ((0.17, 0, 1.14), (0.21, 0, 0.86), "Spine"),
        "Arm.R": ((-0.17, 0, 1.14), (-0.21, 0, 0.86), "Spine"),
        "Leg.L": ((0.10, 0, 0.76), (0.10, 0, 0.34), "Hips"),
        "Leg.R": ((-0.10, 0, 0.76), (-0.10, 0, 0.34), "Hips"),
        "Pack": ((0, 0.12, 1.05), (0, 0.30, 1.05), "Spine"),
    }

    parts = []

    def part(obj, bone):
        group = obj.vertex_groups.new(name=bone)
        group.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        parts.append(obj)
        return obj

    # pelvis and torso
    part(box("pelvis", (0.30, 0.22, 0.20), (0, 0, 0.78), m_teal_dark), "Hips")
    part(box("torso", (0.36, 0.24, 0.32), (0, 0, 1.04), m_teal), "Spine")
    part(box("chest_strap", (0.38, 0.02, 0.05), (0, -0.12, 1.06), m_mustard), "Spine")
    part(box("belt", (0.34, 0.23, 0.05), (0, 0, 0.90), m_brown), "Spine")

    # head, face, hat
    part(sphere("head", 0.205, (0, 0, 1.34), m_skin, scale=(1.0, 0.95, 1.05)), "Head")
    part(sphere("hair", 0.21, (0, 0.015, 1.40), m_hair, scale=(1.0, 0.98, 0.62)), "Head")
    part(sphere("eye_l", 0.024, (0.065, -0.178, 1.35), m_dark, subdiv=1), "Head")
    part(sphere("eye_r", 0.024, (-0.065, -0.178, 1.35), m_dark, subdiv=1), "Head")
    part(sphere("cheek_l", 0.028, (0.115, -0.16, 1.30), m_coral, subdiv=1), "Head")
    part(sphere("cheek_r", 0.028, (-0.115, -0.16, 1.30), m_coral, subdiv=1), "Head")
    part(cyl("hat_brim", 0.255, 0.022, (0, 0, 1.47), m_cream, verts=16), "Head")
    part(cyl("hat_dome", 0.155, 0.11, (0, 0, 1.52), m_cream, verts=16, flat=False), "Head")
    part(cyl("hat_band", 0.16, 0.032, (0, 0, 1.475), m_mustard, verts=16), "Head")

    # scarf
    part(cyl("scarf", 0.118, 0.07, (0, 0, 1.19), m_coral, verts=12), "Spine")
    part(box("scarf_tail", (0.09, 0.03, 0.16), (0.10, 0.10, 1.10), m_coral), "Spine")

    # arms
    for side, sign in (("L", 1), ("R", -1)):
        part(cyl("arm_" + side, 0.05, 0.30, (0.20 * sign, 0, 1.00), m_teal, verts=8), "Arm." + side)
        part(sphere("hand_" + side, 0.055, (0.205 * sign, 0, 0.855), m_skin, subdiv=1), "Arm." + side)

    # legs
    for side, sign in (("L", 1), ("R", -1)):
        part(cyl("leg_" + side, 0.062, 0.32, (0.10 * sign, 0, 0.56), m_teal_dark, verts=8), "Leg." + side)
        part(box("boot_" + side, (0.14, 0.22, 0.11), (0.10 * sign, -0.02, 0.375), m_brown_dark), "Leg." + side)

    # backpack and bedroll
    part(box("pack", (0.26, 0.14, 0.24), (0, 0.18, 1.06), m_brown), "Pack")
    part(cyl("bedroll", 0.06, 0.30, (0, 0.20, 1.20), m_mustard, verts=8,
             rot=(0, math.pi / 2, 0)), "Pack")

    # little wayfinder compass on the belt
    part(cyl("compass", 0.05, 0.02, (0.15, -0.11, 1.00), m_mustard, verts=12,
             rot=(math.pi / 2, 0, 0)), "Spine")

    mesh = join(parts, "PipBody")

    # armature
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    rig = bpy.context.object
    rig.name = "PipRig"
    rig.data.name = "PipRigData"
    edit = rig.data.edit_bones
    for bone in list(edit):
        edit.remove(bone)
    made = {}
    for name, (head, tail, parent) in bones.items():
        b = edit.new(name)
        b.head = Vector(head)
        b.tail = Vector(tail)
        b.use_connect = False
        if parent:
            b.parent = made[parent]
        made[name] = b
    bpy.ops.object.mode_set(mode="OBJECT")

    mesh.parent = rig
    modifier = mesh.modifiers.new("Armature", "ARMATURE")
    modifier.object = rig
    modifier.use_vertex_groups = True

    for bone in rig.pose.bones:
        bone.rotation_mode = "XYZ"

    def key(action_name, length, tracks):
        rig.animation_data_create()
        act = bpy.data.actions.new(action_name)
        act.use_fake_user = True
        rig.animation_data.action = act
        for pb in rig.pose.bones:
            pb.rotation_euler = Euler((0, 0, 0))
            pb.location = Vector((0, 0, 0))
            pb.scale = Vector((1, 1, 1))
        for bone_name, keys in tracks.items():
            pb = rig.pose.bones[bone_name]
            for frame, rot, loc in keys:
                pb.rotation_euler = Euler(rot)
                pb.keyframe_insert("rotation_euler", frame=frame)
                if loc is not None:
                    pb.location = Vector(loc)
                    pb.keyframe_insert("location", frame=frame)
        # Explicit base pose at the ends keeps clips independent.
        for bone_name, pb in rig.pose.bones.items():
            if bone_name in tracks:
                continue
            pb.rotation_euler = Euler((0, 0, 0))
            pb.location = Vector((0, 0, 0))
            pb.keyframe_insert("rotation_euler", frame=1)
            pb.keyframe_insert("location", frame=1)
            pb.keyframe_insert("rotation_euler", frame=length)
        act.frame_range  # touch so Blender recalculates
        rig.animation_data.action = None
        return act

    def legs(phase, spread=0.85):
        return [(1, (0, 0, 0), None),
                (7, (phase * spread, 0, 0), None),
                (13, (0, 0, 0), None),
                (19, (-phase * spread, 0, 0), None),
                (25, (0, 0, 0), None)]

    key("Idle", 61, {
        "Spine": [(1, (0.02, 0, 0), None), (31, (0.06, 0, 0), None), (61, (0.02, 0, 0), None)],
        "Head": [(1, (0, 0, 0), None), (31, (-0.03, 0.05, 0), None), (61, (0, 0, 0), None)],
        "Arm.L": [(1, (0.04, 0, -0.08), None), (31, (0.08, 0, -0.10), None), (61, (0.04, 0, -0.08), None)],
        "Arm.R": [(1, (0.04, 0, 0.08), None), (31, (0.08, 0, 0.10), None), (61, (0.04, 0, 0.08), None)],
        "Hips": [(1, (0, 0, 0), (0, 0, 0)), (31, (0, 0, 0), (0, 0.012, 0)), (61, (0, 0, 0), (0, 0, 0))],
    })

    key("Run", 25, {
        "Spine": [(1, (0.20, 0, 0), None), (13, (0.26, 0, 0), None), (25, (0.20, 0, 0), None)],
        "Head": [(1, (-0.12, 0, 0), None), (13, (-0.16, 0, 0), None), (25, (-0.12, 0, 0), None)],
        "Arm.L": [(1, (0.9, 0, -0.10), None), (7, (0, 0, -0.10), None), (13, (-0.9, 0, -0.10), None),
                  (19, (0, 0, -0.10), None), (25, (0.9, 0, -0.10), None)],
        "Arm.R": [(1, (-0.9, 0, 0.10), None), (7, (0, 0, 0.10), None), (13, (0.9, 0, 0.10), None),
                  (19, (0, 0, 0.10), None), (25, (-0.9, 0, 0.10), None)],
        "Hips": [(1, (0, 0, 0), (0, 0, 0)), (7, (0, 0, 0), (0, 0.045, 0)), (13, (0, 0, 0), (0, 0, 0)),
                 (19, (0, 0, 0), (0, 0.045, 0)), (25, (0, 0, 0), (0, 0, 0))],
        "Leg.L": legs(1),
        "Leg.R": legs(-1),
    })

    key("Jump", 21, {
        "Hips": [(1, (0, 0, 0), (0, 0, 0)), (6, (0, 0, 0), (0, 0.22, 0)), (20, (0, 0, 0), (0, 0, 0))],
        "Spine": [(1, (0.05, 0, 0), None), (6, (-0.16, 0, 0), None), (20, (0.05, 0, 0), None)],
        "Arm.L": [(1, (0.2, 0, -0.1), None), (6, (-2.1, 0, -0.4), None), (20, (0.2, 0, -0.1), None)],
        "Arm.R": [(1, (0.2, 0, 0.1), None), (6, (-2.1, 0, 0.4), None), (20, (0.2, 0, 0.1), None)],
        "Leg.L": [(1, (0, 0, 0), None), (6, (-1.1, 0, 0), None), (20, (0, 0, 0), None)],
        "Leg.R": [(1, (0, 0, 0), None), (6, (0.5, 0, 0), None), (20, (0, 0, 0), None)],
        "Head": [(1, (0, 0, 0), None), (6, (-0.12, 0, 0), None), (20, (0, 0, 0), None)],
    })

    key("Slide", 21, {
        "Hips": [(1, (0, 0, 0), (0, 0, 0)), (4, (-0.35, 0, 0), (0, -0.34, 0)),
                 (16, (-0.35, 0, 0), (0, -0.34, 0)), (21, (0, 0, 0), (0, 0, 0))],
        "Spine": [(1, (0, 0, 0), None), (4, (-0.5, 0, 0), None), (16, (-0.5, 0, 0), None), (21, (0, 0, 0), None)],
        "Leg.L": [(1, (0, 0, 0), None), (4, (-1.25, 0, 0), None), (16, (-1.25, 0, 0), None), (21, (0, 0, 0), None)],
        "Leg.R": [(1, (0, 0, 0), None), (4, (-0.4, 0, 0), None), (16, (-0.4, 0, 0), None), (21, (0, 0, 0), None)],
        "Arm.L": [(1, (0, 0, 0), None), (4, (0.8, 0, -0.5), None), (16, (0.8, 0, -0.5), None), (21, (0, 0, 0), None)],
        "Arm.R": [(1, (0, 0, 0), None), (4, (0.8, 0, 0.5), None), (16, (0.8, 0, 0.5), None), (21, (0, 0, 0), None)],
        "Head": [(1, (0, 0, 0), None), (4, (0.45, 0, 0), None), (16, (0.45, 0, 0), None), (21, (0, 0, 0), None)],
    })

    key("Stumble", 21, {
        "Spine": [(1, (0, 0, 0), None), (5, (0.55, 0, 0.22), None), (21, (0, 0, 0), None)],
        "Arm.L": [(1, (0, 0, 0), None), (5, (-1.1, 0, -0.9), None), (21, (0, 0, 0), None)],
        "Arm.R": [(1, (0, 0, 0), None), (5, (-1.1, 0, 0.9), None), (21, (0, 0, 0), None)],
        "Leg.L": [(1, (0, 0, 0), None), (5, (0.6, 0, 0), None), (21, (0, 0, 0), None)],
        "Head": [(1, (0, 0, 0), None), (5, (-0.3, 0, 0), None), (21, (0, 0, 0), None)],
    })

    key("Celebrate", 41, {
        "Arm.L": [(1, (0, 0, 0), None), (8, (-2.4, 0, -0.5), None), (16, (-2.0, 0, -0.5), None),
                  (24, (-2.4, 0, -0.5), None), (41, (0, 0, 0), None)],
        "Arm.R": [(1, (0, 0, 0), None), (8, (-2.4, 0, 0.5), None), (16, (-2.0, 0, 0.5), None),
                  (24, (-2.4, 0, 0.5), None), (41, (0, 0, 0), None)],
        "Hips": [(1, (0, 0, 0), (0, 0, 0)), (10, (0, 0, 0), (0, 0.14, 0)), (20, (0, 0, 0), (0, 0, 0)),
                 (30, (0, 0, 0), (0, 0.1, 0)), (41, (0, 0, 0), (0, 0, 0))],
        "Head": [(1, (0, 0, 0), None), (16, (-0.18, 0, 0), None), (41, (0, 0, 0), None)],
    })

    bpy.context.scene.frame_end = 61
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND_DIR, "Pip.blend"))
    export([rig, mesh], os.path.join(MODELS, "characters", "pip.glb"), animations=True)
    return rig


# --------------------------------------------------------------------------
# scenery and props
# --------------------------------------------------------------------------

def build_props():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()

    stone = mat("stone", "#9aa0a6", 0.85)
    stone_dark = mat("stone_dark", "#6c7278", 0.85)
    bark = mat("bark", "#7a5638", 0.8)
    bark_dark = mat("bark_dark", "#5a3f29", 0.8)
    leaf = mat("leaf", "#5aa86b", 0.7)
    leaf_dark = mat("leaf_dark", "#3d7f52", 0.7)
    pine = mat("pine", "#2f6b4f", 0.7)
    wood = mat("wood", "#b98a56", 0.72)
    wood_dark = mat("wood_dark", "#8a6240", 0.75)
    metal = mat("metal", "#8e9aa6", 0.35, metal=0.8)
    brass = mat("brass", "#c99a4a", 0.35, metal=0.75)
    glow = mat("glow", "#ffe6a1", 0.3, emission="#ffd166", strength=3.0)
    glow_cyan = mat("glow_cyan", "#bdf3ff", 0.3, emission="#8ee8ff", strength=2.6)
    crystal = mat("crystal", "#a98ff0", 0.25, emission="#8f6bff", strength=0.7)
    ice = mat("ice", "#d8f2ff", 0.2, emission="#bde9ff", strength=0.35)
    sand = mat("sand", "#e6cf9a", 0.8)
    dark = mat("obsidian", "#3b3340", 0.5)
    cream = mat("cream", "#efe3c6", 0.8)
    coral = mat("coral", "#e2674f", 0.7)

    # ground tile: light so the game can tint it per region
    tile_ground = mat("tile_ground", "#e8e8e8", 0.9)
    tile_edge = mat("tile_edge", "#cfcfcf", 0.9)
    tile_accent = mat("tile_accent", "#ffffff", 0.6)

    assets = {}

    def asset(name):
        def wrap(fn):
            assets[name] = fn
            return fn
        return wrap

    @asset("track_tile")
    def _tile():
        parts = [box("slab", (7.8, 20.0, 0.5), (0, 0, -0.25), tile_ground)]
        parts.append(box("kerb_l", (0.35, 20.0, 0.55), (-3.95, 0, -0.2), tile_edge))
        parts.append(box("kerb_r", (0.35, 20.0, 0.55), (3.95, 0, -0.2), tile_edge))
        for lane in (-1.3, 1.3):
            parts.append(box("strip", (0.06, 20.0, 0.02), (lane, 0, 0.005), tile_accent))
        for i in range(4):
            parts.append(box("mark", (0.5, 0.9, 0.02), (0, -8 + i * 5, 0.012), tile_accent))
        return parts

    @asset("rock_big")
    def _rock_big():
        parts = [sphere("rock", 1.25, (0, 0, 0.85), stone, scale=(1.1, 1.0, 0.9), subdiv=1, flat=True)]
        parts.append(sphere("rock2", 0.7, (0.9, 0.4, 0.45), stone_dark, scale=(1.0, 1.1, 0.8), subdiv=1, flat=True))
        for p in parts:
            jitter(p, 0.22, 3)
        return parts

    @asset("rock_small")
    def _rock_small():
        parts = [sphere("rock", 0.55, (0, 0, 0.36), stone, scale=(1.2, 0.9, 0.75), subdiv=1, flat=True)]
        for p in parts:
            jitter(p, 0.12, 9)
        return parts

    @asset("log")
    def _log():
        parts = [cyl("trunk", 0.34, 3.1, (0, 0, 0.34), bark, verts=9, rot=(0, math.pi / 2, 0), flat=True)]
        parts.append(cyl("cut_l", 0.35, 0.06, (1.55, 0, 0.34), wood, verts=9, rot=(0, math.pi / 2, 0)))
        parts.append(cyl("cut_r", 0.35, 0.06, (-1.55, 0, 0.34), wood, verts=9, rot=(0, math.pi / 2, 0)))
        parts.append(cyl("branch", 0.10, 0.7, (0.4, 0, 0.75), bark_dark, verts=6, rot=(0.5, 0, 0.4)))
        return parts

    @asset("tree_round")
    def _tree_round():
        parts = [cyl("trunk", 0.26, 2.2, (0, 0, 1.1), bark, verts=8)]
        parts.append(sphere("canopy", 1.35, (0, 0, 2.75), leaf, scale=(1.05, 1.0, 0.95), subdiv=1, flat=True))
        parts.append(sphere("canopy2", 0.95, (0.85, 0.25, 2.3), leaf_dark, subdiv=1, flat=True))
        parts.append(sphere("canopy3", 0.85, (-0.75, -0.3, 2.45), leaf_dark, subdiv=1, flat=True))
        return parts

    @asset("tree_pine")
    def _tree_pine():
        parts = [cyl("trunk", 0.22, 1.9, (0, 0, 0.95), bark, verts=8)]
        for i, (r, h, z) in enumerate(((1.35, 1.9, 1.55), (1.05, 1.7, 2.5), (0.72, 1.4, 3.4))):
            parts.append(cone("cone%d" % i, r, 0.0, h, (0, 0, z), pine if i % 2 == 0 else leaf_dark, verts=9))
        return parts

    @asset("mushroom")
    def _mushroom():
        parts = [cyl("stem", 0.16, 0.55, (0, 0, 0.27), cream, verts=8)]
        parts.append(cone("cap", 0.55, 0.05, 0.42, (0, 0, 0.65), coral, verts=10))
        parts.append(sphere("spot", 0.06, (0.2, -0.25, 0.75), cream, subdiv=1))
        parts.append(sphere("spot2", 0.05, (-0.22, -0.2, 0.72), cream, subdiv=1))
        return parts

    @asset("crystal")
    def _crystal():
        parts = [cone("c1", 0.28, 0.02, 2.2, (0, 0, 1.1), crystal, verts=6)]
        parts.append(cone("c2", 0.2, 0.02, 1.5, (0.45, 0.15, 1.3), crystal, verts=6, rot=(0, 0.3, 0)))
        parts.append(cone("c3", 0.16, 0.02, 1.15, (-0.4, -0.2, 1.05), crystal, verts=6, rot=(0.2, -0.28, 0)))
        parts.append(sphere("base", 0.5, (0, 0, 0.15), stone_dark, scale=(1.2, 1.2, 0.4), subdiv=1, flat=True))
        return parts

    @asset("ice_spire")
    def _ice_spire():
        parts = [cone("spire", 0.55, 0.02, 3.0, (0, 0, 1.5), ice, verts=7)]
        parts.append(cone("spire2", 0.34, 0.02, 1.7, (0.5, 0.2, 1.1), ice, verts=6, rot=(0, 0.25, 0)))
        parts.append(cone("spire3", 0.28, 0.02, 1.2, (-0.45, -0.15, 0.85), ice, verts=6, rot=(-0.2, -0.2, 0)))
        return parts

    @asset("cactus")
    def _cactus():
        parts = [cyl("body", 0.32, 2.1, (0, 0, 1.05), leaf_dark, verts=8)]
        parts.append(cyl("arm", 0.18, 0.8, (0.45, 0, 1.35), leaf_dark, verts=7, rot=(0, 0.9, 0)))
        parts.append(cyl("arm2", 0.15, 0.6, (-0.4, 0, 1.05), leaf_dark, verts=7, rot=(0, -0.9, 0)))
        parts.append(sphere("flower", 0.13, (0, 0, 2.15), coral, subdiv=1))
        return parts

    @asset("palm")
    def _palm():
        parts = []
        for i in range(4):
            parts.append(cyl("seg%d" % i, 0.2 - i * 0.02, 1.0, (i * 0.14, 0, 0.5 + i * 0.95), bark, verts=8,
                             rot=(0, 0.16 * (i + 1), 0)))
        for i in range(6):
            angle = i * math.pi / 3
            parts.append(box("frond%d" % i, (1.7, 0.44, 0.06),
                             (math.cos(angle) * 0.8, math.sin(angle) * 0.8, 3.65),
                             leaf_dark, rot=(0, 0.25, angle), flat=True))
        return parts

    @asset("fern")
    def _fern():
        parts = []
        for i in range(5):
            angle = i * math.tau / 5
            parts.append(cone("leaf%d" % i, 0.22, 0.0, 1.3,
                              (math.cos(angle) * 0.35, math.sin(angle) * 0.35, 0.55),
                              leaf, verts=5, rot=(0.5 * math.cos(angle), 0.5 * math.sin(angle), angle)))
        return parts

    @asset("reed")
    def _reed():
        parts = []
        for i in range(7):
            h = 1.1 + (i % 4) * 0.25
            parts.append(cyl("reed%d" % i, 0.045, h, ((i % 3) * 0.2 - 0.2, (i // 3) * 0.2 - 0.2, h / 2),
                             leaf_dark, verts=5, rot=(0.08 * (i % 3), 0.06 * (i % 2), 0)))
        return parts

    @asset("ruin_pillar")
    def _ruin_pillar():
        parts = [box("base", (1.0, 1.0, 0.28), (0, 0, 0.14), stone_dark),
                 cyl("shaft", 0.38, 2.6, (0, 0, 1.55), stone, verts=10),
                 box("cap", (0.95, 0.95, 0.22), (0, 0, 2.94), stone_dark)]
        parts.append(cyl("crack", 0.40, 0.1, (0, 0, 2.2), stone_dark, verts=10))
        return parts

    @asset("ruin_arch")
    def _ruin_arch():
        parts = [box("p_l", (0.7, 0.7, 3.0), (-1.6, 0, 1.5), stone),
                 box("p_r", (0.7, 0.7, 3.0), (1.6, 0, 1.5), stone),
                 box("lintel", (4.1, 0.8, 0.55), (0, 0, 3.15), stone_dark),
                 box("base_l", (1.0, 1.0, 0.22), (-1.6, 0, 0.11), stone_dark),
                 box("base_r", (1.0, 1.0, 0.22), (1.6, 0, 0.11), stone_dark)]
        parts.append(cyl("medallion", 0.36, 0.12, (0, -0.42, 3.0), glow, verts=12,
                         rot=(math.pi / 2, 0, 0)))
        return parts

    @asset("statue")
    def _statue():
        parts = [box("plinth", (1.5, 1.5, 0.6), (0, 0, 0.3), stone_dark),
                 box("body", (0.7, 0.6, 1.5), (0, 0, 1.35), stone),
                 sphere("head", 0.28, (0, 0, 2.3), stone, subdiv=1),
                 box("arm_l", (0.22, 0.22, 0.9), (0.45, 0, 1.5), stone, rot=(0, 0.3, 0)),
                 box("arm_r", (0.22, 0.22, 0.9), (-0.45, 0, 1.5), stone, rot=(0, -0.3, 0))]
        return parts

    @asset("gear")
    def _gear():
        parts = [cyl("hub", 1.1, 0.4, (0, 0, 1.1), brass, verts=16, rot=(math.pi / 2, 0, 0))]
        for i in range(8):
            a = i * math.tau / 8
            parts.append(box("tooth%d" % i, (0.32, 0.42, 0.34),
                             (math.cos(a) * 1.1, 0, 1.1 + math.sin(a) * 1.1), brass,
                             rot=(0, -a, 0)))
        parts.append(cyl("axle", 0.26, 0.9, (0, 0, 1.1), metal, verts=10, rot=(math.pi / 2, 0, 0)))
        parts.append(box("stand", (1.4, 0.5, 0.3), (0, 0, 0.15), stone_dark))
        return parts

    @asset("lamp_post")
    def _lamp_post():
        parts = [cyl("post", 0.09, 3.2, (0, 0, 1.6), metal, verts=8),
                 box("arm", (1.1, 0.12, 0.12), (0.45, 0, 3.1), metal),
                 box("lantern", (0.38, 0.38, 0.5), (0.9, 0, 2.9), glow),
                 box("cap", (0.5, 0.5, 0.08), (0.9, 0, 3.16), metal),
                 box("foot", (0.4, 0.4, 0.18), (0, 0, 0.09), stone_dark)]
        return parts

    @asset("lantern")
    def _lantern():
        parts = [torus("ring", 0.35, 0.05, (0, 0, 2.4), metal, rot=(math.pi / 2, 0, 0), segments=12),
                 box("body", (0.45, 0.45, 0.6), (0, 0, 1.95), glow),
                 box("top", (0.55, 0.55, 0.1), (0, 0, 2.3), metal),
                 box("bottom", (0.55, 0.55, 0.1), (0, 0, 1.6), metal)]
        return parts

    @asset("crate")
    def _crate():
        parts = [box("body", (1.2, 1.2, 1.2), (0, 0, 0.6), wood)]
        for z in (0.08, 1.12):
            parts.append(box("band", (1.24, 1.24, 0.12), (0, 0, z), wood_dark))
        for x in (-0.5, 0.5):
            parts.append(box("rib", (0.12, 1.24, 1.16), (x, 0, 0.6), wood_dark))
        parts.append(box("glyph", (0.4, 0.04, 0.4), (0, -0.62, 0.65), brass))
        return parts

    @asset("timber_frame")
    def _timber_frame():
        parts = [box("leg_l", (0.3, 0.3, 3.2), (-1.3, 0, 1.6), wood_dark, rot=(0, 0.18, 0)),
                 box("leg_r", (0.3, 0.3, 3.2), (1.3, 0, 1.6), wood_dark, rot=(0, -0.18, 0)),
                 box("beam", (3.0, 0.34, 0.34), (0, 0, 3.05), wood),
                 box("brace", (2.1, 0.22, 0.22), (0, 0, 2.1), wood, rot=(0, 0, 0.5)),
                 box("wheel", (0.9, 0.2, 0.9), (1.5, 0, 0.55), metal)]
        return parts

    @asset("banner")
    def _banner():
        parts = [cyl("pole", 0.09, 4.0, (0, 0, 2.0), wood_dark, verts=8),
                 box("cloth", (1.1, 0.05, 1.9), (0.62, 0, 3.0), cream),
                 box("stripe", (1.1, 0.06, 0.28), (0.62, 0, 3.6), coral),
                 sphere("finial", 0.12, (0, 0, 4.05), brass, subdiv=1)]
        return parts

    @asset("topiary")
    def _topiary():
        parts = [cyl("trunk", 0.16, 0.7, (0, 0, 0.35), bark, verts=8),
                 sphere("bush", 0.95, (0, 0, 1.4), leaf, scale=(1.0, 1.0, 1.1), subdiv=1, flat=True),
                 sphere("bush2", 0.62, (0.35, 0.2, 2.1), leaf_dark, subdiv=1, flat=True),
                 box("pot", (1.0, 1.0, 0.4), (0, 0, 0.2), stone_dark)]
        return parts

    @asset("obsidian")
    def _obsidian():
        parts = [cone("shard", 0.6, 0.03, 2.4, (0, 0, 1.2), dark, verts=5)]
        parts.append(cone("shard2", 0.35, 0.02, 1.4, (0.5, 0.2, 0.7), dark, verts=5, rot=(0, 0.35, 0)))
        parts.append(cone("shard3", 0.3, 0.02, 1.1, (-0.45, -0.2, 0.55), dark, verts=5, rot=(0.2, -0.3, 0)))
        return parts

    @asset("beacon")
    def _beacon():
        parts = [box("plinth", (2.2, 2.2, 0.7), (0, 0, 0.35), stone_dark),
                 cone("tower", 1.0, 0.55, 4.2, (0, 0, 2.8), stone, verts=8),
                 torus("ring", 0.95, 0.10, (0, 0, 3.6), brass, rot=(math.pi / 2, 0, 0), segments=20),
                 sphere("core", 0.5, (0, 0, 4.55), glow, subdiv=2),
                 cone("roof", 0.7, 0.05, 1.0, (0, 0, 5.2), brass, verts=8)]
        return parts

    @asset("gate")
    def _gate():
        parts = [torus("ring", 1.25, 0.16, (0, 0, 1.6), glow_cyan, rot=(0, math.pi / 2, 0), segments=20),
                 box("post_l", (0.3, 0.3, 1.2), (0, -1.15, 0.6), stone_dark),
                 box("post_r", (0.3, 0.3, 1.2), (0, 1.15, 0.6), stone_dark),
                 box("lintel", (0.4, 2.8, 0.3), (0, 0, 3.0), stone_dark)]
        return parts

    @asset("spark")
    def _spark():
        parts = [sphere("spark", 0.24, (0, 0, 0.35), glow, subdiv=1),
                 torus("halo", 0.34, 0.035, (0, 0, 0.35), glow, rot=(math.pi / 2, 0, 0), segments=12)]
        return parts

    @asset("relic")
    def _relic():
        parts = [cyl("disc", 0.34, 0.1, (0, 0, 0.8), brass, verts=12, rot=(math.pi / 2, 0, 0)),
                 cone("star", 0.22, 0.0, 0.3, (0, -0.08, 0.8), glow, verts=4, rot=(math.pi / 2, 0, 0)),
                 torus("ring", 0.36, 0.04, (0, 0, 0.8), glow, rot=(0, math.pi / 2, 0), segments=14)]
        return parts

    @asset("powerup_crate")
    def _powerup_crate():
        parts = [box("body", (1.0, 1.0, 1.0), (0, 0, 0.6), cream),
                 box("band_h", (1.06, 1.06, 0.16), (0, 0, 0.6), coral),
                 box("band_v", (0.16, 1.06, 1.06), (0, 0, 0.6), coral),
                 sphere("core", 0.24, (0, 0, 0.6), glow, subdiv=1)]
        return parts

    @asset("hurdle")
    def _hurdle():
        parts = [box("post_l", (0.18, 0.18, 1.0), (-1.1, 0, 0.5), wood_dark),
                 box("post_r", (0.18, 0.18, 1.0), (1.1, 0, 0.5), wood_dark),
                 box("rail", (2.5, 0.22, 0.3), (0, 0, 0.92), coral),
                 box("stripe", (2.5, 0.24, 0.1), (0, 0, 0.95), cream),
                 box("foot_l", (0.5, 0.5, 0.1), (-1.1, 0, 0.05), wood),
                 box("foot_r", (0.5, 0.5, 0.1), (1.1, 0, 0.05), wood)]
        return parts

    @asset("overhead_bar")
    def _bar():
        # The beam must sit low enough that standing hits it and sliding clears
        # it: bottom edge at 1.10m, which is under the 1.55m standing height.
        parts = [box("post_l", (0.2, 0.2, 3.0), (-1.35, 0, 1.5), metal),
                 box("post_r", (0.2, 0.2, 3.0), (1.35, 0, 1.5), metal),
                 box("beam", (3.2, 0.34, 0.5), (0, 0, 1.35), coral),
                 box("warn", (3.2, 0.36, 0.14), (0, 0, 1.36), cream),
                 box("flag_l", (0.6, 0.05, 0.35), (-1.35, 0, 2.4), cream),
                 box("flag_r", (0.6, 0.05, 0.35), (1.35, 0, 2.4), cream)]
        return parts

    @asset("block_wall")
    def _block():
        parts = [box("wall", (1.9, 1.5, 2.6), (0, 0, 1.3), stone),
                 box("cap", (2.05, 1.6, 0.18), (0, 0, 2.62), stone_dark),
                 box("emblem", (0.6, 0.1, 0.6), (0, -0.79, 1.5), coral)]
        for i in range(3):
            parts.append(box("crack%d" % i, (0.1, 0.06, 0.7), (-0.5 + i * 0.5, -0.77, 1.0), stone_dark,
                             rot=(0, 0, 0.2 * (i - 1))))
        return parts

    @asset("boulder")
    def _boulder():
        parts = [sphere("ball", 0.95, (0, 0, 0.95), stone_dark, subdiv=1, flat=True)]
        for i in range(4):
            a = i * math.tau / 4
            parts.append(box("stud%d" % i, (0.22, 0.22, 0.16),
                             (math.cos(a) * 0.9, 0, 0.95 + math.sin(a) * 0.9), stone,
                             rot=(0, -a, 0)))
        for p in parts:
            jitter(p, 0.08, 11 + i)
        return parts

    @asset("floating_island")
    def _island():
        parts = [cone("rock", 2.6, 0.2, 1.8, (0, 0, -0.9), stone_dark, verts=9, rot=(math.pi, 0, 0)),
                 cyl("grass", 2.6, 0.4, (0, 0, 0.1), leaf, verts=12),
                 sphere("bush", 0.7, (1.4, 0.4, 0.5), leaf_dark, subdiv=1, flat=True)]
        return parts

    @asset("finish_gate")
    def _finish_gate():
        parts = [box("post_l", (0.5, 0.5, 4.4), (-2.6, 0, 2.2), stone),
                 box("post_r", (0.5, 0.5, 4.4), (2.6, 0, 2.2), stone),
                 box("lintel", (6.0, 0.6, 0.8), (0, 0, 4.4), brass),
                 box("banner", (4.6, 0.1, 1.1), (0, -0.1, 3.6), coral),
                 cone("spire_l", 0.4, 0.05, 1.2, (-2.6, 0, 5.2), brass, verts=6),
                 cone("spire_r", 0.4, 0.05, 1.2, (2.6, 0, 5.2), brass, verts=6)]
        return parts

    made = {}
    for name, fn in assets.items():
        parts = fn()
        obj = join(parts, name)
        made[name] = obj
        export(obj, os.path.join(MODELS, "props", name + ".glb"))
        bpy.data.objects.remove(obj, do_unlink=True)

    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(BLEND_DIR, "Props.blend"))
    return made


if __name__ == "__main__":
    build_pip()
    build_props()
    print("asset build complete")
