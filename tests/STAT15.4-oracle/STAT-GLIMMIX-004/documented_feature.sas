/* STAT-GLIMMIX-004: GLIMMIX — CLASS / EFFECT / MODEL
 * Source: S154 / Chapter 52 / `CLASS Statement` (PDF pp. 3731–3732); S154 / Chapter 52 / `EFFECT Statement` (PDF p. 3744); S154 / Chapter 52 / `MODEL Statement` (PDF pp. 3772–3786).
 * Discriminates: Example 52.16: Diallel Experiment with Multimember Random Effects; explicit statements: CLASS, EFFECT, MODEL
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

data diallel;
label time = 'Flowering time in days';
do p = 1 to 8;
do m = 1 to 8;
if (m ne p) then do;
sym = trim(left(min(m,p))) || ',' || trim(left(max(m,p)));
do block = 1 to 2;
input time @@;
output;
end;
end;
end;
end;
datalines;
14.4 16.2 27.2 30.8 17.2 27.0 18.3 20.2 16.2 16.8 18.6 14.4 16.4 16.0
15.4 16.5 14.8 14.6 18.6 18.6 15.2 15.3 17.0 15.2 14.4 14.8 10.8 13.2
31.8 30.4 21.0 23.0 24.6 25.4 19.2 20.0 29.8 28.4 12.8 14.2 13.0 14.4
16.2 17.8 11.4 13.0 16.8 16.3 12.4 14.2 16.8 14.8 12.6 12.2 9.6 11.2
14.6 18.8 12.2 13.6 15.2 15.4 15.2 13.8 18.0 16.0 10.4 12.2 13.4 20.0
20.2 23.4 14.2 14.0 18.6 14.8 22.2 17.0 14.3 17.3 9.0 10.2 11.8 12.8
14.0 16.6 12.2 9.2 13.6 16.2 13.8 14.4 15.6 15.6 15.6 11.0 13.0 9.8
15.2 17.2 10.0 11.6 17.0 18.2 20.8 20.8 20.0 17.4 17.0 12.6 13.0 9.8
;
proc glimmix data=diallel outdesign(z)=zmat;
class block sym p m;
effect line = mm(p m);
model time = block;
random line sym p m p*m;
run;
