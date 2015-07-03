#!/usr/bin/env perl

#****************************************************************************
#*   ArduIcingaAlert - arduino version                                      *
#*   Controls leds on an arduino runing firmata depending on the json       *
#*   output of Icinga.                                                      *
#*                                                                          *
#*   Copyright (C) 2015 by Jeremy Falling except where noted.               *
#*                                                                          *
#*   This program is free software: you can redistribute it and/or modify   *
#*   it under the terms of the GNU General Public License as published by   *
#*   the Free Software Foundation, either version 3 of the License, or      *
#*   (at your option) any later version.                                    *
#*                                                                          *
#*   This program is distributed in the hope that it will be useful,        *
#*   but WITHOUT ANY WARRANTY; without even the implied warranty of         *
#*   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the          *
#*   GNU General Public License for more details.                           *
#*                                                                          *
#*   You should have received a copy of the GNU General Public License      *
#*   along with this program.  If not, see <http://www.gnu.org/licenses/>.  *
#****************************************************************************

#pin assignments
my $green_pin  = 2;
my $yellow_pin = 3;
my $red_pin    = 4;
my $blue_pin   = 5;

#used to turn on/off led blinking feature
my $switch_pin = 13;

#the serial port that the arduino is on
my $serialPort = "/dev/ttyUSB0";

#Icinga url to the status that you want to dislplay (in json), with the format of https(s)://user:pass@url
my $icingaURL = 'https://username:password@host.tld/icinga/cgi-bin/status.cgi?allunhandledproblems&scroll=0&jsonoutput';

#How often in do you want to poll icinga (in seconds)?
my $updateInterval = "30";

#how fast do you want the led to blink?
my $blinkDelay = "0.5";

#Ignore everything with disabled notifications? 0 = no, 1 = yes
my $ignoreDisabledNotifications = 1;

#Ignore acknowledged host/services? 0 = no, 1 = yes
my $ignoreAcknowledged = 1;

#Ignore flapping host/services? 0 = no, 1 = yes
my $ignoreFlapping = 1;

#Ignore host/services with scheduled downtime? 0 = no, 1 = yes
my $ignoreSchDowntime = 1;

#What is the min time in seconds for a host or service to have a problem before reporting it? 0 to disable
my $minProblemTime = 60;

#Max age of the icinga status data in seconds. This detect if icinga is responding but no longer doing or reporting check status
my $maxStatusDataAge = 60;

#reverse these if you don't have the ground pin of the leds connected to the digital pins (default 0-on, 1-off)
my $on  = 0;
my $off = 1;

#########################################################################
#set min perl version
use 5.12.1;
use strict;
use warnings;
use Data::Dumper;
use Time::HiRes;
use Device::Firmata::Constants qw/ :all /;
use Device::Firmata;
use WWW::Mechanize;
use JSON;
use Encode qw(encode_utf8);

$|++;
my $jsonData;

#if we get an interupt, run function to exit
$SIG{INT}  = \&interrupt;
$SIG{TERM} = \&interrupt;
$SIG{HUP}  = \&interrupt;

my $progName    = "ArduIcingaAlert";
my $progVersion = "1.0";

my $iteration = my $criticalStatus = my $warningStatus = my $okStatus = my $unknownStatus = my $updateError = my $blinkLED = my $lastTime = 0;

print "Waiting for arduino to boot or become ready, please wait...\n";

my $device = Device::Firmata->open("$serialPort") or die "Could not connect to device running Firmata Server on port $serialPort";

#print device info
printf "Firmware name: %s\n",    $device->{metadata}{firmware};
printf "Firmware version: %s\n", $device->{metadata}{firmware_version};
do { $device->{protocol}->{protocol_version} = $_ if $device->{metadata}{firmware_version} eq $_ }
  foreach keys %$COMMANDS;
printf "Protocol version: %s\n", $device->{protocol}->{protocol_version};

#set up the pins
$device->pin_mode( $green_pin  => PIN_OUTPUT );
$device->pin_mode( $yellow_pin => PIN_OUTPUT );
$device->pin_mode( $red_pin    => PIN_OUTPUT );
$device->pin_mode( $blue_pin   => PIN_OUTPUT );
$device->pin_mode( $switch_pin => PIN_INPUT );

#watch the switch pin, and run onSwitchChange sub when there is a change
$device->observe_digital( $switch_pin, \&onSwitchChage );

#poll the device every 200ms
$device->sampling_interval(200);

#turn all of the leds off
$device->digital_write( $green_pin  => $off );
$device->digital_write( $red_pin    => $off );
$device->digital_write( $yellow_pin => $off );
$device->digital_write( $blue_pin   => $off );

#get inital switch position
$blinkLED = "print $device->digital_read($switch_pin)";

print "\nReady\n\n";

