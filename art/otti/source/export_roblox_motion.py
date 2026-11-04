"""Export 60 fps authored otter motion against the Studio-imported skeleton."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
shared=(root.parent/'krokero/source/export_roblox_motion.py').read_text(encoding='utf-8')
shared=shared.replace('Krokero','Otti').replace('KrokoMotion','OttiMotion')
shared=shared.replace("('Kroko_Idle','Kroko_Walk','Kroko_ClubStrike','Kroko_Stagger')", "tuple(a.name for a in bpy.data.actions if a.name.startswith('Otti_'))")
shared=shared.replace('end+1,3','end+1,2').replace('/30','/60').replace("'clips':4","'clips':28")
exec(compile(shared,str(__file__),'exec'))
