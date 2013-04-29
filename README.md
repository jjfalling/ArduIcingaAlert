ArduIcingaAlert
===============

This script controls leds on an arduino runing firmata depending on the json output of Icinga. 
It is designed to turn on and off red, yellow, blue, and green leds to indicate critical, warning, unknown, and ok states. Also attach a switch to switch the leds between blinking an solid.

Requires:
 Time::HiRes;
 Device::Firmata;
 WWW::Mechanize;
 JSON;
