// Alice will call this
mtype = {DistributeAssets, Invalid, ReceiveEarnings, ReceiveItem};

// Bob and Charlie will call this
mtype = {BidHigher, BidLower, BidSuccess};


chan ToUser[3] = [1] of {mtype};

chan ToContract = [0] of {mtype, int};

proctype User(int id; bool isOwner){
    // If this user is supposed to be the owner, create the contract
    if
        ::isOwner -> run Contract(id);
        ::else -> skip;
    fi
    // Attempt to call all possible functions.
    do
        ::true ->
            if
                ::ToContract!DistributeAssets, id
                ::ToContract!BidHigher, id
                ::ToContract!BidLower, id
                ::true -> goto retry
            fi
            if
                ::ToUser[id]?Invalid ->
                    skip;
                ::ToUser[id]?BidSuccess ->
                    skip;
                ::ToUser[id]?ReceiveEarnings ->
                        goto end;
                ::ToUser[id]?ReceiveItem ->
                        goto end;
//                ::else -> skip;
            fi
            retry:
            skip
    od
    end:
    skip;
}

// active proctype Alice(){
//     run Contract(alice);
//     do
//         ::true ->
//             if
//             ::ToContract!DistributeAssets, alice
//             ::true -> goto retry_alice
//             fi

//             if
//                 ::ToAlice?ReceiveEarnings ->
//                     end_ownerPaid:
//                         goto end_alice;
//                 ::ToAlice?ReceiveItem ->
//                     end_ownerRefunded:
//                         goto end_alice;
//                 ::ToAlice?Invalid
// //                ::else -> skip;
//             fi
//         retry_alice:
//         skip
//     od
//     end_alice:
//     skip;
// }

// active proctype Bob(){
//     do
//         ::true ->
//             if
//                 ::ToContract!DistributeAssets, bob
//                 ::ToContract!BidHigher, bob
//                 ::ToContract!BidLower, bob
//                 ::true -> goto retry_bob
//             fi
//             if
//                 ::ToBob?Invalid ->
//                     skip;
//                 ::ToBob?BidSuccess ->
//                     progress_bob:
//                     skip;
//                 ::ToBob?ReceiveEarnings ->
//                     accept_InvalidState:
//                         goto end_bob;
//                 ::ToBob?ReceiveItem ->
//                     end_bobWon:
//                         goto end_bob;
// //                ::else -> skip;
//             fi
//         retry_bob:
//         skip
//     od
//     end_bob:
//     skip;
// }

// active proctype Charlie(){
//         do
//             ::true ->
//                 if
//                     ::ToContract!DistributeAssets, charlie
//                     ::ToContract!BidHigher, charlie
//                     ::ToContract!BidLower, charlie
//                     ::true -> goto retry_charlie
//                 fi
//                 if
//                     ::ToCharlie?Invalid ->
//                         skip;
//                     ::ToCharlie?BidSuccess ->
//                         progress_charlie:
//                         skip;
//                     ::ToCharlie?ReceiveEarnings ->
//                         accept_InvalidState:
//                             goto end_charlie;
//                     ::ToCharlie?ReceiveItem ->
//                         end_charlieWon:
//                             goto end_charlie;
// //                    ::else -> skip;
//                 fi
//         retry_charlie:
//         skip
//     od
//     end_charlie:
//     skip;
// }

proctype Contract(int ownerId){
    int highestBidder = -1;
    bool hasBid = false;
    int current = -1;
    do
        ::ToContract?BidHigher, current ->
            hasBid = true;
            highestBidder = current;
            ToUser[current]!BidSuccess;
            current = -1;
        ::ToContract?BidLower, current ->
            if
            // I'm not really sure about this case because I feel like it might complicate analysis later... Should we just "assume" that bid lower always fails? 
            // e.g. if there's a minimum price for the auction, then even if there's no current highest bidder, bid lower would fail.
            ::!hasBid ->
                hasBid = true;
                highestBidder = current;
                ToUser[current]!BidSuccess;
                current = -1;
            ::else ->
                ToUser[current]!Invalid;
                current = -1;
            fi
        ::ToContract?DistributeAssets, current ->
                ToUser[current]!Invalid;
                current = -1;
        //::true
        ::true -> goto auctionEnd;
    od

    // State when the auction has ended
    auctionEnd:
    do
        ::ToContract?DistributeAssets, _ ->
            if
                // If there's a highest bidder then the bidder should get the item and the contract owner should get the earnings.
                ::hasBid ->
                    ToUser[ownerId]!ReceiveEarnings;
                    ToUser[highestBidder]!ReceiveItem;
                    goto end_contract;
                // Otherwise the item is returned to the owner.
                ::else ->
                    ToUser[ownerId]!ReceiveItem;
                    goto end_contract;
            fi

        // Calling other functions after the auction has ended should fail.
        ::ToContract?BidHigher, current ->
            ToUser[current]!Invalid;
            current = -1;
        ::ToContract?BidLower, current ->
            ToUser[current]!Invalid;
            current = -1;
    od
    end_contract:
    skip;
}

init {
    run User(0, true);
    run User(1, false);
    run User(2, false);
}