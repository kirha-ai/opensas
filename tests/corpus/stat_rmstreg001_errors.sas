/* expect-rc: 1
 * STAT-RMSTREG-001: documented invalid input (SAS 9.4 reference logs).
 * A BY group without valid observations is an ERROR after the earlier
 * groups have printed ("No valid observations due to invalid or missing
 * values in the response, explanatory, or frequency variable."); TAU=-1 is
 * an ERROR ("The parameter value -1 is less than the minimum allowed value
 * of 0.") and prints nothing. Invented deterministic data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data h;
do id=1 to 60;
age=25+mod(id*7,40);
x=mod(id,2);
time=exp(0.5+0.15*x+0.01*age+0.7*sin(id*1.7));
status=(mod(id,4) ne 0);
length grp $3; grp=ifc(id<=30,'aa','bb'); if id>30 then age=.;
output;
end;
run;
proc rmstreg data=h tau=4; by grp; model time*status(0)=age x / link=linear; run;
proc rmstreg data=h tau=-1; model time*status(0)=age x; run;
