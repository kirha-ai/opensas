/* STAT-COMMON-001 runtime foundation; SAS/STAT 15.4 physical pp. 13-36.
   Runtime identity is explicitly OpenSAS, not the reference SAS build.
   Compare both lookup paths without freezing a Git tag into the golden.
   Exercise DATA -> PRINT RUN/QUIT -> DATA execution; REG is separately owned. */
data runtime;
 length version $64;
 version=symget('sysvlong4');
 identified=(substr(version,1,8)='opensas ' and length(version)>8);
 same=(version="&sysvlong4");
 compatible=(symget('sysver')='9.4');
run;
proc print data=runtime noobs;
 var identified same compatible;
run;
quit;
data _null_;
 set runtime;
 if version=symget('SYSVLONG4') then put 'RUNTIME_AFTER_QUIT=ok';
 else put 'RUNTIME_AFTER_QUIT=bad';
run;
