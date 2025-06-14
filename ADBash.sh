#!/bin/bash

VERSION="2.4"
MAX_DEVICES=300
SESSION_ID=$(uuidgen | cut -d'-' -f1)
LOG_FILE="adbash_$SESSION_ID.log"
DEVICES_DB="devices.db"
SCREENSHOT_DIR="screenshots"
UPLOAD_DIR="uploads"
EXTRACTED_APK_DIR="extracted_apks"

mkdir -p "$SCREENSHOT_DIR"
mkdir -p "$UPLOAD_DIR"
mkdir -p "$EXTRACTED_APK_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

declare -A CONNECTED_DEVICES
DEVICE_COUNTER=0
CURRENT_DEVICE=""

dev_extract_apk() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    local package=${input[1]}
    if [ -z "$package" ]; then
        echo -e "${RED}Usage: extractapk [package_name]${NC}"
        echo -e "${YELLOW}Example: extractapk com.whatsapp${NC}"
        echo -e "\n${CYAN}Available packages:${NC}"
        adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell pm list packages | cut -d':' -f2 | sort
        return
    fi
    
    echo -e "${CYAN}Extracting APK for package '$package' from device $CURRENT_DEVICE...${NC}"
    
    apk_path=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell pm path "$package" | cut -d':' -f2 | tr -d '\r')
    
    if [ -z "$apk_path" ]; then
        echo -e "${RED}Could not find APK path for package $package${NC}"
        return
    fi
    
    mkdir -p "$EXTRACTED_APK_DIR"
    
    local output_file="$EXTRACTED_APK_DIR/${package}_$(date +"%Y%m%d_%H%M%S").apk"
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} pull "$apk_path" "$output_file" >/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}APK extracted successfully to: $output_file${NC}"
    else
        echo -e "${RED}Failed to extract APK${NC}"
    fi
}

dev_wpa_supplicant() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    echo -e "${CYAN}Attempting to get wpa_supplicant.conf from device $CURRENT_DEVICE...${NC}"
    echo -e "${YELLOW}Note: This requires root access${NC}"
    
    root_status=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell "su -c 'echo OK' 2>&1")
    if [[ "$root_status" != *"OK"* ]]; then
        echo -e "${RED}Device is not rooted!${NC}"
        return
    fi
    
    local output_file="wpa_supplicant_${CURRENT_DEVICE}_$(date +"%Y%m%d_%H%M%S").conf"
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell "su -c 'cat /data/misc/wifi/wpa_supplicant.conf'" > "$output_file" 2>/dev/null
    
    if [ -s "$output_file" ]; then
        echo -e "${GREEN}wpa_supplicant.conf saved to: $output_file${NC}"
    else
        rm -f "$output_file"
        echo -e "${RED}Failed to get wpa_supplicant.conf${NC}"
    fi
}

dev_current_activity() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    echo -e "${CYAN}Getting current activity for device $CURRENT_DEVICE...${NC}"
    
    activity=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell dumpsys window windows | grep -E 'mCurrentFocus|mFocusedApp' | tail -1 | awk -F'/' '{print $2}' | awk '{print $1}' | sed 's/}.*//')
    
    if [ -z "$activity" ]; then
        activity=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell dumpsys activity activities | grep -E 'ResumedActivity' | head -1 | awk '{print $4}' | cut -d'/' -f2)
    fi
    
    if [ -n "$activity" ]; then
        echo -e "${GREEN}Current Activity: $activity${NC}"
        package=$(echo "$activity" | awk -F'.' '{s=$1; for(i=2;i<NF;i++){s=s"."$i}} END{print s}')
        echo -e "${GREEN}Package: $package${NC}"
    else
        echo -e "${RED}Could not determine current activity${NC}"
    fi
}

dev_keycode() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    local keycode=${input[1]}
    if [ -z "$keycode" ]; then
        echo -e "${RED}Usage: keycode [keycode_number]${NC}"
        echo -e "${YELLOW}Common keycodes:${NC}"
        echo "3: Home, 4: Back, 5: Call, 6: End Call"
        echo "24: Volume Up, 25: Volume Down"
        echo "26: Power, 27: Camera"
        echo "66: Enter, 67: Backspace"
        echo "82: Menu, 164: Volume Mute"
        echo "220: Brightness Down, 221: Brightness Up"
        return
    fi
    
    if ! [[ "$keycode" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Keycode must be a number${NC}"
        return
    fi
    
    echo -e "${CYAN}Sending keycode $keycode to device $CURRENT_DEVICE...${NC}"
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell input keyevent "$keycode"
}

dev_remove_password() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    echo -e "${CYAN}Attempting to remove device password...${NC}"
    echo -e "${YELLOW}Note: This requires root access${NC}"
    
    root_status=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell "su -c 'echo OK' 2>&1")
    if [[ "$root_status" != *"OK"* ]]; then
        echo -e "${RED}Device is not rooted!${NC}"
        return
    fi
    
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell "su -c 'rm /data/system/gesture.key /data/system/password.key /data/system/locksettings.db*'"
    
    echo -e "${GREEN}Password files removed. Reboot the device for changes to take effect.${NC}"
    echo -e "${YELLOW}Would you like to reboot now? (y/n)${NC}"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} reboot
    fi
}

