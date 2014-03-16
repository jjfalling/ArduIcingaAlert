ArduIcingaAlert
===============

This script controls leds on an arduino or spark core depending on the json output of Icinga. 
It is designed to turn on and off red, yellow, blue, and green leds to indicate critical, warning, unknown, and ok states. 

At the top of the file there are several options that allow you to ignore hosts and services in certain states. 

There are two versions, the first for using an arduino running firmata over serial and the second for a spark core with the provided firmware.  See the the readme of the desired version for more information. 