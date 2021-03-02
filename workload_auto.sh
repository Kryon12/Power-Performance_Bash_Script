#!/bin/bash

# This is an intitial check to check whether or not the file exists, and if not
# create said file and set associated permissions. This file will enable/disable
# the settings associated with this script.
if [ -e "/home/brandan/ServiceEnable" ]; then
  enablecheck=`cat /home/brandan/ServiceEnable`
else
  touch /home/brandan/ServiceEnable
  chmod 777 /home/brandan/ServiceEnable
fi

# Determine the current power status of the system as per the reported status by the battery/system.
power=`cat /sys/class/power_supply/BAT0/status`

# Let's perform a check to determine if the power status is Unknown and/or if
# the ServiceEnable file has been set to 1 by the user.
if [ "$power" != "Unknown" ] && [ "$enablecheck" = "1" ]; then

# Determine the current CPU workload type, cpu load and fancontrol minimum temperature.
# Obtain current bluetooth autosuspend status and intel_pstate status.
btusb=`cat /sys/module/btusb/parameters/enable_autosuspend`
pstate=`cat "/sys/devices/system/cpu/intel_pstate/status"`
currentworkload=`cat /sys/bus/pci/devices/0000:00:04.0/workload_request/workload_type`
currentcpuload=`top -b -n1 | grep "Cpu(s)" | awk '{print $2 + $4}'`
currentmintemp=`grep -m 1 "MINTEMP" /etc/fancontrol`
cpufreqgov=`cat /etc/default/cpufrequtils`

# Assign the Intel_Pstate driver status to desired condition if it does not match.
if [ "$pstate" != "passive" ]; then
  echo "Setting Intel_Pstate Driver from $pstate to Active."
  echo "passive" > "/sys/devices/system/cpu/intel_pstate/status"
fi

# Disable bluetooth USB autosuspend to prevent mouse from disconnecting.
if [ "$btusb" = "Y" ]; then
  echo "N" > "/sys/module/btusb/parameters/enable_autosuspend"
fi

# Algorithm to determine whether or not charging/discharging, CPU load.
# Assign workload hint algorithm based on determined charging/discharging status.
# Assign a governor associated with the current status. Conservative for Discharging/Idle and Schedutil for Charging.
# Assign an associated minimum temperature for the fan. This correlates to the ramp temperature.
# This requires dependencies: cpufrequtils, fancontrol.
  if [ "$power" = "Charging" ] || [ "$power" = "Full" ]; then
   mintemp="MINTEMP=hwmon5/pwm1=0"
   governor="GOVERNOR=schedutil"
    if [ 1 -eq "$(echo "${currentcpuload} < 17.99" | bc)" ]; then
        if [ "$currentworkload" != "idle" ]; then
          workload="idle"
        else
          workload="$currentworkload"
        fi
    elif [ 1 -eq "$(echo "${currentcpuload} > 18.01" | bc)" ] && [ 1 -eq "$(echo "${currentcpuload} < 71.99" | bc)" ]; then
        if [ "$currentworkload" != "bursty" ]; then
          workload="bursty"
        else
          workload="$currentworkload"
        fi
    elif [ 1 -eq "$(echo "${currentcpuload} > 72.01" | bc)" ] && [ 1 -eq "$(echo "${currentcpuload} < 100.01" | bc)" ]; then
        if [ "$currentworkload" != "sustained" ]; then
          workload="sustained"
        else
          workload="$currentworkload"
        fi
    fi
    echo "$workload" > /sys/bus/pci/devices/0000:00:04.0/workload_request/workload_type
        if ( [ "$currentworkload" = "bursty" ] || [ "$currentworkload" = "sustained" ] ); then
          if [ "$currentmintemp" != "$mintemp" ]; then
             sed -i -e "s|$currentmintemp|$mintemp|g" /etc/fancontrol
             systemctl restart fancontrol.service
          fi
        elif [ "$currentworkload" = "idle" ]; then
          if [ "$currentmintemp" != "$mintemp" ]; then
             sed -i -e "s|$currentmintemp|$mintemp|g" /etc/fancontrol
             systemctl restart fancontrol.service
          fi
        fi
  elif [ "$power" = "Discharging" ]; then
   mintemp="MINTEMP=hwmon5/pwm1=68"
   governor="GOVERNOR=conservative"
    if [ 1 -eq "$(echo "${currentcpuload} < 11.99" | bc)" ]; then
        if [ "$currentworkload" != "battery_life" ]; then
          workload="battery_life"
        else
          workload="$currentworkload"
        fi
    elif [ 1 -eq "$(echo "${currentcpuload} > 12.01" | bc)" ] && [ 1 -eq "$(echo "${currentcpuload} < 100.01" | bc)" ]; then
        if [ "$currentworkload" != "bursty" ]; then
          workload="bursty"
        else
          workload="$currentworkload"
        fi
    fi
    echo "$workload" > /sys/bus/pci/devices/0000:00:04.0/workload_request/workload_type
        if ( [ "$currentworkload" = "battery_life" ] || [ "$currentworkload" = "bursty" ] ); then
          if [ "$currentmintemp" != "$mintemp" ]; then
            sed -i -e "s|$currentmintemp|$mintemp|g" /etc/fancontrol
            systemctl restart fancontrol.service
          fi
        fi
  fi

# Update cpufrequtils using the /etc/default/ file.
# Restart the cpufrequtils service to update the current governor.
if [ "$governor" != "$cpufreqgov" ]; then
  if [ -e "/etc/default/cpufrequtils" ]; then
    echo "$governor" > /etc/default/cpufrequtils
  else
    touch /etc/default/cpufrequtils
    echo "$governor" > /etc/default/cpufrequtils
  fi
  systemctl restart cpufrequtils.service
fi

# Output all of this information to command line.
 echo "Power Status: $power"
 echo "CPU Load: $currentcpuload"
 echo "intel_pstate=$pstate"
 echo "$governor"
 echo "workload_type=$currentworkload"
 echo "$mintemp"
else
# This is the default state of this bash script and its service.
# ServiceEnable must be set to 1 for this to function.
 echo "Power Status: $power"
 echo "Please set /home/brandan/ServiceEnable"
 echo "to the value of 1 to start this service."
fi

exit 0
