chan FromAlice [1]
chan FromBob [1]
chan ToAlice [1]
chan ToBob [1]

active proctype Alice(){

}

active proctype Bob(){

}

active proctype Contract(){
    initContract:
    do
    :: -> 
    ::true -> goto timedOut
    od
    timedOut:
    do

    od
}