dev_send_file() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    local source=${input[1]}
    local destination=${input[2]:-/sdcard/}
    
    if [ -z "$source" ]; then
        echo -e "${RED}Usage: sendfile [source_path] [destination_path(optional)]${NC}"
        return
    fi
    
    if [ ! -e "$source" ]; then
        echo -e "${RED}Source file/folder does not exist: $source${NC}"
        return
    fi
    
    echo -e "${CYAN}Sending $source to device $CURRENT_DEVICE at $destination...${NC}"
    
    mkdir -p "$UPLOAD_DIR"
    
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} push "$source" "$destination" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}File/folder sent successfully!${NC}"
        log "Sent $source to $destination on device $CURRENT_DEVICE"
    else
        echo -e "${RED}Failed to send file/folder${NC}"
    fi
}

dev_realtime_log() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    echo -e "${CYAN}Starting real-time logcat for device $CURRENT_DEVICE...${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} logcat -v threadtime
}

dev_battery() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi

    echo -e "${CYAN}Getting battery info for device $CURRENT_DEVICE...${NC}"
    
    if ! adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell true 2>/dev/null; then
        echo -e "${RED}Device communication failed!${NC}"
        return
    fi

    battery_info=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell dumpsys battery 2>&1)
    
    if [[ "$battery_info" == *"not found"* ]] || [[ -z "$battery_info" ]]; then
        echo -e "${YELLOW}Standard battery info not available. Trying alternative methods...${NC}"
        
        alt_info=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell cat /sys/class/power_supply/*/capacity 2>/dev/null | head -1)
        
        if [ -n "$alt_info" ]; then
            echo -e "${GREEN}Battery Level: ${alt_info}%${NC}"
        else
            power_info=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell dumpsys power | grep -i 'mBatteryLevel=\|mPowered=')
            if [ -n "$power_info" ]; then
                level=$(echo "$power_info" | grep 'mBatteryLevel=' | cut -d= -f2)
                powered=$(echo "$power_info" | grep 'mPowered=' | cut -d= -f2)
                echo -e "${GREEN}Battery Level: ${level}%${NC}"
                echo -e "${GREEN}Charging Status: $([ "$powered" = "true" ] && echo "Charging" || echo "Discharging")${NC}"
            else
                echo -e "${RED}Could not retrieve battery information${NC}"
            fi
        fi
        return
    fi

    echo "$battery_info" | grep -E 'level|status|health|temperature|voltage' | while read -r line; do
        key=$(echo "$line" | awk -F: '{print $1}' | tr -d '[:space:]')
        value=$(echo "$line" | awk -F: '{print $2}' | tr -d '[:space:]')

        case $key in
            level) echo -e "${GREEN}Battery Level: ${value}%${NC}" ;;
            status)
                case $value in
                    1) status="Unknown" ;;
                    2) status="Charging" ;;
                    3) status="Discharging" ;;
                    4) status="Not charging" ;;
                    5) status="Full" ;;
                    *) status="N/A" ;;
                esac
                echo -e "${GREEN}Charging Status: $status${NC}"
                ;;
            health)
                case $value in
                    1) health="Unknown" ;;
                    2) health="Good" ;;
                    3) health="Overheat" ;;
                    4) health="Dead" ;;
                    5) health="Over voltage" ;;
                    6) health="Unspecified failure" ;;
                    7) health="Cold" ;;
                    *) health="N/A" ;;
                esac
                echo -e "${GREEN}Health: $health${NC}"
                ;;
            temperature)
                temp_c=$(echo "scale=1; $value / 10" | bc)
                temp_f=$(echo "scale=1; $temp_c * 9/5 + 32" | bc)
                echo -e "${GREEN}Temperature: ${temp_c}°C (${temp_f}°F)${NC}"
                ;;
            voltage)
                voltage_v=$(echo "scale=3; $value / 1000" | bc)
                echo -e "${GREEN}Voltage: ${voltage_v}V${NC}"
                ;;
        esac
    done
}

dev_netstat() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    echo -e "${CYAN}Network connections for device $CURRENT_DEVICE:${NC}"
    echo -e "${YELLOW}Note: Requires root access for complete information${NC}"
    
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell "netstat -tunap || netstat -tun || netstat -tuln" 2>/dev/null | awk '
    BEGIN {
        printf "%-20s %-20s %-10s %-10s %-15s\n", "Local Address", "Foreign Address", "State", "Proto", "PID/Program"
        printf "--------------------------------------------------------------------------------\n"
    }
    /^tcp|^udp/ {
        split($4, local, ":")
        split($5, foreign, ":")
        proto = $1
        state = ($1 == "tcp") ? $6 : "-"
        pid_prog = ($NF ~ /\//) ? $NF : "-"
        
        local_ip = local[1]
        foreign_ip = foreign[1]
        
        printf "%-20s %-20s %-10s %-10s %-15s\n", local_ip ":" local[2], foreign_ip ":" foreign[2], state, proto, pid_prog
    }'
}

dev_root() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    echo -e "${CYAN}Attempting to root device $CURRENT_DEVICE...${NC}"
    
    root_status=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell "su -c 'echo OK' 2>&1")
    if [[ "$root_status" == *"OK"* ]]; then
        echo -e "${GREEN}Device is already rooted!${NC}"
        return
    fi
    
    echo -e "${YELLOW}Trying common root methods...${NC}"
    
    echo -e "${CYAN}Attempting 'adb root'...${NC}"
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} root >/dev/null 2>&1
    sleep 2
    
    root_status=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell "su -c 'echo OK' 2>&1")
    if [[ "$root_status" == *"OK"* ]]; then
        echo -e "${GREEN}Success! Device rooted via 'adb root'${NC}"
        return
    fi
    
    echo -e "${CYAN}Attempting to push SuperSU...${NC}"
    echo -e "${YELLOW}Would you like to attempt this? (y/n)${NC}"
    read -r answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo -e "${RED}This feature requires device-specific implementation.${NC}"
    else
        echo -e "${YELLOW}Root attempt cancelled.${NC}"
    fi
}

dev_show_ip() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    echo -e "${CYAN}Network information for device $CURRENT_DEVICE:${NC}"
    
    wifi_ip=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$wifi_ip" ]; then
        echo -e "${GREEN}WiFi IP: $wifi_ip${NC}"
    else
        echo -e "${YELLOW}No WiFi connection${NC}"
    fi
    
    cell_ip=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell ip addr show rmnet0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    if [ -n "$cell_ip" ]; then
        echo -e "${GREEN}Cellular IP: $cell_ip${NC}"
    else
        echo -e "${YELLOW}No cellular data connection${NC}"
    fi
    
    echo -e "${CYAN}Attempting to get public IP...${NC}"
    public_ip=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell "curl -s ifconfig.me || wget -qO- ifconfig.me" 2>/dev/null)
    if [ -n "$public_ip" ]; then
        echo -e "${GREEN}Public IP: $public_ip${NC}"
        
        echo -e "${CYAN}Getting geolocation info...${NC}"
        location_info=$(curl -s "http://ip-api.com/json/$public_ip")
        echo -e "${GREEN}Country: $(echo "$location_info" | jq -r '.country')${NC}"
        echo -e "${GREEN}Region: $(echo "$location_info" | jq -r '.regionName')${NC}"
        echo -e "${GREEN}City: $(echo "$location_info" | jq -r '.city')${NC}"
        echo -e "${GREEN}ISP: $(echo "$location_info" | jq -r '.isp')${NC}"
    else
        echo -e "${YELLOW}Could not determine public IP${NC}"
    fi
}

dev_wifi() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    local action=$1
    
    case $action in
        on)
            echo -e "${CYAN}Enabling WiFi on device $CURRENT_DEVICE...${NC}"
            adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell svc wifi enable
            ;;
        off)
            echo -e "${CYAN}Disabling WiFi on device $CURRENT_DEVICE...${NC}"
            adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell svc wifi disable
            ;;
        scan)
            echo -e "${CYAN}Scanning WiFi networks...${NC}"
            adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell cmd wifi list-networks | while read -r line; do
                echo -e "${GREEN}$line${NC}"
            done
            ;;
        status)
            echo -e "${CYAN}WiFi status for device $CURRENT_DEVICE:${NC}"
            wifi_status=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell dumpsys wifi | grep "Wi-Fi is" | cut -d' ' -f3-)
            echo -e "${GREEN}$wifi_status${NC}"
            
            current_network=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell dumpsys wifi | grep "Current network" -A 5)
            echo -e "${GREEN}$current_network${NC}"
            ;;
        *)
            echo -e "${RED}Usage: wifi [on|off|scan|status]${NC}"
            ;;
    esac
}

dev_install() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    local apk_path=$1
    
    if [ -z "$apk_path" ]; then
        echo -e "${RED}Please specify APK file path${NC}"
        return
    fi
    
    if [ ! -f "$apk_path" ]; then
        echo -e "${RED}File not found: $apk_path${NC}"
        return
    fi
    
    echo -e "${CYAN}Installing $apk_path on device $CURRENT_DEVICE...${NC}"
    
    output=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} install -r "$apk_path" 2>&1)
    
    if [[ $output == *"Success"* ]]; then
        echo -e "${GREEN}Installation successful!${NC}"
    else
        echo -e "${RED}Regular install failed. Trying alternative methods...${NC}"
        
        temp_path="/data/local/tmp/$(basename "$apk_path")"
        adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} push "$apk_path" "$temp_path" >/dev/null
        output=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell pm install -r "$temp_path" 2>&1)
        
        if [[ $output == *"Success"* ]]; then
            echo -e "${GREEN}Installation successful via temp push!${NC}"
        else
            echo -e "${RED}Installation failed:${NC}"
            echo -e "${YELLOW}$output${NC}"
            
            if [[ $output == *"INSTALL_PARSE_FAILED_NO_CERTIFICATES"* ]] || [[ $output == *"INSTALL_FAILED_UPDATE_INCOMPATIBLE"* ]]; then
                echo -e "${YELLOW}Attempting to install with --unsigned flag...${NC}"
                output=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} install -r --unsigned "$apk_path" 2>&1)
                
                if [[ $output == *"Success"* ]]; then
                    echo -e "${GREEN}Installation successful with --unsigned flag!${NC}"
                else
                    echo -e "${RED}Still failed:${NC}"
                    echo -e "${YELLOW}$output${NC}"
                fi
            fi
        fi
    fi
}

dev_uninstall() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    local package=$1
    
    if [ -z "$package" ]; then
        echo -e "${RED}Please specify package name${NC}"
        return
    fi
    
    echo -e "${CYAN}Uninstalling $package from device $CURRENT_DEVICE...${NC}"
    
    output=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} uninstall "$package" 2>&1)
    
    if [[ $output == *"Success"* ]]; then
        echo -e "${GREEN}Uninstall successful!${NC}"
    else
        echo -e "${RED}Normal uninstall failed. Trying with --user 0...${NC}"
        output=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell pm uninstall --user 0 "$package" 2>&1)
        
        if [[ $output == *"Success"* ]]; then
            echo -e "${GREEN}Uninstall successful with --user 0!${NC}"
        else
            echo -e "${RED}Uninstall failed:${NC}"
            echo -e "${YELLOW}$output${NC}"
            
            if [[ $output == *"DELETE_FAILED_DEVICE_POLICY_MANAGER"* ]]; then
                echo -e "${YELLOW}This package is protected by device policy. Root may be required.${NC}"
            fi
        fi
    fi
}

dev_screenshot() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local filename="$SCREENSHOT_DIR/screenshot_${CURRENT_DEVICE}_${timestamp}.png"
    
    echo -e "${CYAN}Capturing screenshot from device $CURRENT_DEVICE...${NC}"
    
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell screencap -p /sdcard/screenshot.png >/dev/null 2>&1
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} pull /sdcard/screenshot.png "$filename" >/dev/null 2>&1
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell rm /sdcard/screenshot.png >/dev/null 2>&1
    
    if [ -f "$filename" ]; then
        echo -e "${GREEN}Screenshot saved to $filename${NC}"
        
        if command -v xdg-open >/dev/null; then
            echo -e "${CYAN}Opening screenshot...${NC}"
            xdg-open "$filename" >/dev/null 2>&1 &
        fi
    else
        echo -e "${RED}Failed to capture screenshot${NC}"
        
        local temp_video="$SCREENSHOT_DIR/temp.mp4"
        adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell screenrecord --time-limit 1 /sdcard/screenrecord.mp4 >/dev/null 2>&1
        adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} pull /sdcard/screenrecord.mp4 "$temp_video" >/dev/null 2>&1
        adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell rm /sdcard/screenrecord.mp4 >/dev/null 2>&1
        
        if [ -f "$temp_video" ]; then
            ffmpeg -i "$temp_video" -vframes 1 "$filename" >/dev/null 2>&1
            rm "$temp_video"
            
            if [ -f "$filename" ]; then
                echo -e "${GREEN}Screenshot extracted from video to $filename${NC}"
            else
                echo -e "${RED}Failed to extract frame from video${NC}"
            fi
        else
            echo -e "${RED}All screenshot methods failed${NC}"
        fi
    fi
}

dev_upload() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    local source=$1
    local destination=$2
    
    if [ -z "$source" ]; then
        echo -e "${RED}Please specify source file${NC}"
        return
    fi
    
    if [ -z "$destination" ]; then
        destination="/sdcard/"
    fi
    
    echo -e "${CYAN}Uploading $source to device $CURRENT_DEVICE at $destination...${NC}"
    
    if [ ! -f "$source" ] && [ ! -d "$source" ]; then
        echo -e "${RED}Source file/directory not found: $source${NC}"
        return
    fi
    
    mkdir -p "$UPLOAD_DIR"
    
    local upload_path="$UPLOAD_DIR/$(basename "$source")"
    cp -r "$source" "$upload_path" 2>/dev/null
    
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} push "$source" "$destination" >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Upload successful!${NC}"
        log "Uploaded $source to $destination on device $CURRENT_DEVICE"
    else
        echo -e "${RED}Upload failed${NC}"
    fi
}

dev_sysinfo() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    echo -e "${CYAN}Getting system information for device $CURRENT_DEVICE...${NC}"
    
    echo -e "${YELLOW}=== Basic Information ===${NC}"
    manufacturer=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell getprop ro.product.manufacturer)
    model=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell getprop ro.product.model)
    device=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell getprop ro.product.device)
    android_version=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell getprop ro.build.version.release)
    build_number=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell getprop ro.build.id)
    security_patch=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell getprop ro.build.version.security_patch)
    
    echo -e "${GREEN}Manufacturer: $manufacturer${NC}"
    echo -e "${GREEN}Model: $model${NC}"
    echo -e "${GREEN}Device: $device${NC}"
    echo -e "${GREEN}Android Version: $android_version${NC}"
    echo -e "${GREEN}Build Number: $build_number${NC}"
    echo -e "${GREEN}Security Patch: $security_patch${NC}"
    
    echo -e "\n${YELLOW}=== Hardware Information ===${NC}"
    cpu_info=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d':' -f2)
    cpu_cores=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell cat /proc/cpuinfo | grep 'processor' | wc -l)
    mem_total=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell cat /proc/meminfo | grep MemTotal | awk '{print $2}')
    mem_total=$((mem_total / 1024))
    storage_total=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell df /data | tail -1 | awk '{print $2}')
    storage_total=$((storage_total / 1024))
    
    echo -e "${GREEN}CPU: $cpu_info${NC}"
    echo -e "${GREEN}CPU Cores: $cpu_cores${NC}"
    echo -e "${GREEN}Total RAM: ${mem_total}MB${NC}"
    echo -e "${GREEN}Total Storage: ${storage_total}MB${NC}"
    
    echo -e "\n${YELLOW}=== Memory Usage ===${NC}"
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell dumpsys meminfo | head -15
    
    echo -e "\n${YELLOW}=== Storage Usage ===${NC}"
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell df -h
    
    echo -e "\n${YELLOW}=== Battery Information ===${NC}"
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell dumpsys battery
    
    echo -e "\n${YELLOW}=== Network Information ===${NC}"
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell ifconfig
    adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell netcfg
    
    echo -e "\n${YELLOW}=== Installed Packages ===${NC}"
    package_count=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell pm list packages | wc -l)
    echo -e "${GREEN}Total installed packages: $package_count${NC}"
}

dev_openurl() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    local url=${input[1]}
    if [ -z "$url" ]; then
        echo -e "${RED}Usage: openurl [url]${NC}"
        return
    fi
    
    echo -e "${CYAN}Opening URL '$url' on device $CURRENT_DEVICE...${NC}"
    
    output=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell am start -a android.intent.action.VIEW -d "$url" 2>&1)
    
    if [[ $output == *"Error"* ]]; then
        echo -e "${RED}Failed to open URL:${NC}"
        echo -e "${YELLOW}$output${NC}"
        
        adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell monkey -p com.android.browser -c android.intent.category.LAUNCHER 1
        sleep 2
        adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell input keyevent KEYCODE_TAB
        adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell input text "$url"
        adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell input keyevent KEYCODE_ENTER
    else
        echo -e "${GREEN}URL opened successfully!${NC}"
    fi
}

dev_runapp() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    local package=${input[1]}
    if [ -z "$package" ]; then
        echo -e "${RED}Usage: runapp [package_name]${NC}"
        echo -e "\n${CYAN}Available packages:${NC}"
        adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell pm list packages | cut -d':' -f2 | sort
        return
    fi
    
    echo -e "${CYAN}Launching app with package '$package' on device $CURRENT_DEVICE...${NC}"
    
    activity=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell cmd package resolve-activity --brief "$package" | tail -1)
    
    if [ -z "$activity" ]; then
        echo -e "${RED}Could not find main activity for package $package${NC}"
        return
    fi
    
    output=$(adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell am start -n "$activity" 2>&1)
    
    if [[ $output == *"Error"* ]]; then
        echo -e "${RED}Failed to launch app:${NC}"
        echo -e "${YELLOW}$output${NC}"
    else
        echo -e "${GREEN}App launched successfully!${NC}"
    fi
}

dev_keyboard() {
    if [ -z "$CURRENT_DEVICE" ]; then
        echo -e "${RED}No device selected! Use 'device [ID]' first.${NC}"
        return
    fi
    
    local action=${input[1]}
    
    case $action in
        text)
            local text="${input[@]:2}"
            if [ -z "$text" ]; then
                echo -e "${RED}Usage: keyboard text [text to input]${NC}"
                return
            fi
            echo -e "${CYAN}Sending text input to device $CURRENT_DEVICE...${NC}"
            adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell input text "$text"
            ;;
        tap)
            local x=${input[2]}
            local y=${input[3]}
            if [ -z "$x" ] || [ -z "$y" ]; then
                echo -e "${RED}Usage: keyboard tap [x] [y]${NC}"
                return
            fi
            echo -e "${CYAN}Sending tap at ($x, $y) to device $CURRENT_DEVICE...${NC}"
            adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell input tap $x $y
            ;;
        keyevent)
            local keycode=${input[2]}
            if [ -z "$keycode" ]; then
                echo -e "${RED}Usage: keyboard keyevent [keycode]${NC}"
                echo "3: Home, 4: Back, 5: Call, 6: End Call"
                echo "24: Volume Up, 25: Volume Down"
                echo "26: Power, 27: Camera"
                echo "66: Enter, 67: Backspace"
                echo "82: Menu"
                return
            fi
            echo -e "${CYAN}Sending keyevent $keycode to device $CURRENT_DEVICE...${NC}"
            adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell input keyevent $keycode
            ;;
        swipe)
            local x1=${input[2]}
            local y1=${input[3]}
            local x2=${input[4]}
            local y2=${input[5]}
            local duration=${input[6]:-100}
            if [ -z "$x1" ] || [ -z "$y1" ] || [ -z "$x2" ] || [ -z "$y2" ]; then
                echo -e "${RED}Usage: keyboard swipe [x1] [y1] [x2] [y2] [duration(ms)]${NC}"
                return
            fi
            echo -e "${CYAN}Sending swipe from ($x1, $y1) to ($x2, $y2) to device $CURRENT_DEVICE...${NC}"
            adb -s ${CONNECTED_DEVICES[$CURRENT_DEVICE]} shell input swipe $x1 $y1 $x2 $y2 $duration
            ;;
        *)
            echo -e "${RED}Usage: keyboard [command]${NC}"
            echo "text [text] - Input text"
            echo "tap [x] [y] - Tap at coordinates"
            echo "keyevent [code] - Send key event"
            echo "swipe [x1] [y1] [x2] [y2] [duration] - Swipe between coordinates"
            ;;
    esac
}

init() {
    clear
    echo -e "${CYAN}"
    echo "   █████╗ ██████╗ ██████╗  █████╗ ███████╗██╗  ██╗"
    echo "  ██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝██║  ██║"
    echo "  ███████║██║  ██║██████╔╝███████║███████╗███████║"
    echo "  ██╔══██║██║  ██║██╔══██╗██╔══██║╚════██║██╔══██║"
    echo "  ██║  ██║██████╔╝██████╔╝██║  ██║███████║██║  ██║"
    echo "  ╚═╝  ╚═╝╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝"
    echo -e "${NC}"
    echo -e "  ${YELLOW}ADBash Framework v$VERSION - Interactive ADB Shell${NC}"
    echo -e "  ${YELLOW}Type 'help' for available commands${NC}"
    echo ""
    
    touch $DEVICES_DB
    log "Session started (ID: $SESSION_ID)"
    
    if ! pgrep -x "adb" > /dev/null; then
        adb start-server > /dev/null 2>&1
    fi
}

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

connect_device() {
    local target=$1
    log "Attempting to connect to $target"
    
    if [[ $target =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        target="$target:5555"
    fi
    
    if [[ ! $target =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$ ]]; then
        echo -e "${RED}Invalid format! Use IP or IP:PORT${NC}"
        return 1
    fi
    
    for id in "${!CONNECTED_DEVICES[@]}"; do
        if [ "${CONNECTED_DEVICES[$id]}" == "$target" ]; then
            echo -e "${YELLOW}Device already connected as ID $id${NC}"
            return 0
        fi
    done

    if [ $DEVICE_COUNTER -ge $MAX_DEVICES ]; then
        echo -e "${RED}Maximum device limit ($MAX_DEVICES) reached${NC}"
        return 1
    fi

    adb disconnect $target > /dev/null 2>&1
    
    echo -e "${YELLOW}Attempting connection to $target...${NC}"
    output=$(timeout 5 adb connect $target 2>&1)
    status=$?
    
    if [ $status -eq 0 ] && [[ $output == *"connected to"* ]]; then
        DEVICE_COUNTER=$((DEVICE_COUNTER+1))
        CONNECTED_DEVICES[$DEVICE_COUNTER]=$target
        echo -e "${GREEN}Success! Connected to $target as ID $DEVICE_COUNTER${NC}"
        log "Connected to $target (ID: $DEVICE_COUNTER)"
        echo "$DEVICE_COUNTER|$target|$(date +'%Y-%m-%d %H:%M:%S')" >> $DEVICES_DB
        return 0
    else
        echo -e "${RED}Failed to connect to $target${NC}"
        log "Connection failed to $target - $output"
        return 1
    fi
}

list_connections() {
    if [ ${#CONNECTED_DEVICES[@]} -eq 0 ]; then
        echo -e "${YELLOW}No active connections${NC}"
        return
    fi

    echo -e "${CYAN}Active ADB Connections ($DEVICE_COUNTER/$MAX_DEVICES):${NC}"
    echo -e "${GREEN}ID\tIP:Port${NC}"
    for id in "${!CONNECTED_DEVICES[@]}"; do
        echo -e "$id\t${CONNECTED_DEVICES[$id]}"
    done
}

start_shell() {
    local device_id=$1
    local target=${CONNECTED_DEVICES[$device_id]}

    if [ -z "$target" ]; then
        echo -e "${RED}Invalid device ID${NC}"
        return
    fi

    echo -e "${GREEN}Starting ADB shell for Device $device_id ($target)${NC}"
    adb -s $target shell
}

set_current_device() {
    local device_id=$1
    if [ -z "${CONNECTED_DEVICES[$device_id]}" ]; then
        echo -e "${RED}Invalid device ID${NC}"
        return 1
    fi
    
    CURRENT_DEVICE=$device_id
    echo -e "${GREEN}Current device set to ID $device_id (${CONNECTED_DEVICES[$device_id]})${NC}"
    return 0
}

show_help() {
    echo -e "${CYAN}ADBash Framework Commands:${NC}"
    echo -e "  ${GREEN}connect [ip|ip:port]${NC} - Connect to ADB device"
    echo -e "  ${GREEN}connections${NC} - List all active connections"
    echo -e "  ${GREEN}shell [ID]${NC} - Start interactive shell for device"
    echo -e "  ${GREEN}disconnect [ID]${NC} - Disconnect from device"
    echo -e "  ${GREEN}device [ID]${NC} - Set current device for operations"
    echo -e "  ${GREEN}clear${NC} - Clear screen"
    echo -e "  ${GREEN}exit${NC} - Quit ADBash"
    echo ""
    echo -e "${CYAN}Device Operations (requires current device):${NC}"
    echo -e "  ${GREEN}battery${NC} - Show battery information"
    echo -e "  ${GREEN}netstat${NC} - Show network connections"
    echo -e "  ${GREEN}root${NC} - Attempt to root device"
    echo -e "  ${GREEN}show_ip${NC} - Show device IP addresses"
    echo -e "  ${GREEN}wifi [on|off|scan|status]${NC} - Control WiFi"
    echo -e "  ${GREEN}install [apk_path]${NC} - Install APK"
    echo -e "  ${GREEN}uninstall [package]${NC} - Uninstall app"
    echo -e "  ${GREEN}screenshot${NC} - Capture screenshot"
    echo -e "  ${GREEN}upload [local] [remote]${NC} - Upload file to device"
    echo -e "  ${GREEN}sysinfo${NC} - Show detailed system information"
    echo -e "  ${GREEN}openurl [url]${NC} - Open URL in device browser"
    echo -e "  ${GREEN}runapp [package]${NC} - Launch application by package name"
    echo -e "  ${GREEN}keyboard [command]${NC} - Control device keyboard/input"
    echo -e "  ${GREEN}extractapk [package]${NC} - Extract APK from installed app"
    echo -e "  ${GREEN}wpasupplicant${NC} - Get wpa_supplicant.conf (root)"
    echo -e "  ${GREEN}currentactivity${NC} - Show current foreground activity"
    echo -e "  ${GREEN}keycode [number]${NC} - Send keycode to device"
    echo -e "  ${GREEN}removepassword${NC} - Remove device password (root)"
    echo -e "  ${GREEN}sendfile [source] [dest]${NC} - Send file/folder to device"
    echo -e "  ${GREEN}realtimelog${NC} - Show real-time device logs"
    echo -e "  ${GREEN}adb [command]${NC} - Run raw ADB command"
}

init

while true; do
    read -e -p "ADBash> " -a input

    if [ -z "${input[0]}" ]; then
        continue
    fi

    cmd=${input[0]}

    case $cmd in
        connect)
            target=${input[1]}
            if [ -z "$target" ]; then
                echo -e "${RED}Usage: connect [ip|ip:port]${NC}"
            else
                connect_device $target
            fi
            ;;
        connections)
            list_connections
            ;;
        shell)
            device_id=${input[1]}
            if [[ $device_id =~ ^[0-9]+$ ]]; then
                start_shell $device_id
            else
                echo -e "${RED}Usage: shell [ID]${NC}"
            fi
            ;;
        disconnect)
            device_id=${input[1]}
            if [[ $device_id =~ ^[0-9]+$ ]]; then
                target=${CONNECTED_DEVICES[$device_id]}
                if [ -z "$target" ]; then
                    echo -e "${RED}Invalid device ID${NC}"
                else
                    adb disconnect $target > /dev/null
                    unset CONNECTED_DEVICES[$device_id]
                    echo -e "${GREEN}Disconnected device $device_id ($target)${NC}"
                    log "Disconnected device $device_id ($target)"
                    
                    if [ "$CURRENT_DEVICE" == "$device_id" ]; then
                        CURRENT_DEVICE=""
                    fi
                fi
            else
                echo -e "${RED}Usage: disconnect [ID]${NC}"
            fi
            ;;
        device)
            device_id=${input[1]}
            if [[ $device_id =~ ^[0-9]+$ ]]; then
                set_current_device $device_id
            else
                echo -e "${RED}Usage: device [ID]${NC}"
            fi
            ;;
        clear)
            clear
            ;;
        help)
            show_help
            ;;
        exit)
            echo -e "${CYAN}Closing all connections...${NC}"
            for target in "${CONNECTED_DEVICES[@]}"; do
                adb disconnect $target > /dev/null
            done
            echo -e "${GREEN}ADBash session ended.${NC}"
            exit 0
            ;;
        adb)
            adb_cmd="${input[@]:1}"
            adb $adb_cmd
            ;;
        battery)
            dev_battery
            ;;
        netstat)
            dev_netstat
            ;;
        root)
            dev_root
            ;;
        show_ip)
            dev_show_ip
            ;;
        wifi)
            dev_wifi "${input[1]}"
            ;;
        install)
            dev_install "${input[1]}"
            ;;
        uninstall)
            dev_uninstall "${input[1]}"
            ;;
        screenshot)
            dev_screenshot
            ;;
        upload)
            dev_upload "${input[1]}" "${input[2]}"
            ;;
        sysinfo)
            dev_sysinfo
            ;;
        openurl)
            dev_openurl
            ;;
        runapp)
            dev_runapp
            ;;
        keyboard)
            dev_keyboard
            ;;
        extractapk)
            dev_extract_apk
            ;;
        wpasupplicant)
            dev_wpa_supplicant
            ;;
        currentactivity)
            dev_current_activity
            ;;
        keycode)
            dev_keycode
            ;;
        removepassword)
            dev_remove_password
            ;;
        sendfile)
            dev_send_file
            ;;
        realtimelog)
            dev_realtime_log
            ;;
        *)
            echo -e "${RED}Unknown command. Type 'help' for available commands.${NC}"
            ;;
    esac
done
