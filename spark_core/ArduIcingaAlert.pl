#!/usr/bin/env perl

#****************************************************************************
#*   ArduIcingaAlert - spark core version                                   *
#*   Controls leds on a spark core depending on the json output of Icinga.  *
#*                                                                          *
#*   Copyright (C) 2013 by Jeremy Falling except where noted.               *
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


#spark access token/key
my $sparkAccessToken = "changme";

#spark device id
my $sparkDeviceId = "changeme";

#url of the json data you want, with the format of https(s)://user:pass@url
my $icingaURL = 'https://username:password@host.tld/icinga/cgi-bin/status.cgi?allunhandledproblems&scroll=0&jsonoutput';

#how often in do you want this to update (in seconds)? 
my $updateInterval = "30";

#enable led blinking?
my $blink = 1;

#ignore everything with disabled notifications? 0 = no, 1 = yes
my $ignoreDisabledNotifications = 1;

#ignore acknowledged host/services? 0 = no, 1 = yes
my $ignoreAcknowledged = 1;

#ignore flapping host/services? 0 = no, 1 = yes
my $ignoreFlapping = 1;

#ignore host/services with scheduled downtime? 0 = no, 1 = yes
my $ignoreSchDowntime = 1;


#########################################################################   
use strict;
use warnings;
use Data::Dumper;
use WWW::Mechanize;
use JSON;
use Getopt::Long;

$|++;
my $jsonData;

#if we get an interupt, run function to exit
$SIG{INT} = \&interrupt;
$SIG{TERM} = \&interrupt;
$SIG{HUP} = \&interrupt;

my $progName = "ArduIcingaAlert";
my $progVersion = "1.0";

my $iteration = my $criticalStatus = my $warningStatus = my $okStatus = my $unknownStatus = my $updateError = my $blinkLED = my $lastTime = 0;
my $on = 1;
my $off = 0;
my $debug;


#TODO: fix whole debug vs verbose thing.
Getopt::Long::Configure('bundling');
GetOptions
        ("d|debug" => \$debug) ;

debugOutput("Debugging enabled");

print "\nReady\n\n";


#main loop
while (1) {

	#update the status if needed
	updateStatus();

	#this is needed to keep the script from consuming too many resources
	sleep("1");
	

}


sub controlLeds {
  
  #check if there was an error updating, if not update the core with the status
  if ($updateError == 0) {
  
	debugOutput("Attempting to update spark core");
    my $mechUpdate = WWW::Mechanize->new(autocheck => 0);
    my $resUpdate = $mechUpdate ->post("https://api.spark.io/v1/devices/$sparkDeviceId/alert", 
				       [ 'access_token' => "$sparkAccessToken",
					 'params' => "$warningStatus$criticalStatus$unknownStatus$blink" ] );

    unless($resUpdate->is_success()){
	
      my $time = gmtime(time());
      my $error = $mechUpdate->res->content;
      print "$time GMT - ERROR: could not connect to spark core url: $error\n";

    }
    else {
    	debugOutput("Updated spark core successfully");

    }
    
  }
  #an error occured, update core with error pattern
  else {

	debugOutput("An error occured, updating spark core with error pattern");


    #send an invalid update to the core (not 4 digits) to trigger the error pattern
    my $mechUpdate = WWW::Mechanize->new(autocheck => 0);
    my $resUpdate = $mechUpdate ->post("https://api.spark.io/v1/devices/$sparkDeviceId/alert", 
				       [ 'access_token' => "$sparkAccessToken",
					 'params' => "0" ] );

    unless($resUpdate->is_success()){

      my $time = gmtime(time());
      my $error = $mechUpdate->res->content;
      print "$time GMT - ERROR: could not connect to spark core url: $error\n";

    }
  }
}




