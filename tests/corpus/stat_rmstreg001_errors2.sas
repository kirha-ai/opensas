/* expect-rc: 1
 * STAT-RMSTREG-001 close-out: documented invalid input, SAS 9.4 log texts of
 * this program (2026-11-28 batch); SAS prints no listing for any step:
 * an ascending BY out of order ("Data set WORK.SD is not sorted in
 * ascending sequence. The current BY group has g = 2 and the next BY group
 * has g = 1." -- the current group is not analysed); ALPHA=1.5 and MODEL
 * ALPHA=2 ("... not within the required range of 0 and 1."); NAMELEN=10
 * and 201 ("... of 20 and 200."); SINGULAR=2; a character FREQ variable
 * ("Variable c in list does not match type prescribed for this list.");
 * TAU=0 ("The TAU= value must be positive."); NAMELEN=25.5 ("ERROR
 * 22-322: Expecting an integer constant."); BY x g with g out of order
 * (only g is named in the message). Invented data.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data d;
do id=1 to 60;
age=25+mod(id*7,40);
x=mod(id,2);
time=round(exp(0.5+0.15*x+0.01*age+0.7*sin(id*1.7)),0.001);
status=(mod(id,4) ne 0);
g=mod(id,3);
length c $2; c='a';
output;
end;
run;
proc sort data=d out=sd; by descending g; run;
proc rmstreg data=sd tau=4; by g; model time*status(0)=age x / link=linear; run;
proc rmstreg data=d tau=4 alpha=1.5; model time*status(0)=age x / link=linear; run;
proc rmstreg data=d tau=4; model time*status(0)=age x / link=linear alpha=2; run;
proc rmstreg data=d tau=4 namelen=10; model time*status(0)=age x / link=linear; run;
proc rmstreg data=d tau=4 namelen=201; model time*status(0)=age x / link=linear; run;
proc rmstreg data=d tau=4 singular=2; model time*status(0)=age x / link=linear; run;
proc rmstreg data=d tau=4; freq c; model time*status(0)=age x / link=linear; run;
proc rmstreg data=d tau=0; model time*status(0)=age x / link=linear; run;
proc rmstreg data=d tau=4 namelen=25.5; model time*status(0)=age x / link=linear; run;
proc sort data=d out=sx; by x; run;
proc rmstreg data=sx tau=4; by x g; model time*status(0)=age / link=linear; run;
