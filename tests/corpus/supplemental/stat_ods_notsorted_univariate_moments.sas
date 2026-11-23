data sample;
input g a b c;
datalines;
1 1 2 4
1 2 3 1
1 2 2 5
1 4 7 3
1 5 4 2
1 7 9 8
1 8 5 5
2 2 4 2
2 3 1 7
2 3 8 4
2 5 7 5
2 6 6 2
2 8 2 4
2 . 5 6
;
run;
data grouped;
length Arm 8;
label Arm='Study arm';
format Arm z2.;
informat Arm 2.;
set sample(in=firstpart) sample(in=mid) sample(in=lastpart);
if firstpart then Arm=2;
if mid then Arm=1;
if lastpart then Arm=2;
if mid then do;
  if a=8 then delete;
  if c>5 then b=.;
end;
if lastpart then do;
  if a=2 then delete;
  a=a+4;
end;
run;
ods output Moments=captured;
proc univariate data=grouped; by Arm notsorted; var a;
run;
data _null_;
  length line $512 nm $32 kind $4 fmt infmt $49 lab $256;
  id=open('work.captured','i');
  if id>0 then do;
    n=attrn(id,'NLOBS');
    line=cats('ODS_ROWS|',put(n,best12.));
    put line;
    do pos=1 to attrn(id,'NVARS');
      nm=varname(id,pos);
      if vartype(id,pos)='C' then kind='char';
      else kind='num';
      width=varlen(id,pos);
      fmt=varfmt(id,pos);
      infmt=varinfmt(id,pos);
      lab=varlabel(id,pos);
      line=cats('ODS_COL|',put(pos,best12.),'|',nm,'|',kind,'|',put(width,best12.),'|',fmt,'|',infmt,'|',lab);
      put line;
    end;
    rc=close(id);
  end;
run;

data _null_;
  length line $512 text $256;
  id=open('work.captured','i');
  if id>0 then do;
    do row=1 to attrn(id,'NLOBS');
      rc=fetchobs(id,row);
      do pos=1 to attrn(id,'NVARS');
        if vartype(id,pos)='N' then text=put(getvarn(id,pos),best32.);
        else text=getvarc(id,pos);
        line=cats('ODS_VALUE|',put(row,best12.),'|',varname(id,pos),'|',text);
        put line;
      end;
    end;
    rc=close(id);
  end;
run;
