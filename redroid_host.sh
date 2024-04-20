#!/bin/bash

# this script assumes you already have your docker-compose.yml setup and redroid containers running
# all of this should be auto created by redroid_init.sh
# if redroid_init.sh is not found in the repo check back later

# this script requires you to certify by registering your device
# the script will pause to get your input to confirm it
# this removes the nagging play protect pop-up that prohibits magisk init and sulist functions from being carried out
# these input touch and keyevents are dependent on the screen being free and clear of obstructions

exeggcute_package="com.gocheats.launcher"
exeggcute_apk=$(ls -t *exeggcute*.apk | head -n 1 | sed -e 's@\*@@g')
pogo_package="com.nianticlabs.pokemongo"
pogo_apk=$(ls -t *pokemongo*.apk | head -n 1 | sed -e 's@\*@@g')
pogo_version=0.309.0

# true will start exeggcute after any update, install, or main function call
exeggcute_startup=true

# Ensure the exeggcute directory exists
mkdir -p ~/exeggcute
cd ~/exeggcute


# vm.txt should contain ip:port of every redroid container you have per line
if [ ! -f vm.txt ]; then
    echo "[error] vm.txt file not found"
    echo "[error] you need to create vm.txt and add all your redroids to it"
    exit 1
fi

# redroid_device.sh needs to be in the same folder
# this script is required to run inside redroid
if [ ! -f redroid_device.sh ]; then
    echo "[error] redroid_device.sh file not found"
    exit 1
fi

logdir="./script-logs"
logfile=${logdir}/exeggcute.script.log
cerror=${logdir}/connection_error.log

log() {
    line="$(date +'[%Y-%m-%dT%H:%M:%S %Z]') $@"
    echo "$line"
}

mkdir -p "$logdir"
touch "$logfile"
exec > >(tee -a "$logfile") 2>&1

cd ~/exeggcute

# Read device list from vm.txt
# format should be ip:port of your redroid containers for adb
# e.g. localhost:5555 localhost:5556, etc per line
mapfile -t devices < vm.txt

# handle adb connect and catch errors to avoid bad installs
adb_connect_device() {
    local device_ip="$1"
    local timeout_duration="60s"
    local max_retries=3
    local attempt=0

    # disconnect before connecting to avoid already connected status
    adb disconnect "${device_ip}"
    sleep 1
    echo "[adb] trying to connect to ${device_ip}..."
    while (( attempt < max_retries )); do
        local output=$(timeout $timeout_duration adb connect "${device_ip}" 2>&1)
        if [[ "$output" == *"connected"* ]]; then
            echo "[adb] connected successfully to ${device_ip}."
            return 0  # success
        elif [[ "$output" == *"offline"* ]]; then
            echo "[adb] device ${device_ip} is offline, retrying in 10 seconds..."
            ((attempt++))
            sleep 30
        elif [[ "$output" == *"connection refused"* ]]; then
            echo "[adb] connection refused to ${device_ip}. Exiting script."
            exit 1  # exit script completely
        elif [[ $? -eq 124 ]]; then  # Check if timeout occurred
            echo "[adb] connection attempt to ${device_ip} timed out."
            echo "${device_ip} Timeout" >> "$logfile"
            exit 1  # Failure due to timeout, terminate script
        else
            echo "[error] connecting to ${device_ip}: $output"
            echo "${device_ip} Error" >> "$logfile"
            exit 1  # Unknown failure, terminate script
        fi
    done
    echo "[adb] max retries reached, unable to connect to ${device_ip}."
    exit 1  # Failure after retries
}


# handle connecting via root to avoid bad installs
adb_root_device() {
    local device_ip="$1"
    local timeout_duration="60s"
    local max_retries=3
    local attempt=0

    echo "[adb] trying to connect as root to ${device_ip}"
    while (( attempt < max_retries )); do
        local output=$(timeout $timeout_duration adb -s "${device_ip}" root 2>&1)
        if [[ "$output" == *"restarting adbd"* || "$output" == *"already running"* ]]; then
            echo "[adb] running as root successfully ${device_ip}."
            return 0  # success
        elif [[ "$output" == *"error"* ]]; then
            echo "[adb] device ${device_ip} is offline, retrying in 10 seconds..."
            ((attempt++))
            sleep 30
        elif [[ "$output" == *"production builds"* ]]; then
            echo "[adb] cannot run as root in production builds on ${device_ip}."
            echo "[adb] this error means your redroid image is not correct."
            exit 1  # exit script completely
        elif [[ $? -eq 124 ]]; then  # Check if timeout occurred
            echo "[adb] connection attempt to ${device_ip} timed out."
            echo "${device_ip} Timeout" >> "$logfile"
            exit 1  # Failure due to timeout, terminate script
        else
            echo "[error] connecting to ${device_ip}: $output"
            echo "${device_ip} Error" >> "$logfile"
            exit 1  # Unknown failure, terminate script
        fi
    done
    echo "[adb] Max retries reached, unable to connect to ${device_ip}."
    exit 1  # Failure after retries
}

