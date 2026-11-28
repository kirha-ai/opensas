/* expect-rc: 1
 * STAT-STEPDISC-001: BY groups (PDF pp.9563-9564). Two BY groups hold the
 * same SASHELP.FISH rows, so each group repeats the full listing under its
 * own BY line and repeats the missing-value WARNINGs with its own counts.
 * Expected listing is the SAS 9.4 output, minus the blank line SAS writes
 * before the first page (opensas convention).
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title 'Fish Measurement Data';
data _oracle_input; set sashelp.fish; do _oracle_by=1 to 2; output; end; run;
proc sort data=_oracle_input; by _oracle_by; run;
proc stepdisc data=_oracle_input;
by _oracle_by;
class Species;
run;
