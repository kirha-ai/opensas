/* STAT-MULTTEST-007: MULTTEST — ODS Graphics
 * Source: S154 / Chapter 86 / `ODS Graphics` (PDF pp. 6935–6936).
 * Discriminates: Example 86.6: Adaptive Adjustments and ODS Graphics
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

ods graphics on;
ods trace on;
ods trace on;
data test;
length Probe_Set_ID $9.;
input Probe_Set_ID $ Probt @@;
datalines;
200973_s_ .963316 201059_at .462754 201563_at .000409 201733_at .000819
201951_at .000252 202944_at .106550 203107_x_ .040396 203372_s_ .010911
203469_s_ .987234 203641_s_ .019296 203795_s_ .002276 204055_s_ .002328
205020_s_ .008628 205199_at .608129 205373_at .005209 205384_at .742381
205428_s_ .870533 205653_at .621671 205686_s_ .396440 205760_s_ .000002
206032_at .024661 206159_at .997627 206223_at .003702 206398_s_ .191682
206623_at .010030 206852_at .000004 207072_at .000214 207371_at .000013
207789_s_ .023623 207861_at .000002 207897_at .000007 208022_s_ .251999
208086_s_ .000361 208406_s_ .040182 208464_at .161468 209055_s_ .529824
209125_at .142276 209369_at .240079 209748_at .071750 209894_at .000042
209906_at .223282 210130_s_ .192187 210199_at .101623 210477_x_ .300038
210491_at .000078 210531_at .000784 210734_x_ .202931 210755_at .009644
210782_x_ .000011 211320_s_ .022896 211329_x_ .486869 211362_s_ .881798
211369_at .000030 211399_at .000008 211572_s_ .269788 211647_x_ .001301
213072_at .005019 213143_at .008711 213238_at .004824 213391_at .316133
213468_at .000172 213636_at .097133 213823_at .001678 213854_at .001921
213976_at .000299 214006_s_ .014616 214063_s_ .000361 214407_x_ .609880
214445_at .000009 214570_x_ .000002 214648_at .001255 214684_at .288156
214991_s_ .006695 215012_at .000499 215117_at .000136 215201_at .045235
215304_at .000816 215342_s_ .973786 215392_at .112937 215557_at .000007
215608_at .006204 215935_at .000027 215980_s_ .037382 216010_x_ .000354
216051_x_ .000003 216086_at .002310 216092_s_ .000056 216511_s_ .294776
216733_s_ .004823 216747_at .002902 216874_at .000117 216969_s_ .001614
217133_x_ .056851 217198_x_ .169196 217557_s_ .002966 217738_at .000005
218601_at .023817 218818_at .027554 219302_s_ .000039 219441_s_ .000172
219574_at .193737 219612_s_ .000075 219697_at .046476 219700_at .003049
219945_at .000066 219964_at .000684 220234_at .130064 220473_s_ .000017
220575_at .030223 220633_s_ .058460 220925_at .252465 221256_s_ .721731
221314_at .002307 221589_s_ .001810 221995_s_ .350859 222071_s_ .000062
222113_s_ .000023 222208_s_ .100961 222303_at .049265 37226_at .000749
60474_at .000423
run;
ods graphics on;
proc multtest inpvalues(Probt)=test plots=all seed=518498000
aholm ahoc afdr pfdr(positive) nopvalue;
id Probe_Set_ID;
run;
ods graphics off;
proc nlmixed data=test;
parameters pi0=0.5 a=.1 b=.1;
pi1= 1-pi0;
bounds 0 <= pi0 <= 1;
loglikelihood= log(pi0+pi1*pdf('beta',Probt,a,b));
model Probt ~ general(loglikelihood);
run;
proc multtest inpvalues(Probt)=test ptruenull=0.10
aholm ahoc afdr pfdr(positive) nopvalue;
id Probe_Set_ID;
run;
ods graphics on / labelmax=1000;
proc multtest inpvalues(Probt)=test afdr nopvalue
plots=Manhattan(label=obs vref=0.0001);
id Probe_Set_ID;
run;
ods graphics off;
ods graphics on;
proc multtest inpvalues(Probt)=test plots(sigonly=0.001)=PByTest
aholm ahoc afdr pfdr(positive) nopvalue;
run;
ods graphics off;
run;
quit;
ods trace off;
ods trace off;
ods graphics off;
