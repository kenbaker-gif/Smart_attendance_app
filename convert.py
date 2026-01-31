import os
import sys

# --- STEP 1: IMPORT ---
try:
    # ✅ FOR MOVIEPY 1.0.3 (Your Version)
    from moviepy.editor import VideoFileClip, clips_array
except ImportError as e:
    print(f"❌ Import Error: {e}")
    print("👉 Debug: You have v1.0.3 installed, but the import failed.")
    sys.exit()

# --- STEP 2: FILE SETUP ---
mobile_video_path = r"Screenrecorder-2026-01-24-15-23-12-263.mp4"
laptop_video_path = r"VID_20260124_091715.3gp"

# Check if files exist
if not os.path.exists(mobile_video_path):
    print(f"❌ Cannot find file: {mobile_video_path}")
    sys.exit()
if not os.path.exists(laptop_video_path):
    print(f"❌ Cannot find file: {laptop_video_path}")
    sys.exit()

print("✅ Files found. Processing video... (This might take a minute)")

# --- STEP 3: PROCESSING ---
try:
    # Time settings (seconds to skip at start)
    mobile_start_skip = 0 
    laptop_start_skip = 0 

    # ✅ OLD SYNTAX (v1.0.3 uses .subclip, NOT .subclipped)
    clip1 = VideoFileClip(mobile_video_path).subclip(mobile_start_skip)
    clip2 = VideoFileClip(laptop_video_path).subclip(laptop_start_skip)

    # ✅ OLD SYNTAX (v1.0.3 uses .without_audio(), NOT .with_audio(None))
    clip2 = clip2.without_audio()

    # ✅ OLD SYNTAX (v1.0.3 uses .resize, NOT .resized)
    clip2 = clip2.resize(height=clip1.h)

    # Stack them side-by-side
    final_clip = clips_array([[clip1, clip2]])

    # Resize for LinkedIn (720p height)
    final_clip = final_clip.resize(height=720)

    # Write the file
    output_name = "linkedin_demo.mp4"
    final_clip.write_videofile(output_name, codec="libx264", audio_codec="aac")
    
    print(f"🎉 Done! Created {output_name}")

except Exception as e:
    print(f"❌ An error occurred: {e}")