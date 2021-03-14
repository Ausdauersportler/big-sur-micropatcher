#!/bin/bash

### begin function definitions ###

# Check that we can access the directory that ocntains this script, as well
# as the root directory of the installer USB. Access to both of these
# directories is vital, and Catalina's TCC controls for Terminal are
# capable of blocking both. Therefore we must check access to both
# directories before proceeding.
checkDirAccess() {
    # List the two directories, but direct both stdout and stderr to
    # /dev/null. We are only interested in the return code.
    ls "$VOLUME" . &> /dev/null
}

### end function definitions ###

# Make sure there isn't already an "EFI" volume mounted.
if [ -d "/Volumes/EFI" ]
then
    echo 'An "EFI" volume is already mounted. Please unmount it then try again.'
    echo "If you don't know what this means, then restart your Mac and try again."
    echo
    echo "config-opencore cannot continue."
    exit 1
fi

# For this script, root permissions are vital.
[ $UID = 0 ] || exec sudo "$0" "$@"


ROOT=/
while [[ $1 = -* ]]
do
    case $1 in
    -v | --verbose)
        VERBOSEBOOT="YES"
        #echo 'Verbose boot option enabled.'
        ;;
    -AMD | --polaris*)
        GPU="AMD"
        ;;
    -NV | --kepler*)
        GPU="NV"
        ;;
    --volume)
        shift
        ROOT=$1
        echo "Big Sur Volume Root :" $ROOT
        ;;
    *)
        echo "Unknown command line option: $1"
        exit 1
        ;;
    esac

    shift
done

# Allow the user to drag-and-drop the USB stick in Terminal, to specify the
# path to the USB stick in question. (Otherwise it will try hardcoded paths
# for a presumed Big Sur Golden Master/public release, beta 2-or-later,
# and beta 1, in that order.)
if [ -z "$1" ]
then
    for x in "Install macOS Big Sur" "Install macOS Big Sur Beta" "Install macOS Beta"
    do
        if [ -d "/Volumes/$x/$x.app" ]
        then
            VOLUME="/Volumes/$x"
            APPPATH="$VOLUME/$x.app"
            break
        fi
    done

    if [ ! -d "$APPPATH" ]
    then
        echo "Failed to locate Big Sur recovery USB stick."
        echo "Remember to create it using createinstallmedia, and do not rename it."
        echo "If all else fails, try specifying the path to the USB stick"
        echo "as a command line parameter to this script."
        echo
        echo "config-opencore cannot continue and will now exit."
        exit 1
    fi
else
    VOLUME="$1"
    # The use of `echo` here is to force globbing.
    APPPATH=`echo -n "$VOLUME"/Install\ macOS*.app`
    if [ ! -d "$APPPATH" ]
    then
        echo "Failed to locate Big Sur recovery USB stick for patching."
        echo "Make sure you specified the correct volume. You may also try"
        echo "not specifying a volume and allowing the patcher to find"
        echo "the volume itself."
        echo
        echo "config-opencore cannot continue and will now exit."
        exit 1
    fi
fi

# Check if the opencore directory is inside the current directory. If not,
# it's probably inside the same directory as this script, so find that
# directory.
if [ ! -d opencore ]
then
    BASEDIR="`echo $0|sed -E 's@/[^/]*$@@'`"
    [ -z "$BASEDIR" ] || cd "$BASEDIR"
fi

# Check again in case we changed directory after the first check
if [ ! -d opencore ]
then
    echo '"opencore" folder was not found.'
    echo
    echo "config-opencore cannot continue and will now exit."
    exit 1
fi

# Check to make sure we can access both our own directory and the root
# directory of the USB stick. Terminal's TCC permissions in Catalina can
# prevent access to either of those two directories. However, only do this
# check on Catalina or higher. (I can add an "else" block later to handle
# Mojave and earlier, but Catalina is responsible for every single bug
# report I've received due to this script lacking necessary read permissions.)
RELEASE=`/usr/sbin/chroot "$ROOT" uname -r | sed -e 's@\..*@@'`
if [ $RELEASE -ge 19 ]
then
    echo 'Checking read access to necessary directories...'
    if ! checkDirAccess
    then
        echo 'Access check failed.'
        tccutil reset All com.apple.Terminal
        echo 'Retrying access check...'
        if ! checkDirAccess
        then
            echo
            echo 'Access check failed again. Giving up.'
            echo 'Next time, please give Terminal permission to access removable drives,'
            echo 'as well as the location where this patcher is stored (for example, Downloads).'
            exit 1
        else
            echo 'Access check succeeded on second attempt.'
            echo
        fi
    else
        echo 'Access check succeeded.'
        echo
    fi
fi

MOUNTEDPARTITION=`mount | fgrep "$VOLUME" | awk '{print $1}'`
if [ -z "$MOUNTEDPARTITION" ]
then
    echo Failed to find the partition that
    echo "$VOLUME"
    echo is mounted from. install-opencore cannot proceed.
    exit 1
fi

DEVICE=`echo -n $MOUNTEDPARTITION | sed -e 's/s[0-9]*$//'`
PARTITION=`echo -n $MOUNTEDPARTITION | sed -e 's/^.*disk[0-9]*s//'`
echo "$VOLUME found on device $MOUNTEDPARTITION"

if [ "x$PARTITION" = "x1" ]
then
    echo "The volume $VOLUME"
    echo "appears to be on partition 1 of the USB stick, therefore the stick is"
    echo "incorrectly partitioned (possibly MBR instead of GPT?)."
    echo
    echo 'Please use Disk Utility to erase the USB stick as "Mac OS Extended'
    echo '(Journaled)" format on "GUID Partition Map" scheme and start over with'
    echo '"createinstallmedia". Or for other methods, please refer to the micropatcher'
    echo "README for more information."
    echo
    echo "config-opencore cannot continue."
    exit 1
