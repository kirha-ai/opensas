/* PROC DATASETS MODIFY attribute clean-up, the SDTM pre-XPORT idiom.
   BUG-datasetsstrip pinned the FORMAT half; BUG-datasetsinformatstrip (GH#79
   part 2) adds the INFORMAT half, which this fixture could not catch before
   because no column carried an informat. `attrib _all_ informat=;` was a
   hard-coded no-op at rc 0: the Format column emptied and the Informat column
   kept every old spec, so a "stripped" dataset still advertised them to
   CONTENTS and to the .xpt descriptor. Base SAS 9.4 Procedures Guide, 7th ed.
   p.598 — inside DATASETS, ATTRIB takes only FORMAT/INFORMAT/LABEL; p.641 —
   "To remove all informats from a data set, use the ATTRIB statement ... and
   the _ALL_ keyword". vs2 is the negative control: a named-variable strip must
   leave the other variable's informat alone. */
data vs;
  x = 1; format x dollar8.2; informat x comma8.;
  y = 2; format y comma6.;   informat y best12.;
  label x = "Systolic";
run;
data vs2;
  a = 1; informat a comma8.;
  b = 2; informat b best12.;
run;
proc datasets library=work nolist;
  modify vs (label='Vital Signs');
  attrib _all_ format=;
  attrib _all_ informat=;
quit;
proc datasets library=work nolist;
  modify vs2;
  attrib a informat=;
quit;
proc contents data=vs; run;
proc contents data=vs2; run;
