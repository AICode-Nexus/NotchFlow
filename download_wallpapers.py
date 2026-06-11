import os
import subprocess
import urllib.request
import time
import re

dest = "/Users/wangyang/图文/壁纸/NotchFlow精选4K"
os.makedirs(dest, exist_ok=True)

# Unsplash Source is down. Let's use a Pixabay or Pexels-like direct approach if possible,
# or just use images.unsplash.com if we find a way.
# Actually, unsplash.com/photos/random works (the webpage).
# But for automation without API key, let's try a different source or a fixed list of high-res categories.
# Let's try "https://commons.wikimedia.org" or just more specific search links.
# Another option: "https://picsum.photos/v2/list?limit=100" then filter by size.

def get_dims(path):
    try:
        out = subprocess.check_output(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path]).decode()
        w = int(re.search(r"pixelWidth: (\d+)", out).group(1))
        h = int(re.search(r"pixelHeight: (\d+)", out).group(1))
        return w, h
    except: return 0, 0

added = []
target_count = 30
min_w, min_h = 3840, 2160

# Try picsum.photos
try:
    import json
    url = "https://picsum.photos/v2/list?limit=100"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read().decode())
        for item in data:
            if len(added) >= target_count: break
            w_orig, h_orig = item['width'], item['height']
            if w_orig >= min_w and h_orig >= min_h:
                # Use the download URL but request specific size
                id = item['id']
                # Picsum allows custom sizing
                img_url = f"https://picsum.photos/id/{id}/{min_w}/{min_h}"
                filename = f"picsum_{id}.jpg"
                path = os.path.join(dest, filename)
                try:
                    urllib.request.urlretrieve(img_url, path)
                    w, h = get_dims(path)
                    if w >= min_w and h >= min_h:
                        added.append(f"{filename} ({w}x{h})")
                        print(f"Added: {filename}")
                    else:
                        os.remove(path)
                except:
                    if os.path.exists(path): os.remove(path)
except Exception as e:
    print(f"Picsum failed: {e}")

# If we still need more, try random Unsplash photos by ID sequence or known categories
# But Picsum should provide enough. Let's check results.

print(f"AddedCount: {len(added)}")
for a in added: print(f"File: {a}")
