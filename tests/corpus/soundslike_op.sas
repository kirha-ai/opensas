data _null_;
  if 'Smith' =* 'Smythe' then put 'smith-smythe TRUE'; else put 'smith-smythe FALSE';
  if 'Smith' =* 'Jones' then put 'smith-jones TRUE'; else put 'smith-jones FALSE';
run;
data names;
  input id name $;
  datalines;
1 Smith
2 Smyth
3 Jones
4 Smithe
5 Schmidt
;
run;
data hit;
  set names;
  where name =* 'Smith';
run;
proc print data=hit noobs; run;
