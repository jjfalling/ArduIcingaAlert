ArduIcingaAlert
===============

This script controls leds on an arduino or spark core depending on the json output of Icinga. 
It is designed to turn on and off red, yellow, blue, and green leds to indicate critical, warning, unknown, and ok states. 

Some of the options and features:

* HTTP auth support
* Check icinga status file to ensure icinga is working
* Led blinking / solid
* Can ignore hosts/services that:
 * Have disabled notifications
 * Are acknowledged
 * Are flapping 
 * Have scheduled downtime
 * Have reported a problem for less then $x seconds




There are two versions, the first for using an arduino running firmata over serial and the second for a spark core with the provided firmware.  See the the readme of the desired version for more information and dependancies. 
