%macro greet(who);data _null_;put "Hello &who";run;%mend greet;
