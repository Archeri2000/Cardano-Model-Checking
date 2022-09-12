// Alice will call this
mtype = {DistributeAssets, Invalid, ReceiveEarnings, ReceiveItem}

// Bob and Charlie will call this
mtype = {BidHigher, BidLower}

chan ToAlice = [1] of mtype;

chan ToBob = [1] of mtype;

chan ToCharlie = [1] of mtype;

chan ToContract = [1] of mtype;



active proctype Alice(){

}

active proctype Bob(){

}

active proctype Charlie(){

}

active proctype Contract(){
    
}