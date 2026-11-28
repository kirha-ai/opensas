/* expect-rc: 1
 * STAT-PSMATCH-001: REGION= variants with greedy matching on the
 * STAT-PSMATCH-001 data (treatment bits exported from SAS 9.4, as in
 * stat_psmatch001_greedy.sas): default REGION=TREATED, TREATED(EXTEND=),
 * CS(EXTEND=0) "Common Support", EXTEND(MULT=ONE), EXTEND(DISTANCE=PS ...),
 * LOWER=/UPPER=, ALLOBS and ALLOBS(PSMIN= PSMAX=). The expected listing is
 * the token stream of a SAS 9.4 run of this exact program (SAS adds a blank
 * line before each page title); rc 1 from the documented
 * not-enough-controls WARNING (once per step).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
ods graphics off;
data patients;
length bits $100;
bits='1000111111111110011110110000011000000011100111001010010000100010010110111111001111011101101110100000';
do patientid=1 to 100;
gender=mod(patientid,2);
age=30+mod(patientid*7,45);
bmi=20+mod(patientid,12);
drug=input(substr(bits,patientid,1),1.);
output;
end;
drop bits;
run;
%macro r(reg);
title "REG=&reg";
proc psmatch data=patients &reg;
class drug gender;
psmodel drug(treated='1')=gender age bmi;
match method=greedy(k=1) distance=lps caliper=0.5;
assess lps var=(age bmi);
run;
%mend;
%r();
%r(%str(region=treated));
%r(%str(region=cs(extend=0)));
%r(%str(region=treated(extend=0.1)));
%r(%str(region=cs(extend(mult=one)=0.1)));
%r(%str(region=cs(extend(distance=ps mult=one)=0.01)));
%r(%str(region=cs(extend(distance=ps)=0.25)));
%r(%str(region=cs(extend=0.25(lower=0 upper=0.5))));
%r(%str(region=cs(extend=0.25(upper=0.5))));
%r(%str(region=allobs));
%r(%str(region=allobs(psmin=0.4 psmax=0.65)));