fi

diskutil mount ${DEVICE}s1
if [ ! -d "/Volumes/EFI" ]
then
    echo "Partition 1 of the USB stick does not appear to be an EFI partition, or"
    echo "mounting of the partition somehow failed."
    echo
    echo 'Please use Disk Utility to erase the USB stick as "Mac OS Extended'
    echo '(Journaled)" format on "GUID Partition Map" scheme and start over with'
    echo '"createinstallmedia". Or for other methods, please refer to the micropatcher'
    echo "README for more information."
    echo
    echo "config-opencore cannot continue."
    exit 1
fi

# Before proceeding with the actual installation, see if we were provided
# a command line option for GPU Type, and if set, make a decision based
# on what Mac model this is.
if [[ "x$GPU" = "xNV"  ||  "x$GPU" = "xAMD" ]]
then
    MACMODEL=`sysctl -n hw.model`
    echo "Detected Mac model is:" $MACMODEL
    case $MACMODEL in
        "iMac11,1" | "iMac11,2" | "iMac11,3")
        echo "Late 2009 or Mid 2010 iMac detected"
        IMAC11="YES"
        ;;
        "iMac12,1")
        echo "Mid 2011 iMac 21.5 inch detected"
        IMAC121="YES"
        ;;
        "iMac12,2")
        echo "Mid 2011 iMac 27 inch detected"
        IMAC122="YES"
        ;;
    *)
        echo "This Mac is no iMac11,x or 12,x, found this system: " $MACMODEL
        OTHERMAC="YES"
        ;;
    esac
fi

#
# basically selection is based on GPU type, not system type
#
if [ -z "$GPU" ]
then
    DID=`/usr/sbin/chroot "$ROOT" /usr/sbin/system_profiler SPDisplaysDataType | fgrep "Device ID" | awk '{print $3}'`

    case $DID in
        # OpenCore: K610M, K1100M, K2100M
        0x12b9 | 0x0ff6 | 0x11fc)
        echo "NVIDIA K610M, K1100M, K2100M found, device ID: " $DID
        GPU="NV"
        ;;
        # NVIDIA (can run witout OpenCore)
        0x1198 | 0x1199 | 0x119a | 0x119f | 0x119e |0x119d |0x11e0 | 0x11e1 | 0x11b8 | 0x11b7 | 0x11b6 | 0x11bc | 0x11bd | 0x11be |0x0ffb | 0x0ffc)
        echo "NVIDIA Kepler Kx100M, Kx000M, GTX8xx, GTX7xx Card found, device ID: " $DID
        GPU="NV"
        ;;
        # OpenCore; AMD Baffin cards
        0x67e8 | 0x67e0 | 0x67c0 | 0x67df | 0x67ef)
        echo "AMD Polaris WX4130/WX4150/WX4170/WX7100/RX480 found, device ID: " $DID
        GPU="AMD"
        ;;
        0x6720 | 0x6740 | 0x6741)
        echo "Original AMD HD 67x0 card found, NO graphics acceleration, device ID: " $DID
        echo "Stopping installation of OpenCore. It does not make any sense to use this system with Big Sur"
        exit 1
        ;;
        0x68c1 | 0x68d8)
        echo "Original AMD HD 5xx0 card found, NO graphics acceleration, device ID: " $DID
        echo "Stopping installation of OpenCore. It does not make any sense to use this system with Big Sur"
        exit 1

        ;;
        0x9488 | 0x944a | 0x944b)
        echo "Original AMD HD 4xx0 card found, NO graphics acceleration, device ID: " $DID
        echo "Stopping installation of OpenCore. It does not make any sense to use this system with Big Sur"
        exit 1
        ;;
        *)
        echo "Unknown GPU model. This may be a config-opencore bug, device ID: " $DID
        GPU="OTHER"
        ;;
    esac
    echo
fi

# Now do the actual installation
echo "removing old opencore EFI utility."

rm -rf /Volumes/EFI/EFI/OC
rm -rf /Volumes/EFI/EFI/BOOT

echo "Installing opencore EFI utility."

cp -r opencore/EFI /Volumes/EFI

echo "Selecting opencore EFI config.plist."

if [ "x$GPU" = "xNV" ]
then
    if [ "x$VERBOSEBOOT" = "xYES" ]
    then
        echo 'Verbose boot enabled, NVIDIA GPU selected'
        cp -f opencore/CONFIG/config_NVIDIA_BigSur_verbose.plist /Volumes/EFI/EFI/OC/config.plist
    else
        echo 'Verbose boot disabled, NVIDIA GPU selected'
        cp -f opencore/CONFIG/config_NVIDIA_BigSur.plist /Volumes/EFI/EFI/OC/config.plist
    fi
elif [ "x$GPU" = "xAMD" ]
then
    if [ "x$VERBOSEBOOT" = "xYES" ]
    then
        echo 'Verbose boot enabled, AMD GPU selected'
        cp -f opencore/CONFIG/config_AMD_BigSur_verbose.plist /Volumes/EFI/EFI/OC/config.plist
    else
        echo 'Verbose boot disabled, AMD GPU selected'
        cp -f opencore/CONFIG/config_AMD_BigSur.plist /Volumes/EFI/EFI/OC/config.plist
    fi
else
    echo 'Verbose boot disabled, no iMac specific metal GPU selected or detected'
    cp -f opencore/CONFIG/config_OTHER_BigSur.plist /Volumes/EFI/EFI/OC/config.plist
fi

echo "Unmounting EFI volume (if this fails, just eject in Finder afterward)."
umount /Volumes/EFI || diskutil unmount /Volumes/EFI

echo
echo 'install-opencore finished.'

exit 0



