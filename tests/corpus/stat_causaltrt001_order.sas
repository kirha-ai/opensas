/*
 * STAT-CAUSALTRT-001: ORDER= (CLASS levels; FREQ ties in formatted order) and RORDER= (outcome levels); neither reorders the treatment; the outcome-event hint note when no EVENT=/REF=/DESCENDING chose the event.
 * Trial rows: the SAS 9.4 output of the invented generator in
 * stat_causaltrt001_ipwr.sas. Expected listing: SAS 9.4 (batched real-SAS
 * runs, 2026-11-28), titles name each case.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data trial;
  length s $100;
  input s $100.;
  do k=1 to 50;
    id=(_n_-1)*50+k; age=20+mod(id*7,45); bmi=20+mod(id,12); gender=mod(id,2);
    drug=input(substr(s,2*k-1,1),1.); outcome=input(substr(s,2*k,1),1.);
    output;
  end;
  keep id age bmi gender drug outcome;
datalines;
1000000010010011111110101100010000110110111010010111000001010111000010010100001000001101000110000100
0100001000010000101000110011101000110001100000000000101101001001001000000000000100000101101000000011
0001001010011100010110000111111000010000100101100010100100010001100000000110010111100001101001001001
0011101001000011100101000111111000000000100110010100010010100000010001000111000100111001101111100001
;
run;




proc format; value yf 0='zz' 1='aa'; run;
data p; set trial; outcome=1-outcome; drug=1-drug; run;
data b; set trial; if id<0; run;
data t4; set trial; g=1-gender; format g gf.; run;
data p2; set trial; outcome=1-outcome; run;
/* CASE E order data and freq */
proc format; value gf 0='zz' 1='aa'; run;
data e; set trial; g3=mod(id,3); if id=1 then g3=2; format gender gf.; run;
proc causaltrt data=e method=ipwr order=data; class gender g3; psmodel drug(ref='0')=age gender g3; model outcome(ref='0') /dist=bin; run;
proc causaltrt data=e method=ipwr order=freq; class gender g3; psmodel drug(ref='0')=age gender g3; model outcome(ref='0') /dist=bin; run;
proc causaltrt data=e method=ipwr order=internal; class gender g3; psmodel drug(ref='0')=age gender g3; model outcome(ref='0') /dist=bin; run;
proc causaltrt data=e method=ipwr; class gender g3; psmodel drug(ref='0')=age gender g3; model outcome(ref='0') /dist=bin; run;
/* CASE F4 freq tie */
proc causaltrt data=t4 method=ipwr order=freq; class g; psmodel drug(ref='0')=age g; model outcome(ref='0') /dist=bin; run;
/* CASE P rorder=data no ref */
proc causaltrt data=p method=ipwr rorder=data; class gender; psmodel drug=age bmi gender; model outcome /dist=bin; run;
/* CASE Q order=data no ref */
proc causaltrt data=p method=ipwr order=data; class gender; psmodel drug=age bmi gender; model outcome /dist=bin; run;
/* CASE R rorder=internal formatted */
data r; set trial; format outcome drug yf.; run;
proc causaltrt data=r method=ipwr rorder=internal; class gender; psmodel drug=age bmi gender; model outcome /dist=bin; run;
/* CASE S default formatted */
proc causaltrt data=r method=ipwr; class gender; psmodel drug=age bmi gender; model outcome /dist=bin; run;
/* CASE T order=internal formatted */
proc causaltrt data=r method=ipwr order=internal; class gender; psmodel drug=age bmi gender; model outcome /dist=bin; run;
/* CASE U rorder=freq formatted */
proc causaltrt data=r method=ipwr rorder=freq; class gender; psmodel drug=age bmi gender; model outcome /dist=bin; run;
/* CASE W descending rorder=data */
proc causaltrt data=p method=ipwr rorder=data descending; class gender; psmodel drug=age bmi gender; model outcome /dist=bin; run;
/* CASE X order=freq treatment */
proc causaltrt data=r method=ipwr order=freq; class gender; psmodel drug=age bmi gender; model outcome /dist=bin; run;
/* CASE A2 order=data treatment first obs drug=1 */
proc causaltrt data=p2 method=ipwr order=data rorder=data; class gender; psmodel drug=age bmi gender; model outcome /dist=bin; run;
/* CASE B2 outcome desc var option */
proc causaltrt data=trial method=ipwr; class gender; psmodel drug=age bmi gender; model outcome(desc) /dist=bin; run;
/* CASE E2 treatment desc */
proc causaltrt data=trial method=ipwr; class gender; psmodel drug(desc)=age bmi gender; model outcome(ref=first) /dist=bin; run;