sub updateStatus {
	#check if its time to run this again, if not, exit from function
	return unless ((time - $lastTime) >= $updateInterval);

	$updateError=0;

	$criticalStatus = $warningStatus = $okStatus = $unknownStatus = $off;
	
	debugOutput("Attempting to update icinga data");

	#fetch jsondata. it will throw an error and exit if there is an issue
	my $mech = WWW::Mechanize->new(autocheck => 0);
	my $res = $mech -> get($icingaURL);
	
	
	unless($res->is_success()){
		
		my $time = gmtime(time());
		my $error = $mech->res->content;
		print "$time GMT - ERROR: could not connect to icinga url: $error\n";

		#update time of last run
		$lastTime = time;
	       	$updateError=1;

	}
	
	else {
	
		debugOutput("Updated icinga data successfully");
		#put the json data into a hash
		$jsonData = decode_json($mech->content);


		#check if icinga returned an error
		if (defined $jsonData->{'error'}){
	
			my $time = gmtime(time());
			my $error = $jsonData->{'error'}->{'text'};
			print "$time GMT - ERROR: icinga gave an error: $error\n";

			$updateError=1;

		}
	
	
		else{
		
			my $numOfKeys = keys($jsonData->{'status'}->{'service_status'}) ;
			for (my $i=0; $i < $numOfKeys; $i++){	
				#go through the options of what to ignore, if any hit, ignore this service
				CHECKSERVICESTATUS: {
					if ($ignoreDisabledNotifications eq 1 && ($jsonData->{'status'}->{'service_status'}[$i]->{'notifications_enabled'}) eq 0){last CHECKSERVICESTATUS;}
					elsif ($ignoreAcknowledged eq 1 && ($jsonData->{'status'}->{'service_status'}[$i]->{'has_been_acknowledged'}) eq 1){last CHECKSERVICESTATUS;}
					elsif ($ignoreFlapping eq 1 && ($jsonData->{'status'}->{'service_status'}[$i]->{'is_flapping'}) eq 1){last CHECKSERVICESTATUS;}
					elsif ($ignoreSchDowntime eq 1 && ($jsonData->{'status'}->{'service_status'}[$i]->{'in_scheduled_downtime'}) eq 1){last CHECKSERVICESTATUS;}
					else {
						if ($jsonData->{'status'}->{'service_status'}[$i]->{'status'} =~ /critical/i){$criticalStatus = $on;}
						elsif ($jsonData->{'status'}->{'service_status'}[$i]->{'status'} =~ /warning/i){$warningStatus = $on;}
						elsif ($jsonData->{'status'}->{'service_status'}[$i]->{'status'} =~ /unknown/i){$unknownStatus = $on;}
						elsif ($jsonData->{'status'}->{'service_status'}[$i]->{'status'} =~ /unreachable/i){$unknownStatus = $on;}
						else {print "ERROR: unknown status $jsonData->{'status'}->{'service_status'}[$i]->{'status'}"; $updateError = 1;}
					}
				}
			}

			$numOfKeys = keys($jsonData->{'status'}->{'host_status'}) ;
			for (my $i=0; $i < $numOfKeys; $i++){	
				#go through the options of what to ignore, if any hit, ignore this service
				CHECKHOSTSTATUS: {
					if ($ignoreDisabledNotifications eq 1 && ($jsonData->{'status'}->{'host_status'}[$i]->{'notifications_enabled'}) eq 0){last CHECKHOSTSTATUS;}
					elsif ($ignoreAcknowledged eq 1 && ($jsonData->{'status'}->{'host_status'}[$i]->{'has_been_acknowledged'}) eq 1){last CHECKHOSTSTATUS;}
					elsif ($ignoreFlapping eq 1 && ($jsonData->{'status'}->{'host_status'}[$i]->{'is_flapping'}) eq 1){last CHECKHOSTSTATUS;}
					elsif ($ignoreSchDowntime eq 1 && ($jsonData->{'status'}->{'host_status'}[$i]->{'in_scheduled_downtime'}) eq 1){last CHECKHOSTSTATUS;}
					else {
						if ($jsonData->{'status'}->{'host_status'}[$i]->{'status'} =~ /down/i){$criticalStatus = $on;}
						elsif ($jsonData->{'status'}->{'host_status'}[$i]->{'status'} =~ /unknown/i){$unknownStatus = $on;}
						elsif ($jsonData->{'status'}->{'host_status'}[$i]->{'status'} =~ /unreachable/i){$unknownStatus = $on;}
						else {print "ERROR: unknown status $jsonData->{'status'}->{'host_status'}[$i]->{'status'}"; $updateError = 1;}
					}
				}
			}

			#if no other status is active, use ok.
			if ($criticalStatus eq $off && $warningStatus eq $off && $unknownStatus eq $off){$okStatus = $on;}
		}

	}
	
	#update time of last run
	$lastTime = time;

	#update the spark core with the new status
	controlLeds();


}


#This function will be used to give the user output, if they so desire
sub debugOutput {
        my $human_status = $_[0];
        if ($debug) {
                print "**DEBUG: ". gmtime(time()) .": $human_status \n";

        }
}


sub interrupt {
    print STDERR "\nReceived an interupt, shutting down....\n";
    exit;
}

