AFC Spool Scan Utility
======================

This utility is designed to interface with a USB QR code scanner and automatically set
spool IDs in AFC.

Once the service is running, the utility will listen for events from the connected USB 
2D barcode scanner. If a scanned code begins with the magic spoolman prefix `web+spoolman:s-`,
or the scanned code is a URL `Base URL\spool\show\`, it will send a `SET_NEXT_SPOOL_ID SPOOL_ID=#` 
command to AFC for the next spool to be loaded.

Here's the scanner that I'm using, but it's expected that most of the 2D barcode scanners
will work with this method: https://www.amazon.com/dp/B0DYY7GLSL

Requirements
------------

- Linux system with `evtest` package installed.
- User must be a member of the `input` group to access input devices.

Installation
------------

1. **Clone this repository to your home directory:**

    ```
    cd ~
    git clone https://github.com/kekiefer/afc-spool-scan.git
    cd afc-spool-scan
    ```

2. **Modify the evdev path for your scanner, if necessary**

    My scanner doesn't have a unique serial number, and many others will not
    either, so by default the scanner path is `/dev/input/by-id/usb-TMS_HIDKeyBoard_1234567890abcd-event-kbd`.
    You should plug in your scanner, and check this location to see if you need
    to fix up the `EVENT_DEV` variable in `usb-qr-scanner-read.sh`.

    ```
    ls -la /dev/input/by-id/
    ```

3. **Install the `evtest` package:**

    ```
    sudo apt update
    sudo apt install evtest
    ```

4. **Add your user to the `input` group:**

    ```
    sudo usermod -aG input $(whoami)
    ```

    You must log out and log back in for group changes to take effect. Since a user service
    is used to run this, this might mean a reboot.

5. **Symlink the systemd user service:**

    Assuming `usb-qr-scanner.service` is in the project directory:

    ```
    mkdir -p ~/.config/systemd/user
    ln -s ~/afc-spool-scan/usb-qr-scanner.service ~/.config/systemd/user/usb-qr-scanner.service
    ```

6. **Enable and start the systemd user service:**

    The service will start automatically when the system is rebooted:

    ```
    systemctl --user daemon-reload
    systemctl --user enable usb-qr-scanner.service
    systemctl --user start usb-qr-scanner.service
    ```