# handle unrooting to avoid adb_vendor_key unpairing hell
adb_unroot_device() {
    local device_ip="$1"
    local timeout_duration="60s"
    local max_retries=3
    local attempt=0

    echo "[adb] trying to unroot on ${device_ip}"
    while (( attempt < max_retries )); do
        local output=$(timeout $timeout_duration adb -s "${device_ip}" unroot 2>&1)
        if [[ "$output" == *"restarting adb"* || "$output" == *"not running as root"* ]]; then
            echo "[adb] unroot is successful ${device_ip}."
            return 0  # success
        elif [[ "$output" == *"error"* ]]; then
            echo "[adb] device ${device_ip} is offline, retrying in 10 seconds..."
            ((attempt++))
            sleep 30
        elif [[ $? -eq 124 ]]; then  # Check if timeout occurred
            echo "[adb] unroot attempt to ${device_ip} timed out."
            echo "${device_ip} Timeout" >> "$logfile"
            exit 1  # Failure due to timeout, terminate script
        else
            echo "[error] unrooting ${device_ip}: $output"
            echo "${device_ip} Error" >> "$logfile"
            exit 1  # Unknown failure, terminate script
        fi
    done
    echo "[adb] Max retries reached, unable to unroot ${device_ip}."
    exit 1  # Failure after retries
}

# you need to manually certify by registering your device to a google account:
# https://www.google.com/android/uncertified/
# this function will grab the android_id needed for you, and wait for you to confirm "yes" you've registered
setup_certification_script() {
    for i in "${devices[@]}"; do
        if adb_connect_device "$i"; then
            if adb_root_device "$i"; then
                # obtaining android_id from device
                echo "[cert] obtaining android_id for certification from device $i:"
                android_id=$(adb -s $i shell "su -c 'sqlite3 /data/data/com.google.android.gsf/databases/gservices.db \"select * from main where name = \\\"android_id\\\";\"'")

                # check if we got a valid output or not
                if [[ -z "$android_id" ]]; then
                    echo "[cert] failed to retrieve android_id from device $i. Please check if the device is rooted properly."
                    exit 1
                else
                    echo "[cert] android_id for device: $android_id"
                fi

                # request the user to certify the device and provide url
                echo "[cert] please certify by registering your device:"
                echo "https://www.google.com/android/uncertified/"
                echo "Android_ID: \"$android_id\""

                # loop to confirm with user registration has been completed
                while true; do
                    echo "have you completed the registration? (yes/no)"
                    read user_input

                    # Check user's response
                    if [[ "$user_input" == "yes" ]]; then
                        echo "[cert] registration confirmed for device $i with android_id: \"$android_id\"."
                        break  # exit the loop if user confirms registration
                    else
                        echo "[cert] invalid input, please complete registration then type 'yes'"
                        # the beatings will continue until morale improves
                    fi
                done
            else
                echo "[script] Skipping $i due to connection error."
                exit 1
            fi
        else
            echo "[script] Skipping $i due to connection error."
            exit 1
        fi
    done
}

setup_push_script() {
    for i in "${devices[@]}";do
      if adb_connect_device "$i"; then
          adb -s $i push redroid_device.sh /data/local/tmp/
          echo "[setup] scripts transferred and ready"
      else
          echo "[setup] Skipping $i due to connection error."
          exit 1
      fi
    done
}

setup_permissions_script() {
    for i in "${devices[@]}";do
      if adb_connect_device "$i"; then
          if adb_root_device "$i"; then
                # granting scripts executable permission
                adb -s $i shell "su -c chmod +x /data/local/tmp/redroid_device.sh"
                echo "[setup] script chmod +x successful"
            else
                echo "[setup] Skipping $i due to connection error."
                exit 1
          fi
      else
          echo "[magisk] Skipping $i due to connection error."
          exit 1
      fi
    done
}

magisk_setup_settings() {
    for i in "${devices[@]}";do
      if adb_connect_device "$i"; then
          if adb_root_device "$i"; then
              # enabling su via shell and disabling adb root to avoid problems
              echo "[magisk] shell su granting"
              for k in `seq 1 3` ; do
            	  adb -s $i shell "su -c '/system/bin/sh /data/local/tmp/redroid_device.sh setup_magisk_settings'"
              done
              if adb_unroot_device "$i"; then
                  echo "[magisk] shell su settings complete"
              else
                  echo "[magisk] unroot on $i failed, exiting"
                  exit 1
              fi
          else
              echo "[magisk] Skipping $i due to connection error."
              exit 1
          fi
      else
            echo "[magisk] Skipping $i due to connection error."
            exit 1
      fi
    done
}

