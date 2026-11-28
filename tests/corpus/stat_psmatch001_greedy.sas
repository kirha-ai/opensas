/* expect-rc: 1
 * STAT-PSMATCH-001: PROC PSMATCH REGION=CS, CLASS, PSMODEL main effects,
 * greedy nearest neighbor matching (descending PS, K=1, CALIPER=0.5),
 * ASSESS LPS VAR=, OUTPUT OUT(OBS=MATCH)= MATCHID=. The program is the
 * STAT-PSMATCH-001 oracle case with one change: the treatment draws of
 * RAND('BERNOULLI',0.5) after CALL STREAMINIT(419) are written out as a bit
 * string (exported from SAS 9.4, invented data otherwise), because the opensas
 * seeded Bernoulli stream differs from SAS. _PS_ is printed with an explicit
 * 7.5 format (the SAS listing shows 0.53630; PROC PRINT's default numeric
 * layout is STAT-PRINT-001). Every listing token is the SAS reference text;
 * rc 1 comes from the documented not-enough-controls WARNING.
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
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
proc psmatch data=patients region=cs;
class drug gender;
psmodel drug(treated='1')=gender age bmi;
match method=greedy(k=1) distance=lps caliper=0.5;
assess lps var=(age bmi);
output out(obs=match)=matched matchid=matchid;
run;
proc print data=matched(obs=10) noobs;
format _ps_ 7.5;
run;
