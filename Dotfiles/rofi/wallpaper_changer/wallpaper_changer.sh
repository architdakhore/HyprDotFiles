#!/usr/bin/env bash

# --- CONFIGURATION ---
WALL_DIR="$HOME/Pictures/Wallpapers"
THEME="$HOME/.config/rofi/wallpaper_changer/wallpaper_changer.rasi"
CACHE_IMAGE="$HOME/Pictures/Wallpapers/current_wallpaper"

# --- GENERATE LIST WITH ICONS ---
list_images() {
    for f in "$WALL_DIR"/*.{jpg,png,jpeg,gif}; do
        if [ -f "$f" ]; then
            echo -en "$(basename "$f")\0icon\x1f$f\n"
        fi
    done
}

# --- LAUNCH ROFI ---
choice=$(list_images | rofi -dmenu -i -p "󰸉 Wallpapers" -theme "$THEME")

# --- APPLY AND PERSIST ---
if [ -n "$choice" ]; then
    FULL_PATH="$WALL_DIR/$choice"
    
    # 1. Update the symlink so the 'path' in your conf stays valid after reboot
    ln -sf "$FULL_PATH" "$CACHE_IMAGE"
    
    # 2. Apply to current session immediately
    hyprctl hyprpaper preload "$FULL_PATH"
    hyprctl hyprpaper wallpaper ",$FULL_PATH"
    
    # 3. Optional: Clean memory
    (sleep 1 && hyprctl hyprpaper unload all) &
    
    notify-send "Wallpaper" "Applied and saved: $choice"
fi