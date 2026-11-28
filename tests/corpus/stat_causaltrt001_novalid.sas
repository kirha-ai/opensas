/* expect-rc: 1
 * STAT-CAUSALTRT-001: empty input, a BY group without usable observations, all FREQ values 0, and a repeated DATA= (the second is ignored with a warning): SAS prints Model Information, then ERROR No valid observations; other BY groups are still analysed.
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

data b; set trial; if id<0; run;
data c; set trial; grp=(id>100); if grp=0 then outcome=.; run;
data l; set trial; f=0; run;
/* CASE B empty */
data b; set trial; if id<0; run;
proc causaltrt data=b method=ipwr; class gender; psmodel drug(ref='0')=age bmi gender; model outcome(ref='0') /dist=bin; run;
/* CASE C by group no usable obs */
data c; set trial; grp=(id>100); if grp=0 then outcome=.; run;
proc causaltrt data=c method=ipwr; by grp; class gender; psmodel drug(ref='0')=age bmi gender; model outcome(ref='0') /dist=bin; run;
/* CASE L all freq zero */
data l; set trial; f=0; run;
proc causaltrt data=l method=ipwr; class gender; psmodel drug(ref='0')=age bmi gender; model outcome(ref='0') /dist=bin; freq f; run;
/* CASE V data repeated */
proc causaltrt data=b data=trial method=ipwr; class gender; psmodel drug(ref='0')=age bmi gender; model outcome(ref='0') /dist=bin; run;
