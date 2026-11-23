data probe; input x y w; datalines;
-9.5 0 4
-3.0 0 1
-2.875 1 5
-2.625 1 2
-0.5 1 1
1.625 1 5
1.875 1 2
2.375 1 1
6.625 1 5
8.875 1 2
;
run;

%macro fit(id,scale,freq,converge,iter);
data sample; set probe; x=x*&scale; w=w*&freq; run;
proc corr data=sample outpls=fit polyserial(converge=&converge maxiter=&iter) nosimple;
var x; with y; freq w; run;
data _null_; set fit; file print;
if _TYPE_='CORR' then put "SERIAL &id " x best32.; run;

%mend;
%fit(perturb-0-sweep-1,1,1,0.00104538137878688,200);
%fit(perturb-0-sweep-2,1,1,0.0013938418383825,200);
%fit(perturb-0-sweep-3,1,1,0.00156807206818031,200);
%fit(perturb-0-sweep-4,1,1,0.00165518718307922,200);
%fit(perturb-0-sweep-5,1,1,0.00170745625201856,200);
%fit(perturb-0-sweep-6,1,1,0.00172487927499835,200);
%fit(perturb-0-sweep-7,1,1,0.00174055999568015,200);
%fit(perturb-0-sweep-8,1,1,0.00174230229797813,200);
%fit(perturb-0-sweep-9,1,1,0.0017440446002761,200);
%fit(perturb-0-sweep-10,1,1,0.00175972532095791,200);
%fit(perturb-0-sweep-11,1,1,0.00177714834393769,200);
%fit(perturb-0-sweep-12,1,1,0.00182941741287703,200);
%fit(perturb-0-sweep-13,1,1,0.00191653252777594,200);
%fit(perturb-0-sweep-14,1,1,0.00209076275757375,200);
%fit(perturb-0-sweep-15,1,1,0.00261345344696719,200);
%fit(perturb-0-first-m16,1,1,0.00174230229798,16);
%fit(perturb-0-first-m17,1,1,0.00174230229798,17);
%fit(perturb-0-first-step,1,1,0.999,1);
%fit(perturb-0-projection--1e-09,1,1,0.0017422364491687932,200);
%fit(perturb-0-projection--1e-11,1,1,0.0017422374391687931,200);
%fit(perturb-0-projection-1e-11,1,1,0.001742237459168793,200);
%fit(perturb-0-projection-1e-09,1,1,0.001742238449168793,200);
