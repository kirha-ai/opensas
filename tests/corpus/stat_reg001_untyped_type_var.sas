/* STAT-REG-001: the data set TYPE= attribute, not a _TYPE_ variable, decides
 * whether PROC REG reads summary input (Input Data Sets, S154 p. 8589).
 * Verified token-for-token against a SAS 9.4 run of this program (SAS also
 * logs "WARNING: The variable _NAME_ or _TYPE_ exists in a data set that is
 * not TYPE=CORR, COV, SSCP, etc." for both fits; opensas does not log it).
 *  1. PROC MEANS OUT= has a blank TYPE: REG fits its rows (with _TYPE_ as an
 *     ordinary regressor) as raw observations.
 *  2. A DATA step copy of a CORR OUTP= set has a blank TYPE: SAS fits its
 *     MEAN/STD/N/CORR rows as five raw observations.
 *  3. TYPE= written by a DATA step, overridden on CORR OUTP=, and kept by
 *     PROC SORT OUT= (ATTRC 'TYPE').
 * Invented data.
 */
data a; input g x y @@; datalines;
1 1 2 1 2 4 1 3 7 2 4 8 2 5 11 3 6 12 3 7 13 3 8 17 3 9 18
;
run;
proc means data=a noprint; class g; var x y; output out=m mean=mx my; run;
proc reg data=m; model my = mx _type_; run; quit;
proc corr data=a outp=c noprint; var x y; run;
data u; set c; run;
proc reg data=u; model y = x; run; quit;
data u2(type=corr); set c; run;
data _null_; file print; id=open('u2'); t=attrc(id,'TYPE'); rc=close(id); put 'TYPE u2 ' t=; run;
proc corr data=a outp=c2(type=cov) noprint; var x y; run;
data _null_; file print; id=open('c2'); t=attrc(id,'TYPE'); rc=close(id); put 'TYPE c2 ' t=; run;
proc sort data=c out=cs; by _type_; run;
data _null_; file print; id=open('cs'); t=attrc(id,'TYPE'); rc=close(id); put 'TYPE cs ' t=; run;
data _null_; file print; id=open('c'); t=attrc(id,'TYPE'); rc=close(id); put 'TYPE c ' t=; run;
data _null_; file print; id=open('u'); t=attrc(id,'TYPE'); rc=close(id); put 'TYPE u ' t=; run;
