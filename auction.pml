// Alice will call this
mtype = {DistributeAssets, Invalid, ReceiveEarnings, ReceiveItem};

// Bob and Charlie will call this
mtype = {BidHigher, BidLower, BidSuccess};

bool hasContract = false;

bool auctionFinish = false;

int usersWaiting = 0;

//chan ToUser[3] = [1] of {mtype};

chan ToContract = [0] of {mtype, int};

proctype User(int id; bool isOwner){
    // If this user is supposed to be the owner, create the contract
    if
        ::isOwner -> run Contract(id);
        ::else -> skip;
    fi
    // Attempt to call all possible functions.
    hasContract;
    do
        ::auctionFinish -> goto end;
        ::atomic{!auctionFinish -> 
                    usersWaiting++;
                    ToContract!DistributeAssets, id}
        ::atomic{!auctionFinish -> 
                    usersWaiting++;
                    ToContract!BidHigher, id}
        ::atomic{!auctionFinish -> 
                    usersWaiting++;
                    ToContract!BidLower, id;}
//             if
//                 ::ToUser[id]?Invalid ->
//                     skip;
//                 ::ToUser[id]?BidSuccess ->
//                     skip;
//                 ::ToUser[id]?ReceiveEarnings ->
//                         goto end;
//                 ::ToUser[id]?ReceiveItem ->
//                         goto end;
// //                ::else -> skip;
//             fi
    od
    end:
    skip;
}

proctype Contract(int ownerId){
    hasContract = true;
    // Contract State
    int highestBidder = -1;
    bool hasBid = false;
    int current = -1;
    int ticks = 10;
    do
        ::ticks > 0 ->
            if
                // If this is a higher bid, update the highest bidder and notify the caller
                ::ToContract?BidHigher, current ->
                    usersWaiting--;
                    hasBid = true;
                    highestBidder = current;
                    printf("%d is the highest bidder.\n", highestBidder);
                    //ToUser[current]!BidSuccess;
                    current = -1;
                // If this is a lower bid, reject the request
                ::ToContract?BidLower, current ->
                    usersWaiting--;
                    if
                    // I'm not really sure about this case because I feel like it might complicate analysis later... Should we just "assume" that bid lower always fails? 
                    // e.g. if there's a minimum price for the auction, then even if there's no current highest bidder, bid lower would fail.
                    ::!hasBid ->
                        hasBid = true;
                        highestBidder = current;
                        printf("%d is the highest bidder as there was no previous highest bid.\n", highestBidder);
                        //ToUser[current]!BidSuccess;
                        current = -1;
                    ::else ->
                        printf("Call to contract invalid: Bid too low.\n");
                        //ToUser[current]!Invalid;
                        current = -1;
                    fi
                // Attempting to distribute assets before the auction ends should fail.
                ::ToContract?DistributeAssets, current ->
                    usersWaiting--;
                    printf("Call to contract invalid: Bidding still in progress.\n");
                    //ToUser[current]!Invalid;
                    current = -1;
                //::true
                ::true;
            fi
            ticks--;
        ::else -> goto auctionEnd;
    od

    // State when the auction has ended
    auctionEnd:
    do
        ::ToContract?DistributeAssets, _ ->
            usersWaiting--;
            if
                // If there's a highest bidder then the bidder should get the item and the contract owner should get the earnings.
                ::hasBid ->
                    printf("%d received the earnings from the auction.\n", ownerId);
                    //ToUser[ownerId]!ReceiveEarnings;
                    printf("%d received the item from the auction.\n", highestBidder);
                    //ToUser[highestBidder]!ReceiveItem;
                // Otherwise the item is returned to the owner.
                ::else ->
                    printf("%d received the item from the auction as there was no bidder.\n", ownerId);
                    //ToUser[ownerId]!ReceiveItem;
            fi
            goto cleanup;

        // Calling other functions after the auction has ended should fail.
        ::ToContract?BidHigher, current ->
            usersWaiting--;
            printf("Call to contract invalid: Bidding is over.\n");
            //ToUser[current]!Invalid;
            current = -1;
        ::ToContract?BidLower, current ->
            usersWaiting--;
            printf("Call to contract invalid: Bidding is over.\n");
            //ToUser[current]!Invalid;
            current = -1;
    od
    cleanup:
    auctionFinish = true;
    do
        ::usersWaiting > 0 -> 
            ToContract?_,_;
            usersWaiting--;
        ::else -> break;
    od

    end_contract:
    skip;
}

init {
    run User(0, true);
    run User(1, false);
    run User(2, false);
}

ltl p1 {<>Contract@end_contract}