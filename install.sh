#!/bin/bash

rm ~/x

pkg upgrade -y && echo "Updated packages" || echo "Error updating packages"

if ! command -v curl &>/dev/null; then
    echo "curl is not installed. Installing curl..."
    pkg install curl -y && echo "Installed curl" || echo "Error installing curl"
    pkg install jq -y && echo "Installed jq" || echo "Error installing jq"
fi

if [ ! -d "$HOME/storage" ]; then
    echo "Requesting storage permissions..."
    termux-setup-storage
    if [ $? -ne 0 ]; then
        echo "Failed to set up storage. Exiting."
        exit 1
    fi
    echo "Storage permissions granted."
fi

read -p "Enter the directory name for your Minecraft server: " directory_name
server_dir="$HOME/storage/shared/$directory_name"
mkdir -p "$server_dir"
cd "$server_dir" || { echo "Failed to access server directory"; exit 1; }

java_ver=$(java -version 2>&1 | awk -F[\"\.] -v OFS=. 'NR==1{print $2}')

if [ "$java_ver" = 17 ]; then
    pkg remove openjdk-17 -y && echo "Removed Java 17" || echo "Error removing Java 17"
fi

if [ "$java_ver" != 21 ]; then
    pkg install openjdk-21 -y && echo "Installed Java 21" || echo "Error installing Java 21"
fi

pkg autoclean && pkg clean -y && echo "Cleaned packages" || echo "Error cleaning packages"

java_ver=$(java -version 2>&1 | awk -F[\"\.] -v OFS=. 'NR==1{print $2}')

if [ "$java_ver" != 21 ]; then
    echo "Java 21 is not installed or is not working"
    exit 1
fi

read -p "Enter the amount of RAM to allocate (in GB, e.g., 1 for 1 GB): " ram
if ! [[ "$ram" =~ ^[0-9]+$ ]]; then
    echo "Invalid input. Exiting."
    exit 1
fi

echo "Select server type:"
echo "1) Paper"
echo "2) Purpur"
echo "3) Fabric"
read -rp "Choose an option [1-3]: " server_type

if [ "$server_type" != "1" ] && [ "$server_type" != "2" ] && [ "$server_type" != "3" ]; then
    echo "Invalid option. Exiting."
    exit 1
fi

read -p "Enter Minecraft version (e.g., 1.21.1): " version

if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid version format. Expected format: x.x.x (e.g., 1.21.1)"
    exit 1
fi

case "$server_type" in
    1)

        MINECRAFT_VERSION=$version

        LATEST_BUILD=$(curl -s https://api.papermc.io/v2/projects/paper/versions/${MINECRAFT_VERSION}/builds | \
            jq -r '.builds | map(select(.channel == "default") | .build) | .[-1]')

        if [ "$LATEST_BUILD" != "null" ]; then
            JAR_NAME=paper-${MINECRAFT_VERSION}-${LATEST_BUILD}.jar
            download_url="https://api.papermc.io/v2/projects/paper/versions/${MINECRAFT_VERSION}/builds/${LATEST_BUILD}/downloads/${JAR_NAME}"
            jar_name="server.jar"
        else
            echo "No stable build for version $MINECRAFT_VERSION found :("
        fi
        echo "Fetching PaperMC build information..."
        
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

if [ "$server_type" = "3" ]; then
    echo "Installing Fabric server..."
    java -jar "$jar_name" server -mcversion "$version" -downloadMinecraft
    jar_name="fabric-server-launch.jar"
    if [ $? -ne 0 ]; then
        echo "Error setting up Fabric server."
        exit 1
    fi
fi

echo "Creating mcserver command..."
mcserver_path="$PREFIX/bin/mcserver"
if [ -f "$mcserver_path" ]; then
    echo "Warning: \"mcserver\" command already exists. Overwriting..."
fi

echo "Acepting Minecraft eula..."
echo "eula=true" > "eula.txt"

{
echo "#!/bin/bash"
echo "cd \"$server_dir\""
echo "java -Xms${ram}G -Xmx${ram}G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true -jar \"$jar_name\" nogui"
} > "$mcserver_path"

chmod +x "$mcserver_path"
echo "You can now start the server by typing \"mcserver\""

echo "Starting the Minecraft server with $ram GB of RAM..."
mcserver
