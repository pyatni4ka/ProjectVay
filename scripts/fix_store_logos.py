import os
import json
import zlib
import struct

def create_valid_png(width, height):
    # PNG Signature
    png_sig = b'\x89PNG\r\n\x1a\n'
    
    # IHDR Chunk: Width, Height, BitDepth=8, ColorType=2 (Truecolor), Compression=0, Filter=0, Interlace=0
    ihdr_data = struct.pack('!IIBBBBB', width, height, 8, 2, 0, 0, 0)
    ihdr = struct.pack('!I4s', len(ihdr_data), b'IHDR') + ihdr_data + struct.pack('!I', zlib.crc32(b'IHDR' + ihdr_data))
    
    # IDAT Chunk
    # Rows of (Filter=0 + RGB pixels)
    raw_data = b''
    # Create a red square
    for _ in range(height):
        raw_data += b'\x00' + (b'\xFF\x00\x00' * width)
        
    compressed_data = zlib.compress(raw_data)
    idat = struct.pack('!I4s', len(compressed_data), b'IDAT') + compressed_data + struct.pack('!I', zlib.crc32(b'IDAT' + compressed_data))
    
    # IEND Chunk
    iend = struct.pack('!I4sI', 0, b'IEND', zlib.crc32(b'IEND'))
    
    return png_sig + ihdr + idat + iend

DEFAULT_CONTENTS_JSON = {
    "images": [
        {
            "idiom": "universal",
            "filename": "logo.png"
        }
    ],
    "info": {
        "author": "xcode",
        "version": 1
    }
}

def repair_assets(base_path):
    for entry in os.listdir(base_path):
        if not entry.startswith("store_") or not entry.endswith(".imageset"):
            continue
        
        dir_path = os.path.join(base_path, entry)
        if not os.path.isdir(dir_path):
            continue
        
        print(f"Repairing {entry}...")
        
        contents_json_path = os.path.join(dir_path, "Contents.json")
        logo_png_path = os.path.join(dir_path, "logo.png")
        
        # 1. Create Contents.json if missing
        if not os.path.exists(contents_json_path):
            with open(contents_json_path, 'w') as f:
                json.dump(DEFAULT_CONTENTS_JSON, f, indent=2)
            print(f"  Created Contents.json")
            
        # 2. Check/Create logo.png
        # We always overwrite if it's likely our broken placeholder, 
        # but to be safe, let's just ensure it exists.
        # Use a simple heuristic: if it's missing, generate it.
        # If it exists, we assume it's good unless we want to force-fix.
        # User said "logo.png is black screens", implying current ones are bad.
        # So I will overwrite if < 1KB (likely my bad placeholder).
        
        should_generate = True
        if os.path.exists(logo_png_path):
            size = os.path.getsize(logo_png_path)
            if size > 1000: # Assuming real logos are > 1KB
                should_generate = False
                print("  Skipping existing large logo.png")
            else:
                print("  Overwriting suspicious/small logo.png")
        
        if should_generate:
            with open(logo_png_path, 'wb') as f:
                f.write(create_valid_png(64, 64))
            print(f"  Generated valid 64x64 red logo.png")
        
        # 4. Normalize Contents.json
        try:
            with open(contents_json_path, 'r') as f:
                data = json.load(f)
        except:
            data = DEFAULT_CONTENTS_JSON

        data["images"] = [{"idiom": "universal", "filename": "logo.png"}]
        
        with open(contents_json_path, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"  Normalized Contents.json")

if __name__ == "__main__":
    assets_path = "ios/Assets.xcassets/StoreLogos"
    if os.path.exists(assets_path):
        repair_assets(assets_path)
    else:
        print(f"Path {assets_path} not found.")
