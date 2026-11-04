"""Check connected skin, deformation across every clip and FBX round trips."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
shared=(root.parent/'schili/source/validate_schili.py').read_text(encoding='utf-8')
shared=shared.replace('Schili','Otti').replace('SCHILI','OTTI').replace('==21','==26').replace('21 real bones with independent shell and scarf','26 bones with flexible spine and six tail joints').replace('==4,','==7,').replace('four meshes','seven meshes').replace('Otti_StaffStrike.fbx','Otti_Animations.fbx')
exec(compile(shared,str(__file__),'exec'))
