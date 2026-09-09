%macro shout(msg);data _null_;put "[%upcase(&msg)]";run;%mend shout;
