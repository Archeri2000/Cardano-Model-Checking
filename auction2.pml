// Users will call this
mtype = {DistributeAssets, Bid, None};


typedef Log{
    mtype Message = None;
    int Value = 0;
    int Caller = 0;
    bool isSuccess = false;
}

Log log;

int WinningBidder = -1;
int tokens[3];

// Rendevouz Messaging Channel
chan ToContract = [0] of {mtype, int, int};

// Process Synchronisation Variables
bool hasContract = false;
bool auctionFinish = false;

int usersWaiting = 0;

// Contract State
int highestBidder = -1;
int bid = 0;


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
                    ToContract!DistributeAssets, 0, id}
        ::atomic{!auctionFinish -> 
                    usersWaiting++;
                    int num = 0;
                    if
                    ::tokens[id] > bid -> num = bid+1;
                    ::tokens[id] >= bid -> num = bid;
                    ::true -> num = tokens[id];
                    fi
                    tokens[id] = tokens[id] - num;
                    ToContract!Bid, num, id}
    od
    end:
    skip;
}

proctype Contract(int ownerId){
    hasContract = true;
    int current = -1;
    int bidAttempt = -1;
    int ticks = 10;
    do
        ::atomic{ticks > 0 ->
            if
                // If this is a higher bid, update the highest bidder and notify the caller
                ::ToContract?Bid, bidAttempt, current ->
                    usersWaiting--;
                    log.Message = Bid;
                    log.Value = bidAttempt; 
                    log.Caller = current;
                    if
                    ::bidAttempt > bid -> 
                        bid = bidAttempt;
                        highestBidder = current;
                        printf("%d is the highest bidder with Bid=%d.\n", highestBidder, bid);
                        log.isSuccess = true;
                        current = -1;
                    ::else ->
                        tokens[current] = tokens[current] + bidAttempt;
                        printf("Call to contract invalid: %d's Bid of %d is too low.\n", current, bidAttempt);
                        log.isSuccess = false;
                    fi;
                    current = -1;
                    bidAttempt = -1;
                // Attempting to distribute assets before the auction ends should fail.
                ::ToContract?DistributeAssets, bidAttempt, current ->
                    usersWaiting--;
                    tokens[current] = tokens[current] + bidAttempt;
                    printf("Call to contract invalid: Bidding still in progress.\n");
                    log.Message = DistributeAssets;
                    log.Value = bidAttempt; 
                    log.Caller = current;
                    log.isSuccess = false;
                    current = -1;
                    bidAttempt = -1;
                ::true;
            fi
            ticks--;}
        ::else -> goto auctionEnd;
    od

    // State when the auction has ended
    auctionEnd:
    atomic{
        log.Message = None;
        log.Caller = -1;
        log.isSuccess = false;
    }
    do
        ::atomic{ToContract?DistributeAssets, bidAttempt, _ ->
            usersWaiting--;
            if
                // If there's a highest bidder then the bidder should get the item and the contract owner should get the earnings.
                ::bid > 0 ->
                    printf("%d received the earnings from the auction.\n", ownerId);
                    tokens[ownerId] = tokens[ownerId] + bid;
                    printf("%d received the item from the auction.\n", highestBidder);
                    WinningBidder = highestBidder;
                    log.Message = DistributeAssets;
                    log.Caller = current;
                    log.Value = bidAttempt; 
                    log.isSuccess = true;
                // Otherwise the item is returned to the owner.
                ::else ->
                    printf("%d received the item from the auction as there was no bidder.\n", ownerId);
                    WinningBidder = ownerId;
                    log.Message = DistributeAssets;
                    log.Caller = current;
                    log.Value = bidAttempt; 
                    log.isSuccess = true;
            fi
            goto cleanup;}

        // Calling other functions after the auction has ended should fail.
        ::atomic{ToContract?Bid, bidAttempt, current ->
            usersWaiting--;
            printf("Call to contract invalid: Bidding is over.\n");
            tokens[current] = tokens[current] + bidAttempt;
            log.Message = Bid;
            log.Value = bidAttempt; 
            log.Caller = current;
            log.isSuccess = false;
            current = -1;
            bidAttempt = -1;}
    od
    cleanup:
    auctionFinish = true;
    do
        ::usersWaiting > 0 ->
            if
            ::ToContract?Bid,bidAttempt,current -> 
                tokens[current] = tokens[current] + bidAttempt;
                current = -1;
                bidAttempt = -1;
            ::ToContract?DistributeAssets,_,_;
            fi
            usersWaiting--;
        ::else -> break;
    od

    end_contract:
    skip;
}

init {
    atomic{
        tokens[0] = 20;
        tokens[1] = 20;
        tokens[2] = 20;
        run User(0, true);
        run User(1, false);
        run User(2, false);
    }
}

// Contract should eventually end
ltl p1 {<>Contract@end_contract}

// Contract should always time out eventually
ltl p2 {<>Contract@auctionEnd}

// Calling bid before timeout with a lower bid should always fail
#define lowBidShouldFail ((log.Message != Bid) || ((log.Value < bid) -> !log.isSuccess))
ltl p3 {[]lowBidShouldFail}

// Calling bid after timeout should always fail
#define bidShouldFail ((log.Message != Bid) || (!log.isSuccess))
ltl p4 {[](Contract@auctionEnd->[]bidShouldFail)}

// If Distribute assets called before timeout,  it will fail
#define distributeAssetsShouldFail ((log.Message != DistributeAssets) || (!log.isSuccess))
ltl p5 {distributeAssetsShouldFail U Contract@auctionEnd}

// Calling distribute assets after timeout should succeed
#define distributeAssetsShouldSucceed ((log.Message != DistributeAssets) || log.isSuccess)
ltl p6 {[](Contract@auctionEnd->[]distributeAssetsShouldSucceed)}

// User 0 should keep all tokens if they failed to win
ltl p7 {[](Contract@end_contract -> [](WinningBidder != 0 -> tokens[0] >= 20))}

// User 1 should keep all tokens if they failed to win
ltl p8 {[](Contract@end_contract -> [](WinningBidder != 1 -> tokens[1] >= 20))}

// User 2 should keep all tokens if they failed to win
ltl p9 {[](Contract@end_contract -> [](WinningBidder != 2 -> tokens[2] >= 20))}