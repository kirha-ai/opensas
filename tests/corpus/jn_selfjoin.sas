data emp; length name $6 dept $4; input name $ dept $; datalines;
Alice R&D
Bob R&D
Carol QA
Dave QA
Eve R&D
;
run;
data emp2; length name $6 dept $4; input name $ dept $; datalines;
Alice R&D
Bob R&D
Carol QA
Dave QA
Eve R&D
;
run;
proc sql;
  create table coworkers as
    select emp.name as p1, emp2.name as p2, emp.dept
    from emp inner join emp2 on emp.dept=emp2.dept
    where emp.name < emp2.name
    order by emp.dept, p1, p2;
quit;
proc print data=coworkers noobs; run;
