"""Calibrate the new Schili actions against the actual Studio skeleton and export Luau."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
shared=(root.parent/'krokero/source/export_roblox_motion.py').read_text(encoding='utf-8')
shared=shared.replace("Krokero.blend","Schili.blend").replace("Krokero_Rig","Schili_Rig").replace("Krokero_Studio.rbxmx","Schili_Studio.rbxmx").replace("KrokoMotion.luau","SchiliMotion.luau")
shared=shared.replace("('Kroko_Idle','Kroko_Walk','Kroko_ClubStrike','Kroko_Stagger')", "('Schili_Idle','Schili_Walk','Schili_StaffStrike','Schili_Feint','Schili_StaffSweep','Schili_ShellGuard','Schili_Rush','Schili_Stagger','Schili_Bow')")
shared=shared.replace("'clips':4","'clips':9")
exec(compile(shared,str(__file__),'exec'))
