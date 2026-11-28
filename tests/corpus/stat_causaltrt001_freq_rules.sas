/*
 * STAT-CAUSALTRT-001: FREQ values below 1, missing or fractional (p.2450): such observations are not used and are left out of both Sum of Frequencies lines; 2.7 truncates to 2.
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

/* CASE A freq 0 missing fraction negative */
data a; set trial; f=1+mod(id,3); if id=3 then f=0; if id=4 then f=.; if id=6 then f=0.5; if id=7 then f=-1; if id=8 then f=2.7; run;
proc causaltrt data=a method=ipw; class gender; psmodel drug(ref='0')=age bmi gender; model outcome(ref='0') /dist=bin; freq f; run;
