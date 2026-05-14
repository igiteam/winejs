#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# fix_covers.py - Fix cover paths and add cover_wide where missing

import re

input_file = "games_list.js"

# Read file
with open(input_file, 'r') as f:
    content = f.read()

# Create backup
with open("{}.backup".format(input_file), 'w') as f:
    f.write(content)
print("Backup created: {}.backup".format(input_file))

# Process each game object using regex to find complete objects
# Match pattern from { to } including all content
objects = re.findall(r'\{\s*[^{}]*\}(?=,?\s*(?:\{|$))', content, re.DOTALL)

new_objects = []
for obj in objects:
    # Check if cover is null or missing
    has_cover = 'cover:' in obj
    has_cover_wide = 'cover_wide:' in obj
    
    # Check if cover has a URL
    cover_match = re.search(r'cover:\s*"([^"]+)"', obj)
    cover_is_null = 'cover: null' in obj or 'cover:' in obj and not cover_match
    
    if cover_match and not has_cover_wide:
        # Get the cover URL and extract filename
        cover_url = cover_match.group(1)
        if cover_url.startswith('http'):
            # Extract filename from URL
            filename = cover_url.split('/')[-1]
            # Replace cover line
            obj = re.sub(
                r'cover:\s*"[^"]+"',
                'cover: "output_covers_png/{}"'.format(filename),
                obj
            )
            # Add cover_wide line before the closing brace (escape the braces)
            obj = re.sub(
                r'(\s*)\}',
                r'\1    cover_wide: "output_covers/' + filename + '",\n\1}',
                obj
            )
        else:
            # Already has local path, just add cover_wide
            filename = cover_url.split('/')[-1]
            obj = re.sub(
                r'(\s*)\}',
                r'\1    cover_wide: "output_covers/' + filename + '",\n\1}',
                obj
            )
    elif cover_is_null and not has_cover_wide:
        # Cover is null, add cover_wide as null too
        obj = re.sub(
            r'(\s*)\}',
            r'\1    cover_wide: null,\n\1}',
            obj
        )
    
    new_objects.append(obj)

# Reconstruct the file
new_content = 'var games_list = [\n  {}\n];'.format(',\n  '.join(new_objects))

# Write back
with open(input_file, 'w') as f:
    f.write(new_content)

print("Updated cover paths:")
print("  - cover: output_covers_png/ (cropped front covers)")
print("  - cover_wide: output_covers/ (original widescreen covers)")
print("  - Handles null values")
print("  - Preserves existing cover_wide fields")
print("")
print("Complete! Updated {}".format(input_file))