/* expect-rc: 1
 * STAT-PSMATCH-001: observation selection and ORDER=ASCENDING. Rows with a
 * missing PSMODEL covariate or a missing treatment value are excluded from
 * every count; greedy matching in ascending PS order leaves treated units
 * unmatched by the caliper, which SAS reports with the not-enough-controls
 * WARNING (rc 1). The treatment bits were exported from SAS 9.4 (see
 * stat_psmatch001_greedy.sas). Every token is the SAS 9.4 listing of this
 * same program.
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
grp=(patientid>50);
output;
end;
drop bits;
run;
data pmiss; set patients end=e; output; if e then do; patientid=101; age=.; drug=1; output; patientid=102; age=40; drug=.; output; end; run;
title 'MISS';
proc psmatch data=pmiss region=cs;
class drug gender;
psmodel drug(treated='1')=gender age bmi;
match method=greedy(k=1 order=ascending) distance=lps caliper=0.5;
assess lps var=(age bmi);
output out(obs=match)=m2 matchid=mid;
run;
proc print data=m2(firstobs=1 obs=6) noobs; format _ps_ 7.5; run;
