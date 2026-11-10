options nodate nonumber;
data d; input g h r c w; datalines;
1 1 10 2 3
1 1 10 4 1
1 1 20 2 2
2 2 20 4 4
2 2 30 6 0
2 2 . 2 2
;
run;
proc freq data=d noprint; weight w; tables g*h*r*c / outpct outexpect out=result; run;
data _null_; set result; file print; put "BASE" g 16.6 h 16.6 r 16.6 c 16.6 COUNT 16.6 EXPECTED 16.6 PERCENT 16.6 PCT_TABL 16.6 PCT_ROW 16.6 PCT_COL 16.6; run;
proc freq data=d noprint; weight w; tables g*h*r*c / sparse outpct outexpect out=result; run;
data _null_; set result; file print; put "SPARSE" g 16.6 h 16.6 r 16.6 c 16.6 COUNT 16.6 EXPECTED 16.6 PERCENT 16.6 PCT_TABL 16.6 PCT_ROW 16.6 PCT_COL 16.6; run;
proc freq data=d noprint; weight w / zeros; tables r*c /  out=result; run;
data _null_; set result; file print; put "ZEROS" r 16.6 c 16.6 COUNT 16.6 PERCENT 16.6; run;
proc freq data=d noprint; weight w / zeros; tables r*c / nosparse out=result; run;
data _null_; set result; file print; put "NOSPARSE" r 16.6 c 16.6 COUNT 16.6 PERCENT 16.6; run;
proc freq data=d noprint; weight w; tables r*c / missing outpct outexpect out=result; run;
data _null_; set result; file print; put "MISSING" r 16.6 c 16.6 COUNT 16.6 EXPECTED 16.6 PERCENT 16.6 PCT_ROW 16.6 PCT_COL 16.6; run;
proc freq data=d noprint; weight w; tables r / outcum missprint out=result; run;
data _null_; set result; file print; put "MISS" r 16.6 COUNT 16.6 PERCENT 16.6 CUM_FREQ 16.6 CUM_PCT 16.6; run;
proc freq data=d noprint; weight w; tables r / outcum maxlevels=1 out=result; run;
data _null_; set result; file print; put "MAX" r 16.6 COUNT 16.6 PERCENT 16.6 CUM_FREQ 16.6 CUM_PCT 16.6; run;
proc freq data=d order=data noprint; weight w; tables r / missing outcum out=result; run;
data _null_; set result; file print; put "data" r 16.6 COUNT 16.6 PERCENT 16.6 CUM_FREQ 16.6 CUM_PCT 16.6; run;
proc freq data=d order=freq noprint; weight w; tables r / missing outcum out=result; run;
data _null_; set result; file print; put "freq" r 16.6 COUNT 16.6 PERCENT 16.6 CUM_FREQ 16.6 CUM_PCT 16.6; run;
proc freq data=d order=formatted noprint; weight w; tables r / missing outcum out=result; run;
data _null_; set result; file print; put "formatted" r 16.6 COUNT 16.6 PERCENT 16.6 CUM_FREQ 16.6 CUM_PCT 16.6; run;
proc freq data=d order=internal noprint; weight w; tables r / missing outcum out=result; run;
data _null_; set result; file print; put "internal" r 16.6 COUNT 16.6 PERCENT 16.6 CUM_FREQ 16.6 CUM_PCT 16.6; run;
data neg; input r c w; datalines;
1 1 5
1 2 -1
2 1 3
2 2 2
3 1 1
3 1 -1
;
run;
proc freq data=neg noprint; weight w; tables r / outcum out=result; run;
data _null_; set result; file print; put "NEG1" r 16.6 COUNT 16.6 PERCENT 16.6 CUM_FREQ 16.6 CUM_PCT 16.6; run;
proc freq data=neg noprint; weight w; tables r*c / outpct outexpect out=result; run;
data _null_; set result; file print; put "NEG2" r 16.6 c 16.6 COUNT 16.6 EXPECTED 16.6 PERCENT 16.6 PCT_ROW 16.6 PCT_COL 16.6; run;
data ranges; x1=1; x2=2; x3=3; x4=4; run;
proc freq data=ranges noprint; tables (x1-x2)*(x3--x4) / out=result; run;
data _null_; set result; file print; put "LAST" x2 16.6 x4 16.6 COUNT 16.6 PERCENT 16.6; run;
proc freq data=d noprint; by g; weight w; tables r*c / outpct outexpect out=result; run;
data _null_; set result; file print; put "BY" g 16.6 r 16.6 c 16.6 COUNT 16.6 EXPECTED 16.6 PERCENT 16.6 PCT_ROW 16.6 PCT_COL 16.6; run;
proc freq data=d noprint;weight w;format w 8.1;tables w / out=result;run;
data _null_;set result;file print;put 'WEIGHTVAR' w 16.6 COUNT 16.6 PERCENT 16.6;run;
