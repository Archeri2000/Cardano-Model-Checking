// Bob playing
mtype = {PlayWin, PlayLose};

// Claim Winnings
mtype = {Claim, ClaimSuccess, ClaimFail, Refund};

// Alice can Claim
chan FromAlice = [1] of {mtype};

// Bob can PlayWin, PlayLose, Claim
chan FromBob = [1] of {mtype};

// System can reply Alice with ClaimSuccess or ClaimFail or Refund
chan ToAlice = [1] of {mtype};

// System can reply Bob with ClaimSuccess or ClaimFail
chan ToBob = [1] of {mtype};

active proctype Alice(){
    xs FromAlice;
    xr ToAlice;
    do
    ::true -> 
        FromAlice!Claim;
        if
        ::ToAlice?ClaimSuccess -> goto end_alice;
        ::ToAlice?ClaimFail -> skip;
        ::ToAlice?Refund -> goto end_alice;
        fi
    ::true
    od;
    end_alice:
    true;

    //gotta do something here to check the results?
}

active proctype Bob(){
    xs FromBob;
    xr ToBob;
    do
    ::true ->
        FromBob!Claim;
        if
        ::ToBob?ClaimSuccess -> goto end_bob;
        ::ToBob?ClaimFail -> skip;
        fi
    ::true ->
        FromBob!PlayWin;
    ::true ->
        FromBob!PlayLose;
    ::true
    od;
    end_bob:
    true;
}

active proctype Contract(){
    xs ToAlice;
    xr FromAlice;
    xs ToBob;
    xr FromBob;
    mtype message;
    do
    ::FromBob?Claim -> ToBob!ClaimFail;
    ::FromBob?PlayWin -> goto BobWin;
    ::FromBob?PlayLose -> goto AliceWin;
    ::FromAlice?Claim -> ToAlice!ClaimFail; 
    ::true -> skip;
    ::true -> goto timedOut;
    od;

    timedOut:
    do
    ::FromBob?PlayWin -> skip;
    ::FromBob?PlayLose -> skip;
    ::FromBob?Claim -> ToBob!ClaimFail;
    ::FromAlice?Claim -> 
        ToAlice!Refund;
        goto end; 
    od;

    BobWin:
    do
    ::FromBob?PlayWin -> skip;
    ::FromBob?PlayLose -> skip;
    ::FromBob?Claim -> 
        ToBob!ClaimSuccess;
        goto end;
    ::FromAlice?Claim -> ToAlice!ClaimFail; 
    od;

    AliceWin:
    do
    ::FromBob?PlayWin -> skip;
    ::FromBob?PlayLose -> skip;
    ::FromBob?Claim -> ToBob!ClaimFail;
    ::FromAlice?Claim -> 
        ToAlice!ClaimSuccess;
        goto end; 
    od;

    end:
    true;
}