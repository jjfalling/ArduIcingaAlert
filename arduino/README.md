ArduIcingaAlert - Arduino Version
=================================

This version script controls leds on an arduino running firmata depending on the json output of Icinga. 
It is designed to turn on and off red, yellow, blue, and green leds to indicate critical, warning, unknown, and ok states. Also attach a switch to enable/disable led blink mode.

At the top of the file there are several options that allow you to ignore hosts and services in certain states. 

Requires:
 Time::HiRes;
 Device::Firmata;
 WWW::Mechanize;
 JSON;
 Device::SerialPort;