setup_permissions_script_noroot() {
    for i in "${devices[@]}";do
      if adb_connect_device "$i"; then
          # granting scripts executable permission
          adb -s $i shell "su -c chmod +x /data/local/tmp/redroid_device.sh"
          echo "[setup] script chmod +x successful"
      else
          echo "[magisk] Skipping $i due to connection error."
          exit 1
      fi
    done
}

setup_do_settings() {
    for i in "${devices[@]}";do
      if adb_connect_device "$i"; then
          # running global commands avoid pop-ups and issues
          echo "[setup] setting up global settings"
          adb -s $i shell "su -c '/system/bin/sh /data/local/tmp/redroid_device.sh do_settings'"
          echo "[setup] global settings complete"
          echo "[setup] reboot needed..."
      else
          echo "[setup] Skipping $i due to connection error."
          exit 1
      fi
    done
}

magisk_setup_init() {
    for i in "${devices[@]}";do
      if adb_connect_device "$i"; then
          # completing magisk setup
          echo "[magisk] attempting to finish magisk init"
          adb -s $i shell "su -c '/system/bin/sh /data/local/tmp/redroid_device.sh setup_magisk_app'"
          sleep 60
          echo "[magisk] magisk init setup complete"
          echo "[magisk] reboot needed..."
      else
          echo "[magisk] Skipping $i due to connection error."
          exit 1
      fi
    done
}

magisk_denylist() {
    for i in "${devices[@]}";do
      if adb_connect_device "$i"; then
          # adding common packages to denylist
          adb -s $i shell "su -c '/system/bin/sh /data/local/tmp/redroid_device.sh setup_magisk_denylist'"
          echo "[magisk] denylist complete"
      else
          echo "[setup] Skipping $i due to connection error."
          exit 1
      fi
    done
}

magisk_sulist() {
    for i in "${devices[@]}";do
      if adb_connect_device "$i"; then
          # setting up magiskhide + sulist
          echo "[magisk] starting magisk hide and sulist services..."
          adb -s $i shell "su -c '/system/bin/sh /data/local/tmp/redroid_device.sh setup_magisksulist_app'"
          sleep 60
          echo "[magisk] hide and sulist enabled"
          echo "[magisk] reboot needed..."
      else
          echo "[setup] Skipping $i due to connection error."
          exit 1
      fi
    done
}

exeggcute_install() {
    for i in "${devices[@]}";do
      if adb_connect_device "$i"; then
          # install exeggcute
          echo "[exeggcute] killing app if it exists"
          adb -s $i shell "su -c 'am force-stop $exeggcute_package && killall $exeggcute_package'"
          adb -s $i install -r $exeggcute_apk
          echo "[exeggcute] installed exeggcute"
          adb -s $i shell "su -c '/system/bin/sh /data/local/tmp/redroid_device.sh setup_exeggcute_policies'"
          echo "[exeggcute] policy added"
      else
          echo "[setup] Skipping $i due to connection error."
          exit 1
      fi
    done
}

exeggcute_uninstall() {
    for i in "${devices[@]}";do
      if adb_connect_device "$i"; then
          # uninstall exeggcute
          echo "[exeggcute] killing app if it exists"
          adb -s $i shell "su -c 'am force-stop $exeggcute_package && killall $exeggcute_package'"
          adb -s $i uninstall $exeggcute_apk
          echo "[exeggcute] uninstalled"
      else
          echo "[setup] Skipping $i due to connection error."
          exit 1
      fi
    done
}

exeggcute_sulist() {
    for i in "${devices[@]}";do
      if adb_connect_device "$i"; then
          # add exeggcute and magisk to sulist
          adb -s $i shell "su -c '/system/bin/sh /data/local/tmp/redroid_device.sh setup_magisk_sulist'"
          echo "[magisk] sulist packages added"
          echo "[magisk] reboot needed..."
      else
          echo "[setup] Skipping $i due to connection error."
          exit 1
      fi
    done
}

pogo_install () {
    # Loop through each device
    for i in "${devices[@]}"; do
        if adb_connect_device "$i" "$port"; then
            echo "[pogo] checking for installed package on device $i"

            # check if the package exists
            if adb -s $i shell "su -c 'pm list packages | grep -q \"$pogo_package\"'"; then
                # package exists, checking version
                installed_version=$(adb -s $i shell dumpsys package $pogo_package | grep versionName | cut -d "=" -f 2 | tr -d '\r')
                echo "[pogo] installed version is '$installed_version'"

                # check if the installed version is outdated
                if [[ "$(printf '%s\n' "$pogo_version" "$installed_version" | sort -V | head -n1)" != "$installed_version" ]]; then
                    echo "[pogo] installed version is outdated, preparing to update"
                    echo "[pogo] killing app if it exists and uninstalling"
                    adb -s $i shell "su -c 'am force-stop $pogo_package && killall $pogo_package'"
                    adb -s $i uninstall $pogo_package
                else
                    echo "[pogo] already up-to-date, skipping install"
                    continue  # Skip to the next device
                fi
            else
                echo "[pogo] app not installed, preparing to install"
                timeout 5m adb -s $i install -r $pogo_apk
            fi
        else
            echo "[pogo] skipping $i due to connection error."
            continue
        fi
    done
}

