/* QA tick312 — pins the Language Reference: Concepts p.74 rule ("Example:
   Drop and Rename Variables") on the interaction BUG-renamestmtmultiout
   (6481ea65) made reachable: a statement-form RENAME relabels EVERY output
   data set (Language Reference: Concepts Table 4.7 p.73), and because the
   RENAME statement is applied BEFORE the output data set options ("Order of
   Application", p.73-74), an output DROP=/KEEP=/WHERE= must name the NEW
   variable — p.74 notes explicitly that the renamed name is the one used in
   the DROP= data set option.
   Pre-fix this program was silently wrong: the second split set kept the old
   name, the remainder set kept the old name and did not drop it, plus a bogus
   "<newname> ... never been referenced" WARNING. */
data shipments;
  input lane weight;
  datalines;
1 410
2 520
3 630
1 415
;
run;

data lane1 lane2 rest(drop=kg);
   set shipments;
   if lane=1 then output lane1;
   else if lane=2 then output lane2;
   else output rest;
   rename weight=kg;
run;
proc print data=lane1 noobs; run;
proc print data=lane2 noobs; run;
proc print data=rest noobs; run;
