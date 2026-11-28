/* expect-rc: 1
 * STAT-CAUSALTRT-001: treatment/outcome level errors: SAS prints Model Information and then the error (three-level outcome or treatment, constant treatment or outcome, absent REF=/EVENT= level).
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

data o1; set trial; outcome=0; run;
data k; set trial; if drug=1; run;
data j3; set trial; if id=10 then drug=2; run;
/* CASE J three-level outcome */
data j; set trial; if id=10 then outcome=2; run;
proc causaltrt data=j method=ipwr; class gender; psmodel drug(ref='0')=age bmi gender; model outcome(ref='0') /dist=bin; run;
/* CASE K one treatment level */
data k; set trial; if drug=1; run;
proc causaltrt data=k method=ipwr; class gender; psmodel drug(ref='0')=age bmi gender; model outcome(ref='0') /dist=bin; run;
/* CASE K4 one level no ref */
proc causaltrt data=k method=ipwr; class gender; psmodel drug=age bmi gender; model outcome(ref='0') /dist=bin; run;
/* CASE J4 three level treatment */
proc causaltrt data=j3 method=ipwr; class gender; psmodel drug=age bmi gender; model outcome(ref='0') /dist=bin; run;
/* CASE L4 bad outcome event */
proc causaltrt data=trial method=ipwr; class gender; psmodel drug(ref='0')=age bmi gender; model outcome(event='7') /dist=bin; run;
/* CASE O1 constant outcome */
proc causaltrt data=o1 method=ipwr; class gender; psmodel drug(ref='0')=age bmi gender; model outcome /dist=bin; run;
