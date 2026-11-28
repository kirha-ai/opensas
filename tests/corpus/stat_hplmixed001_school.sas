/* expect-rc: 2
 * STAT-HPLMIXED-001: random-coefficients school model (S154 Chapter 60
 * Getting Started shape: 60000 RANUNI/RANNOR observations, CLASS, MODEL
 * SOLUTION, RANDOM INT TIME TIME*TIME SUB=NEIGHBORHOOD(SCHOOLID) TYPE=UN).
 * Expected listing words are the SAS 9.4 reference listing with two
 * documented differences: Number of Threads is opensas's own 1 (machine
 * specific, STAT-HP-002), and the Iteration History table with its
 * convergence line is absent; that omission is a loud gap (ERROR, rc 2),
 * because its Max Gradient is SAS's round-off at its own starting values.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
ods graphics off;
data SchoolSample;
do SchoolID = 1 to 300;
do nID = 1 to 25;
Neighborhood = (SchoolID-1)*5 + nId;
bInt = 5 *ranuni(1);
bTime = 5 *ranuni(1);
bTime2 = ranuni(1);
do sID = 1 to 2;
do Time = 1 to 4;
Math = bInt + bTime*Time + bTime2*Time*Time + rannor(2);
output;
end;
end;
end;
end;
run;
proc hplmixed data=SchoolSample;
class Neighborhood SchoolID;
model Math = Time Time*Time / solution;
random int Time Time *Time / sub=Neighborhood(SchoolID) type=un;
run;
