#!/usr/bin/env python3
# crop_front_cover.py - Extract only the front cover (right side) from scanned Xbox 360 game cases

import os
from PIL import Image

# Image dimensions (assuming 1596x1064 as you specified)
TOTAL_WIDTH = 1596
TOTAL_HEIGHT = 1064

# Spine width (estimated at 50px)
SPINE_WIDTH = 50

# The image layout: [Back Cover] [Spine] [Front Cover]
# Width calculations
BACK_COVER_WIDTH = (TOTAL_WIDTH - SPINE_WIDTH) // 2
FRONT_COVER_WIDTH = TOTAL_WIDTH - BACK_COVER_WIDTH - SPINE_WIDTH

# Alternative: If you want to crop from right side directly
# Right side is the front cover
RIGHT_CROP_WIDTH = TOTAL_WIDTH // 2  # Half of total (798px)

print("\033[32mExtracting front covers from images...\033[0m")
print("-" * 50)

# Create output directory
os.makedirs("front_covers", exist_ok=True)

count = 0
for file in os.listdir('.'):
    if not file.lower().endswith(('.png', '.jpg', '.jpeg')):
        continue
    
    base_name = os.path.splitext(file)[0]
    print(f"\033[33mProcessing: {file}\033[0m")
    
    # Open image
    img = Image.open(file)
    width, height = img.size
    
    print(f"  Dimensions: {width}x{height}")
    
    # Method 1: Crop right half (for standard 1596x1064 images)
    # This assumes front cover is on the right side
    if width == TOTAL_WIDTH and height == TOTAL_HEIGHT:
        # Crop the right half (front cover)
        front_cover = img.crop((TOTAL_WIDTH - RIGHT_CROP_WIDTH, 0, TOTAL_WIDTH, TOTAL_HEIGHT))
        output_path = f"front_covers/{base_name}_front.png"
        front_cover.save(output_path)
        print(f"  \033[32m✓ Extracted front cover (right half)\033[0m")
    else:
        # Method 2: Calculate based on spine position for custom dimensions
        # This removes back cover + spine, keeps only front cover
        spine_pos = (width - SPINE_WIDTH) // 2  # Approximate spine position
        front_start = spine_pos + SPINE_WIDTH
        
        # Alternative: Remove 50px from middle and take right side
        # front_cover = img.crop((front_start, 0, width, height))
        
        # Simpler: Just crop the rightmost portion
        right_portion_width = width // 2
        front_cover = img.crop((width - right_portion_width, 0, width, height))
        output_path = f"front_covers/{base_name}_front.png"
        front_cover.save(output_path)
        print(f"  \033[32m✓ Extracted right portion ({right_portion_width}px)\033[0m")
    
    count += 1

print("-" * 50)
print(f"\033[32mComplete! Processed {count} file(s)\033[0m")
print(f"  📁 Front covers saved to: \033[33mfront_covers/\033[0m")
print("\n\033[36mNote:\033[0m The script extracts the right side/front cover from each image")