exeggcute_start() {
    # Loop through each device
    for i in "${devices[@]}";do
      if adb_connect_device "$i" "$port"; then
          # stop exeggcute if it is running
          adb -s $i shell "su -c 'am force-stop $exeggcute_package && killall $exeggcute_package'"
          # launch exeggcute
          adb -s $i shell "su -c 'am start -n $exeggcute_package/.MainActivity'"
          echo "[exeggcute] launched"
      else
          echo "[exeggcute] Skipping $i due to connection error."
          exit 1
      fi
    done
}

  # magisk will sometimes think it failed repacking
  # repackage manually or add in your own scripting to account for errors
  # the error is a misleading, as it does succeed, but does not replace the old apk
  # you will need to reboot, then select the new repackced apk (settings)

magisk_repackage() {
  for i in "${devices[@]}";do
    if adb_connect_device "$i"; then
        echo "[magisk] attempting to repackage magisk..."
        adb -s $i shell "su -c '/system/bin/sh /data/local/tmp/redroid_device.sh repackage_magisk'"
        sleep 60
        echo "[magisk] reboot needed..."
        adb -s $i shell "su -c 'reboot'"
        sleep 30
    else
        echo "[setup] Skipping $i due to connection error."
        exit 1
    fi
  done
}

reboot_redroid() {
    for i in "${devices[@]}";do
      if adb_connect_device "$i"; then
          # reboot redroid
          adb -s $i shell "su -c 'reboot'"
          echo "[setup] reboot needed...sleep 30"
          sleep 30
      else
          echo "[setup] Skipping $i due to connection error."
          exit 1
      fi
    done
}

exeggcute_update() {
    setup_push_script || { log "[error] transferring redroid setup script"; exit 1; }
    setup_permissions_script_noroot || { log "[error] granting redroid_device.sh chmod +x"; exit 1; }
    exeggcute_install || { log "[error] installing exeggcute"; exit 1; }
    if $exeggcute_startup ; then
      exeggcute_start || { log "[error] launching exeggcute"; exit 1; }
    fi
}

pogo_update() {
    setup_push_script || { log "[error] transferring redroid setup script"; exit 1; }
    setup_permissions_script_noroot || { log "[error] granting redroid_device.sh chmod +x"; exit 1; }
    pogo_install || { log "[error] installing exeggcute"; exit 1; }
    if $exeggcute_startup ; then
      exeggcute_start || { log "[error] launching exeggcute"; exit 1; }
    fi
}

# If no arguments are provided, run all functions
if [ $# -eq 0 ]; then
    main() {
        setup_certification_script || { log "[error] verifying certification status"; exit 1; }
        setup_push_script || { log "[error] transferring redroid setup script"; exit 1; }
        setup_permissions_script || { log "[error] granting redroid_device.sh chmod +x"; exit 1; }
        magisk_setup_settings || { log "[error] giving shell su perms"; exit 1; }
        reboot_redroid || { log "[error] rebooting redroid"; exit 1; }
        setup_do_settings || { log "[error] enabling global settings"; exit 1; }
        reboot_redroid || { log "[error] rebooting redroid"; exit 1; }
        magisk_setup_init || { log "[error] completing magisk init"; exit 1; }
        reboot_redroid || { log "[error] rebooting redroid"; exit 1; }
        magisk_denylist || { log "[error] setting up denylist"; exit 1; }
        magisk_sulist || { log "[error] enabling sulist"; exit 1; }
        exeggcute_install || { log "[error] installing exeggcute"; exit 1; }
        exeggcute_sulist || { log "[error] adding exeggcute to sulist"; exit 1; }
        reboot_redroid || { log "[error] rebooting redroid"; exit 1; }
        pogo_install || { log "[error] pogo install failed"; exit 1; }
        if $exeggcute_startup ; then
          exeggcute_start || { log "[error] launching exeggcute"; exit 1; }
        fi
    }

    main

# If argument is provided, attempt to call the function with that name
else
    while [[ $# -gt 0 ]]; do
        if typeset -f "$1" > /dev/null; then
          "$1" || { log "[error] running function '$1'"; exit 1; }
        else
            log "[error] no such function: '$1'"
            exit 1
        fi
        shift
    done
fi
