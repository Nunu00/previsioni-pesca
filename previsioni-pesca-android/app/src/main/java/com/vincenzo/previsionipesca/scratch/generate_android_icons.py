import os
from PIL import Image, ImageOps, ImageDraw

# Paths
icon_src_path = r"C:\Users\Vincenzo\.gemini\antigravity\brain\76ea45fa-d7cc-4d1a-975f-91a2cace00cf\previsioni_pesca_icon_1784542711448.jpg"
res_dir = r"c:\Antigravity\meteopesca\previsioni-pesca-android\app\src\main\res"

sizes = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192
}

def make_round_image(img):
    # Convert image to RGBA
    img = img.convert("RGBA")
    mask = Image.new('L', img.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0) + img.size, fill=255)
    output = ImageOps.fit(img, mask.size, centering=(0.5, 0.5))
    output.putalpha(mask)
    return output

if not os.path.exists(icon_src_path):
    print(f"Source icon not found at {icon_src_path}")
else:
    src_img = Image.open(icon_src_path)
    
    for folder_name, size in sizes.items():
        folder_path = os.path.join(res_dir, folder_name)
        os.makedirs(folder_path, exist_ok=True)
        
        # 1. Square Icon
        square_img = src_img.resize((size, size), Image.Resampling.LANCZOS)
        square_img.save(os.path.join(folder_path, "ic_launcher.png"), "PNG")
        
        # 2. Round Icon
        round_img = make_round_image(src_img).resize((size, size), Image.Resampling.LANCZOS)
        round_img.save(os.path.join(folder_path, "ic_launcher_round.png"), "PNG")
        
        print(f"Generated icons for {folder_name} ({size}x{size})")

print("Android launcher icons generation complete!")
