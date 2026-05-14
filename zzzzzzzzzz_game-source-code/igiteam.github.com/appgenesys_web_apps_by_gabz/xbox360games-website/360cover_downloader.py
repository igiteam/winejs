#!/usr/bin/env python3

import os
import re
import json
import urllib.request
import urllib.parse
from pathlib import Path
from typing import List, Dict, Optional
import time

def parse_games_list_js(file_path: str) -> List[Dict]:
    """
    Parse games_list.js file and extract game information including cover URLs
    """
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Extract the array content between the brackets
    # Find games_list = [ ... ];
    match = re.search(r'var\s+games_list\s*=\s*(\[[\s\S]*?\])\s*;', content)
    if not match:
        raise ValueError("Could not find games_list array in file")
    
    array_content = match.group(1)
    
    # Parse using regex to extract each object
    games = []
    
    # Pattern to match each object
    # This pattern handles nested structures by matching balanced braces
    object_pattern = r'\{\s*([^}]*(?:\{[^}]*\}[^}]*)*)\s*\}'
    
    objects = re.findall(object_pattern, array_content, re.DOTALL)
    
    for obj_str in objects:
        game = {}
        
        # Extract name
        name_match = re.search(r'name:\s*"([^"]*)"', obj_str)
        if name_match:
            game['name'] = name_match.group(1)
        
        # Extract href
        href_match = re.search(r'href:\s*"([^"]*)"', obj_str)
        if href_match:
            game['href'] = href_match.group(1)
        
        # Extract size
        size_match = re.search(r'size:\s*([\d.]+)', obj_str)
        if size_match:
            game['size'] = float(size_match.group(1))
        
        # Extract cover
        cover_match = re.search(r'cover:\s*"([^"]*)"', obj_str)
        if cover_match:
            game['cover'] = cover_match.group(1)
        
        if game.get('name') and game.get('cover'):
            games.append(game)
    
    return games

def get_filename_from_url(url: str) -> str:
    """
    Extract filename from URL
    """
    # Parse URL and get the last part after the last slash
    parsed = urllib.parse.urlparse(url)
    path = parsed.path
    filename = os.path.basename(path)
    
    # Decode URL-encoded characters
    filename = urllib.parse.unquote(filename)
    
    return filename

def download_image(url: str, output_path: str, max_retries: int = 3) -> bool:
    """
    Download an image from URL to output_path
    """
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    }
    
    for attempt in range(max_retries):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=30) as response:
                with open(output_path, 'wb') as f:
                    f.write(response.read())
            return True
        except Exception as e:
            print(f"  Attempt {attempt + 1} failed: {e}")
            if attempt < max_retries - 1:
                time.sleep(2)
    
    return False

def main():
    # Configuration
    input_file = "games_list.js"
    output_dir = Path("output_covers")
    
    # Create output directory
    output_dir.mkdir(exist_ok=True)
    print(f"✓ Created output directory: {output_dir}")
    
    # Check if input file exists
    if not Path(input_file).exists():
        print(f"❌ Error: {input_file} not found!")
        print("Make sure the file exists in the current directory")
        return
    
    # Parse games_list.js
    print(f"📖 Parsing {input_file}...")
    try:
        games = parse_games_list_js(input_file)
        print(f"✓ Found {len(games)} games with cover images")
    except Exception as e:
        print(f"❌ Error parsing file: {e}")
        return
    
    # Download images
    downloaded = 0
    skipped = 0
    failed = []
    
    print("\n📥 Downloading cover images...")
    print("-" * 50)
    
    for idx, game in enumerate(games, 1):
        cover_url = game['cover']
        filename = get_filename_from_url(cover_url)
        output_path = output_dir / filename
        
        # Check if file already exists
        if output_path.exists():
            print(f"[{idx}/{len(games)}] ⏭️  Skipping (exists): {filename}")
            skipped += 1
            continue
        
        print(f"[{idx}/{len(games)}] 📥 Downloading: {filename}")
        
        # Download the image
        if download_image(cover_url, str(output_path)):
            print(f"  ✓ Saved to: {output_path}")
            downloaded += 1
        else:
            print(f"  ❌ Failed to download: {filename}")
            failed.append({
                'url': cover_url,
                'filename': filename,
                'game': game.get('name', 'Unknown')
            })
        
        # Small delay to avoid overwhelming the server
        time.sleep(0.5)
    
    # Print summary
    print("\n" + "=" * 50)
    print("📊 DOWNLOAD SUMMARY")
    print("=" * 50)
    print(f"✅ Successfully downloaded: {downloaded}")
    print(f"⏭️  Skipped (already exist): {skipped}")
    print(f"❌ Failed: {len(failed)}")
    
    if failed:
        print("\n❌ Failed downloads:")
        for item in failed:
            print(f"  - {item['filename']}")
            print(f"    URL: {item['url']}")
            print(f"    Game: {item['game']}")
    
    print(f"\n📁 All images saved to: {output_dir.absolute()}")

if __name__ == "__main__":
    main()