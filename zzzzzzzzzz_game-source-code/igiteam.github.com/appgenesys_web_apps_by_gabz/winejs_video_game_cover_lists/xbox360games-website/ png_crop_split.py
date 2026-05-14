#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# crop_front_cover.py - Extract front cover by cropping half, then removing spine

import os
from PIL import Image

# Image dimensions (assuming 1596x1064 as you specified)
TOTAL_WIDTH = 1596
TOTAL_HEIGHT = 1064

# Spine width (estimated at 50px)
SPINE_WIDTH = 100

# Input and output folders
INPUT_FOLDER = "output_covers"
OUTPUT_FOLDER = "output_covers_png"

print("Extracting front covers from images...")
print("-" * 100)
print("Process: Crop right half, then remove {}px spine from left".format(SPINE_WIDTH))
print("-" * 100)

# Check if input folder exists
if not os.path.exists(INPUT_FOLDER):
    print("Error: Input folder '{}' not found!".format(INPUT_FOLDER))
    exit(1)

# Create output directory
if not os.path.exists(OUTPUT_FOLDER):
    os.makedirs(OUTPUT_FOLDER)

count = 0

for file in os.listdir(INPUT_FOLDER):
    if not file.lower().endswith(('.png', '.jpg', '.jpeg', '.webp', '.bmp')):
        continue
    
    input_path = os.path.join(INPUT_FOLDER, file)
    output_path = os.path.join(OUTPUT_FOLDER, file)
    
    print("Processing: {}".format(file))
    
    try:
        # Open image
        img = Image.open(input_path)
        width, height = img.size
        
        print("  Original dimensions: {}x{}".format(width, height))
        
        # Step 1: Crop the right half
        half_width = width // 2
        right_half = img.crop((half_width, 0, width, height))
        print("  Step 1 - Right half: {}x{}".format(half_width, height))
        
        # Step 2: Remove spine from left side of the right half
        # The spine is on the left edge of the right half (between back and front)
        spine_crop = SPINE_WIDTH // 2  # Crop half the spine width (25px)
        front_cover = right_half.crop((spine_crop, 0, half_width, height))
        print("  Step 2 - Removed {}px spine, final: {}x{}".format(spine_crop, front_cover.size[0], height))
        
        # Save preserving original format
        front_cover.save(output_path)
        count += 1
        
    except Exception as e:
        print("  Error: {}".format(e))

print("-" * 50)
print("Complete! Processed {} file(s)".format(count))
print("Output: {}/".format(OUTPUT_FOLDER))