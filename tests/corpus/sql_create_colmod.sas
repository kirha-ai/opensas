/* BUG-sqlddlmed: CREATE TABLE column modifiers format=/informat=/label= were
   silently dropped — the created column carried no format/label. They now
   attach to the column like a data-step ATTRIB; CONTENTS shows them. */
proc sql;
  create table t (amt num format=dollar8.2 label='Amount', dt num format=date9.);
quit;
proc contents data=t; run;
