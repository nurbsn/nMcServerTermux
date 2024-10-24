#!/bin/bash

pkg upgrade -y &>/dev/null && echo "Updated packages" || echo "Error updating packages"

if ! command -v curl &>/dev/null; then
    echo "curl is not installed. Installing curl..."
    pkg install curl -y &>/dev/null
fi

if [ ! -d "$HOME/storage/shared" ]; then
    echo "Requesting storage permissions..."
    termux-setup-storage
    if [ $? -ne 0 ]; then
        echo "Failed to set up storage. Exiting."
        exit 1
    fi
    echo "Storage permissions granted."
fi

read -p "Enter the folder name for your Minecraft server: " folder_name
server_dir="$HOME/storage/shared/$folder_name"
mkdir -p "$server_dir"
cd "$server_dir" || { echo "Failed to access server folder"; exit 1; }

java_ver=$(java -version 2>&1 | awk -F[\"\.] -v OFS=. 'NR==1{print $2}')

if [ "$java_ver" = 17 ]; then
    pkg remove openjdk-17 -y &>/dev/null && echo "Removed Java 17" || echo "Error removing Java 17"
fi

pkg install openjdk-21 -y &>/dev/null && echo "Installed Java 21" || echo "Error installing Java 21"
pkg autoclean && pkg clean -y &>/dev/null && echo "Cleaned packages" || echo "Error cleaning packages"

java_ver=$(java -version 2>&1 | awk -F[\"\.] -v OFS=. 'NR==1{print $2}')

if [ "$java_ver" != 21 ]; then
    echo "Java 21 is not installed or is not working"
    exit 1
fi

read -p "Enter the amount of RAM to allocate (in GB, e.g., 1 for 1GB): " ram
if ! [[ "$ram" =~ ^[0-9]+$ ]]; then
    echo "Invalid input. Exiting."
    exit 1
fi

echo "Select server type:"
echo "1) Paper"
echo "2) Purpur"
echo "3) Fabric"
read -rp "Choose an option [1-3]: " server_choice

if [ "$server_choice" != "1" ] && [ "$server_choice" != "2" ] && [ "$server_choice" != "3" ]; then
    echo "Invalid option. Exiting."
    exit 1
fi

read -p "Enter Minecraft version (e.g., 1.21.1): " version

if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid version format. Expected format: x.x.x (e.g., 1.21.1)"
    exit 1
fi

case "$server_choice" in
    1)
        echo "Fetching PaperMC build information..."
        paper_api="https://papermc.io/api/v2/projects/paper/versions/$version"
        latest_build=$(curl -s "$paper_api" | grep -o '"builds":[^]]*' | sed 's/.*,//')
        if [ -z "$latest_build" ]; then
            echo "Error fetching build information. Exiting."
            exit 1
        fi
        download_url="https://papermc.io/api/v2/projects/paper/versions/$version/builds/$latest_build/downloads/paper-$version-$latest_build.jar"
        jar_name="server.jar"
        ;;
    2)
        echo "Fetching Purpur build information..."
        download_url="https://api.purpurmc.org/v2/purpur/$version/latest/download"
        jar_name="server.jar"
        ;;
    3)
        echo "Fetching Fabric installer..."
        download_url="https://maven.fabricmc.net/net/fabricmc/fabric-installer/1.0.1/fabric-installer-1.0.1.jar"
        jar_name="fabric-installer.jar"
        ;;
esac

echo "Downloading server from $download_url..."
curl -o "$jar_name" "$download_url"
if [ $? -ne 0 ]; then
    echo "Error downloading the server."
    exit 1
fi

echo "Download complete."

if [ "$server_choice" = "3" ]; then
    echo "Installing Fabric server..."
    java -jar "$jar_name" server -mcversion "$version" -downloadMinecraft
    if [ $? -ne 0 ]; then
        echo "Error setting up Fabric server."
        exit 1
    fi
fi

echo "Creating mcserver command..."
mcserver_path="$PREFIX/bin/mcserver"
if [ -f "$mcserver_path" ]; then
    echo "Warning: 'mcserver' command already exists. Overwriting..."
fi

{
echo "#!/bin/bash"
echo "cd \"$server_dir\""
echo "java -Xms${ram}G -Xmx${ram}G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -jar \"$jar_name\" nogui"
} > "$mcserver_path"

chmod +x "$mcserver_path"
echo "You can now start the server by typing 'mcserver'."

echo "Starting the Minecraft server with $ram GB of RAM..."
java -Xms${ram}G -Xmx${ram}G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -jar "$jar_name" nogui