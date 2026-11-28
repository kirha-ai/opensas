/* STAT-CAUSALGRAPH-008 (Time Requirements, p.2331): NOSORT is ignored with
 * one warning under MAXSIZE=MIN (checked first, also with NOLIST, NOPRINT or
 * MAXLIST=1), else under METHOD=IV (also with NOLIST). Warning texts and
 * their presence are those of SAS 9.4 reference runs (2026-11-28); the
 * listings of these steps are compared in stat_causalgraph008_nosort.
 * Invented graphs.
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
proc causalgraph nosort maxsize=min; model 'MM' X ==> Y, A ==> X B, B ==> Y, C ==> X Y; identify X ==> Y; run;
proc causalgraph nosort maxsize=min nolist; model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X; identify X ==> Y; run;
proc causalgraph nosort maxsize=min noprint; model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X; identify X ==> Y; run;
proc causalgraph nosort maxlist=1 maxsize=min; model 'S' X ==> Y, Z ==> X Y, W ==> Y, V ==> X; identify X ==> Y; run;
proc causalgraph nosort maxlist=1 method=iv; model 'V' I ==> X, X ==> Y, U ==> X Y; identify X ==> Y; unmeasured U; run;
proc causalgraph nosort method=iv nolist; model 'V' I ==> X, X ==> Y, U ==> X Y; identify X ==> Y; unmeasured U; run;
proc causalgraph nosort maxlist=2; model 'S' X ==> Y, Z ==> X Y; identify X ==> Y; run;
