options nodate nonumber linesize=160 pagesize=max nostimer nofullstimer;
data probe;
  input x g z target;
  datalines;
1 0 1 2
2 0 2 1
3 0 3 5
4 0 4 3
5 1 5 7
6 1 6 2
7 1 7 6
8 1 9 4
;
run;
data three;
  input x g;
  datalines;
1 1
3 1
5 1
2 2
4 2
6 2
3 3
5 3
8 3
;
run;
data many;
  do g=1 to 21;
    do i=1 to 3;
      x=mod(g*7+i*11,31);
      output;
    end;
  end;
run;
data twobytwo;
  input shape r c w;
  datalines;
1 1 1 0
1 1 2 5
1 2 1 5
1 2 2 10
2 1 1 0
2 1 2 9
2 2 1 11
2 2 2 3
3 1 1 5
3 1 2 0
3 2 1 10
3 2 2 5
4 1 1 0
4 1 2 4
4 2 1 8
4 2 2 12
5 1 1 1
5 1 2 9
5 2 1 11
5 2 2 3
;
run;

%put OPTIONCASE serial_ngroups_two;
data _null_; file print; put "OPTIONCASE serial_ngroups_two"; run;
proc corr data=three polyserial(ngroups=2) nosimple; var x; with g; run;
