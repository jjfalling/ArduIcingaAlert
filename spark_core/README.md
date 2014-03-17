ArduIcingaAlert - Spark core Version
====================================

This version script controls leds on a spark core running the provided firmware depending on the json output of Icinga. 
It is designed to turn on and off red, yellow, blue, and green leds to indicate critical, warning, unknown, and ok states. 

At the top of the perl file there are several options that allow you to ignore hosts and services in certain states. There are also some options to set in the firmware.

Requires:
 WWW::Mechanize;
 JSON;
