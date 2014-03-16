// Spark firmware interleaves background CPU activity associated with WiFi + Cloud activity with your code. 
// Make sure none of your code delays or blocks for too long (like more than 5 seconds), or weird things can happen.


//define the led color pins
int greenLed = A0;  
int yellowLed = A1; 
int redLed = A2;
int blueLed = A3; 

//0 is low to turn on, 1 is high to turn on
int outputType = 0;

//how long should the status blink be (in ms)?
int blinkDelay = 700;

//how long should we wait to be updated before throwing an error (in seconds)?
int updateWatchdog = 120;


//some globals
unsigned char on;
unsigned char off;
String blue="0";
String red="0";
String yellow="0";
String blink="1";
unsigned long lastUpdate=0;
unsigned long time;


void setup() {

	//[send y,r,b,blink]
	Spark.function("alert", updateAlert);
	
	//Serial.begin(9600);

	pinMode(greenLed, OUTPUT);
	pinMode(yellowLed, OUTPUT);
	pinMode(redLed, OUTPUT);
	pinMode(blueLed, OUTPUT);

	Serial.println("Ready");

	if (outputType == 0) {
		on=LOW;
		off=HIGH;
	}
	else {
		on=HIGH;
		off=LOW;  
	}


	//ensure all leds are off
	digitalWrite(greenLed, off);
	digitalWrite(yellowLed, off);
	digitalWrite(redLed, off);
	digitalWrite(blueLed, off);
 
}


void loop() {
    
	//updateWatchdog * 1000000 to get ms
	time = millis();
	//Serial.println(time);
	unsigned long  updateWatchdogMs = updateWatchdog * 1000;
	//Serial.println(updateWatchdogMs);
	unsigned long lastUpdateDiff = time - lastUpdate;
	//Serial.println(lastUpdateDiff);
	if (lastUpdateDiff > updateWatchdogMs) {
	errorPattern();    
	}

	else {

		if (red == "1" || yellow == "1" || blue == "1" ) {
			digitalWrite(greenLed, off);

			if (yellow == "1") {
				digitalWrite(yellowLed, on);
			}
			if (red == "1") {
				digitalWrite(redLed, on);
			}
			if (blue == "1") {
				digitalWrite(blueLed, on);
			}


			if (blink == "1") {
				delay(blinkDelay); 
				digitalWrite(yellowLed, off);
				digitalWrite(redLed, off);
				digitalWrite(blueLed, off);
				delay(blinkDelay);
			}

		}
		else {
			digitalWrite(yellowLed, off);
			digitalWrite(redLed, off);
			digitalWrite(blueLed, off);

			if (lastUpdate > 0){
				digitalWrite(greenLed, on);
			}
			//no data yet, blink green light in waiting pattern
			else {
				int waitingDelay = 400;
				digitalWrite(greenLed, on);
				delay(waitingDelay);
				digitalWrite(greenLed, off);
				delay(waitingDelay);
				digitalWrite(greenLed, on);
				delay(waitingDelay);
				digitalWrite(greenLed, off);
				delay(waitingDelay);
				digitalWrite(greenLed, on);
				delay(waitingDelay);
				digitalWrite(greenLed, off);
				delay(1500);
			
			}
		}

	}

}

//[send y,r,b,blink]
int updateAlert(String alertStatus) {

	String nyellow = alertStatus.substring(0,1);
	String nred = alertStatus.substring(1,2);
	String nblue = alertStatus.substring(2,3);
	String nblink = alertStatus.substring(3,4);

	yellow = nyellow;
	red = nred;
	blue = nblue;
	blink = nblink;


	if(alertStatus.substring(3,4) == "1" || alertStatus.substring(3,4) == "0")
	{
		return 1;
		lastUpdate = millis();
	}

	else {
		return -1;
	}

}


//patterns

void errorPattern (void) {
	digitalWrite(greenLed, on);  
	delay(300); 
	digitalWrite(greenLed, off);
	digitalWrite(yellowLed, on);
	delay(300);
	digitalWrite(yellowLed, off);
	digitalWrite(redLed, on); 
	delay(300); 
	digitalWrite(redLed, off);
	digitalWrite(blueLed, on);
	delay(300); 
	digitalWrite(blueLed, off);
	delay(1000);    
}