#main loop
while (1) {

    #update the status if needed
    updateStatus();

    #start controlling the leds
    controlLeds();
    errorPattern() if $updateError ne 0;

    #this is needed to keep the script from consuming too many resources
    Time::HiRes::sleep("$blinkDelay");

    #get the postition of the switch
    $device->poll;
}

sub controlLeds {

    #check to see if blinking is enabled
    if ( $blinkLED eq 1 ) {
        my $strobe_state = $iteration++ % 2;

        #dont blink the green light
        if   ( $okStatus eq $on )      { $device->digital_write( $green_pin  => $okStatus ); }
        if   ( $warningStatus eq $on ) { $device->digital_write( $yellow_pin => $strobe_state ); }
        else                           { $device->digital_write( $yellow_pin => $off ); }
        if   ( $criticalStatus eq $on ) { $device->digital_write( $red_pin => $strobe_state ); }
        else                            { $device->digital_write( $red_pin => $off ); }
        if   ( $unknownStatus eq $on ) { $device->digital_write( $blue_pin => $strobe_state ); }
        else                           { $device->digital_write( $blue_pin => $off ); }

    }

    else {
        $device->digital_write( $green_pin  => $okStatus );
        $device->digital_write( $yellow_pin => $warningStatus );
        $device->digital_write( $red_pin    => $criticalStatus );
        $device->digital_write( $blue_pin   => $unknownStatus );

    }

}

#when the switch is changed, change blink state
sub onSwitchChage {
    my ( $pin, $old, $new ) = @_;

    #print "swich change. now $new\n";
    $blinkLED = $new;

}

#this is used if there is an error to display a led pattern to the user
sub errorPattern {
    $device->digital_write( $green_pin => $on );
    Time::HiRes::sleep(0.2);
    $device->digital_write( $green_pin => $off );
    Time::HiRes::sleep(0.2);

    $device->digital_write( $yellow_pin => $on );
    Time::HiRes::sleep(0.2);
    $device->digital_write( $yellow_pin => $off );
    Time::HiRes::sleep(0.2);

    $device->digital_write( $red_pin => $on );
    Time::HiRes::sleep(0.2);
    $device->digital_write( $red_pin => $off );
    Time::HiRes::sleep(0.2);

    $device->digital_write( $blue_pin => $on );
    Time::HiRes::sleep(0.2);
    $device->digital_write( $blue_pin => $off );
    Time::HiRes::sleep(0.2);

}

