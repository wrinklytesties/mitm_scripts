# mitm_scripts
scripts for setting up various mitms

1. **redroid_init.sh**
    - This script is written to take your new server from nothing to running Exeggcute.
    - This will pull in both redroid_host.sh and redroid_setup.sh.
    - Config files for redroid_host.sh, Exeggcute and Houndour will be auto generated based on answers to questions.
    - **SCRIPT HAS ONLY BEEN TESTED ON UBUNTU SYSTEMS. YMMV**


2. **redroid_host.sh**
    - This script should be run on your redroid host
    - Requirements:
        - redroid_setup.sh
        - vm.txt
          - ip per line:
          - localhost:5555, localhost:5556, localhost:5557, etc
    - redroid containers should already be running before you start

3. **redroid_device.sh**
    - This script is required by redroid_host.sh
    - This performs all of the necessary steps inside of redroid itself
    - Including setting up magisk and all necessary features
