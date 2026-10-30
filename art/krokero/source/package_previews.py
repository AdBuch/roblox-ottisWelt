"""Combine actual Blender renders into review artifacts; no generated/repainted imagery."""
from pathlib import Path
from PIL import Image, ImageOps, ImageDraw
root=Path(__file__).resolve().parents[1]
paths=sorted((root/'previews/walk_frames').glob('*.png'))
assert len(paths)==15,len(paths)
frames=[Image.open(p).convert('RGB') for p in paths]
frames[0].save(root/'previews/Krokero_walk.gif',save_all=True,append_images=frames[1:],duration=67,loop=0,optimize=True)
sheet=Image.new('RGB',(1440,530),(22,35,30))
draw=ImageDraw.Draw(sheet)
for i,index in enumerate((0,5,10)):
    pic=ImageOps.contain(frames[index],(480,480))
    sheet.paste(pic,(i*480,30))
    draw.text((i*480+20,12),f'Walk: frame {1+index*2:02d} / 30 fps',fill=(233,218,171))
sheet.save(root/'previews/Krokero_walk_contact.png')
print('PREVIEWS_READY')