sub updateStatus {

    #check if its time to run this again, if not, exit from function
    return unless ( ( time - $lastTime ) >= $updateInterval );

    $updateError = 0;

    $criticalStatus = $warningStatus = $okStatus = $unknownStatus = $off;

    #fetch jsondata. it will throw an error and exit if there is an issue
    my $mech = WWW::Mechanize->new( autocheck => 0 );
    my $res = $mech->get($icingaURL);

    unless ( $res->is_success() ) {

        my $time  = gmtime( time() );
        my $error = $mech->res->content;
        print "$time GMT - ERROR: could not connect to url: $error\n";

        #update time of last run
        $lastTime = time;

        $updateError = 1;
    }

    else {

        #put the json data into a hash
        $jsonData = decode_json( encode_utf8( $mech->content ) );

        #check if icinga returned an error
        if ( defined $jsonData->{'error'} ) {

            my $time  = gmtime( time() );
            my $error = $jsonData->{'error'}->{'text'};
            print "$time GMT - ERROR: icinga gave an error: $error\n";

            $updateError = 1;

        }

        #check if the icinga data is too old
        elsif ( $jsonData->{'icinga_status'}->{'status_data_age'} > $maxStatusDataAge ) {

            my $time  = gmtime( time() );
            my $error = $jsonData->{'error'}->{'text'};
            print "$time GMT - ERROR: icinga status data too old. Max allowed is: $maxStatusDataAge, found: $jsonData->{'icinga_status'}->{'status_data_age'}\n";

            $updateError = 1;
        }

        else {

            my $numOfKeys = keys( $jsonData->{'status'}->{'service_status'} );
            for ( my $i = 0 ; $i < $numOfKeys ; $i++ ) {

                #go through the options of what to ignore, if any hit, ignore this service
              CHECKSERVICESTATUS: {
                    if    ( $ignoreDisabledNotifications eq 1 && ( $jsonData->{'status'}->{'service_status'}[$i]->{'notifications_enabled'} ) eq 0 ) { last CHECKSERVICESTATUS; }
                    elsif ( $ignoreAcknowledged eq 1          && ( $jsonData->{'status'}->{'service_status'}[$i]->{'has_been_acknowledged'} ) eq 1 ) { last CHECKSERVICESTATUS; }
                    elsif ( $ignoreFlapping eq 1              && ( $jsonData->{'status'}->{'service_status'}[$i]->{'is_flapping'} ) eq 1 )           { last CHECKSERVICESTATUS; }
                    elsif ( $ignoreSchDowntime eq 1           && ( $jsonData->{'status'}->{'service_status'}[$i]->{'in_scheduled_downtime'} ) eq 1 ) { last CHECKSERVICESTATUS; }
                    else {
                        unless ( convertDurationToSec( $jsonData->{'status'}->{'service_status'}[$i]->{'duration'} ) < $minProblemTime ) {

                            if    ( $jsonData->{'status'}->{'service_status'}[$i]->{'status'} =~ /critical/i )    { $criticalStatus = $on; }
                            elsif ( $jsonData->{'status'}->{'service_status'}[$i]->{'status'} =~ /warning/i )     { $warningStatus  = $on; }
                            elsif ( $jsonData->{'status'}->{'service_status'}[$i]->{'status'} =~ /unknown/i )     { $unknownStatus  = $on; }
                            elsif ( $jsonData->{'status'}->{'service_status'}[$i]->{'status'} =~ /unreachable/i ) { $unknownStatus  = $on; }
                            else                                                                                  { print "ERROR: unknown status $jsonData->{'status'}->{'service_status'}[$i]->{'status'}"; $updateError = 1; }

                        }
                    }
                }
            }

            $numOfKeys = keys( $jsonData->{'status'}->{'host_status'} );
            for ( my $i = 0 ; $i < $numOfKeys ; $i++ ) {

                #go through the options of what to ignore, if any hit, ignore this service
              CHECKHOSTSTATUS: {
                    if    ( $ignoreDisabledNotifications eq 1 && ( $jsonData->{'status'}->{'host_status'}[$i]->{'notifications_enabled'} ) eq 0 ) { last CHECKHOSTSTATUS; }
                    elsif ( $ignoreAcknowledged eq 1          && ( $jsonData->{'status'}->{'host_status'}[$i]->{'has_been_acknowledged'} ) eq 1 ) { last CHECKHOSTSTATUS; }
                    elsif ( $ignoreFlapping eq 1              && ( $jsonData->{'status'}->{'host_status'}[$i]->{'is_flapping'} ) eq 1 )           { last CHECKHOSTSTATUS; }
                    elsif ( $ignoreSchDowntime eq 1           && ( $jsonData->{'status'}->{'host_status'}[$i]->{'in_scheduled_downtime'} ) eq 1 ) { last CHECKHOSTSTATUS; }
                    else {
                        unless ( convertDurationToSec( $jsonData->{'status'}->{'host_status'}[$i]->{'duration'} ) < $minProblemTime ) {

                            if    ( $jsonData->{'status'}->{'host_status'}[$i]->{'status'} =~ /down/i )        { $criticalStatus = $on; }
                            elsif ( $jsonData->{'status'}->{'host_status'}[$i]->{'status'} =~ /unknown/i )     { $unknownStatus  = $on; }
                            elsif ( $jsonData->{'status'}->{'host_status'}[$i]->{'status'} =~ /unreachable/i ) { $unknownStatus  = $on; }
                            else                                                                               { print "ERROR: unknown status $jsonData->{'status'}->{'host_status'}[$i]->{'status'}"; $updateError = 1; }
                        }
                    }
                }
            }

            #if no other status is active, use ok.
            if ( $criticalStatus eq "$off" && $warningStatus eq "$off" && $unknownStatus eq "$off" ) { $okStatus = $on; }
        }
    }

    #update time of last run
    $lastTime = time;

}

#if the user ctrl+c's the program, turn off the leds and exit
sub interrupt {
    print STDERR "\nReceived an interupt, shutting down....\n";
    $device->digital_write( $green_pin  => $off );
    $device->digital_write( $red_pin    => $off );
    $device->digital_write( $yellow_pin => $off );
    $device->digital_write( $blue_pin   => $off );

    exit;
}

#convert icinga duration to seconds
sub convertDurationToSec {

    #get the duration, clan it up
    my $duration = $_[0];
    $duration =~ s/[^0-9\s]+//g;
    $duration =~ s/\s+/,/g;

    my ( $days, $hours, $minutes, $seconds ) = split /,/, $duration;

    unless ( ( length $days ) && ( length $hours ) && ( length $minutes ) && ( length $seconds ) ) {
        print STDERR "\nERROR: invalid duration passed to convertDurationToSec. This more then likely is an issue with the data in the icinga API....\n";
        exit 1;
    }

    #convert all of the times to seconds
    $days    = $days * 86400;
    $hours   = $hours * 3600;
    $minutes = $minutes * 60;

    my $finalSecs = $days + $hours + $minutes + $seconds;

    return $finalSecs;
}
