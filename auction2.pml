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
int tokens[3] = 20;
int pending[3];
bool isWaiting[3];

// Rendevouz Messaging Channel
chan ToContract = [0] of {mtype, int, int};

// Process Synchronisation Variables
bool hasContract = false;
bool auctionFinish = false;

int usersWaiting = 0;

// Contract State
int highestBidder = -1;
int bid = 0;


inline refundPending(id){
    atomic{
        tokens[id] = tokens[id] + pending[id];
        pending[id] = 0;
        isWaiting[id] = false;
    }
}

inline consumePending(id){
    atomic{
        pending[id] = 0;
        isWaiting[id] = false;
    }
}

inline refundPrevHighest(){
    atomic{
        if
        ::highestBidder != -1 -> tokens[highestBidder] = tokens[highestBidder] + bid;
        ::else
        fi
    }
}


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
        ::atomic{(!auctionFinish && !isWaiting[id]) -> 
                    usersWaiting++;
                    isWaiting[id] = true;
                    ToContract!DistributeAssets, 0, id}
        ::atomic{(!auctionFinish && !isWaiting[id]) -> 
                    usersWaiting++;
                    isWaiting[id] = true;
                    int num = 0;
                    if
                    ::tokens[id] > bid -> num = bid+1;
                    ::tokens[id] >= bid -> num = bid;
                    ::true -> num = tokens[id];
                    fi
                    tokens[id] = tokens[id] - num;
                    pending[id] = pending[id] + num;
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
        ::ticks > 0 ->
            if
                // If this is a higher bid, update the highest bidder and notify the caller
                ::ToContract?Bid, bidAttempt, current ->
                    usersWaiting--;
                    log.Message = Bid;
                    log.Value = bidAttempt; 
                    log.Caller = current;
                    if
                    ::bidAttempt > bid -> 
                        atomic{
                            refundPrevHighest();
                            consumePending(current);
                            bid = bidAttempt;
                            highestBidder = current;
                        }
                        printf("%d is the highest bidder with Bid=%d.\n", highestBidder, bid);
                        log.isSuccess = true;
                    ::else ->
                        refundPending(current);
                        printf("Call to contract invalid: %d's Bid of %d is too low.\n", current, bidAttempt);
                        log.isSuccess = false;
                    fi;
                    current = -1;
                    bidAttempt = -1;
                // Attempting to distribute assets before the auction ends should fail.
                ::ToContract?DistributeAssets, bidAttempt, current ->
                    usersWaiting--;
                    refundPending(current);
                    printf("Call to contract invalid: Bidding still in progress.\n");
                    log.Message = DistributeAssets;
                    log.Value = bidAttempt; 
                    log.Caller = current;
                    log.isSuccess = false;
                    current = -1;
                    bidAttempt = -1;
                ::true;
            fi
            ticks--;
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
        ::atomic{ToContract?DistributeAssets, bidAttempt, current ->
            usersWaiting--;
            if
                // If there's a highest bidder then the bidder should get the item and the contract owner should get the earnings.
                ::bid > 0 ->
                    printf("%d received the earnings from the auction.\n", ownerId);
                    printf("%d received the item from the auction.\n", highestBidder);
                    atomic{
                        tokens[ownerId] = tokens[ownerId] + bid;
                        refundPending(current);
                        WinningBidder = highestBidder;
                        bid = 0;
                    }
                    log.Message = DistributeAssets;
                    log.Caller = current;
                    log.Value = bidAttempt; 
                    log.isSuccess = true;
                // Otherwise the item is returned to the owner.
                ::else ->
                    printf("%d received the item from the auction as there was no bidder.\n", ownerId);
                    atomic{
                        refundPending(current);
                        WinningBidder = ownerId;
                    }
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
            refundPending(current);
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
                refundPending(current);
                current = -1;
                bidAttempt = -1;
            ::ToContract?DistributeAssets,bidAttempt,current ->
                refundPending(current);
                current = -1;
                bidAttempt = -1;

            fi
            usersWaiting--;
        ::else -> break;
    od

    end_contract:
    skip;
}

init {
    atomic{
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
#define distributeAssetsShouldFail ((log.Message == DistributeAssets) -> (!log.isSuccess))
ltl p5 {distributeAssetsShouldFail U Contract@auctionEnd}

// Calling distribute assets after timeout should succeed
#define distributeAssetsShouldSucceed ((log.Message == DistributeAssets) -> log.isSuccess)
ltl p6 {[](Contract@auctionEnd->[]distributeAssetsShouldSucceed)}

// User 0 should keep all tokens if they aren't the owner and they failed to win
ltl p7 {[](Contract@end_contract -> []((WinningBidder != 0 && !User[1]:isOwner) -> tokens[0] == 20))}

// User 1 should keep all tokens if they aren't the owner and they failed to win
ltl p8 {[](Contract@end_contract -> []((WinningBidder != 1 && !User[2]:isOwner) -> tokens[1] == 20))}

// User 2 should keep all tokens if they aren't the owner and they failed to win
ltl p9 {[](Contract@end_contract -> []((WinningBidder != 2 && !User[3]:isOwner) -> tokens[2] == 20))}

// User 0 should get more tokens if they are the owner and did not win the auction themselves
ltl p10 {[](Contract@end_contract -> [](WinningBidder != 0 && User[1]:isOwner -> tokens[0] == 20 + bid))}

// User 1 should get more tokens if they are the owner and did not win the auction themselves
ltl p11 {[](Contract@end_contract -> [](WinningBidder != 1 && User[2]:isOwner -> tokens[1] == 20 + bid))}

// User 2 should get more tokens if they are the owner and did not win the auction themselves
ltl p12 {[](Contract@end_contract -> [](WinningBidder != 2 && User[3]:isOwner -> tokens[2] == 20 + bid))}

// User 0 should get no tokens if they are the owner and won the auction themselves
ltl p13 {[](Contract@end_contract -> [](WinningBidder == 0 && User[1]:isOwner -> tokens[0] == 20))}

// User 1 should get no tokens if they are the owner and won the auction themselves
ltl p14 {[](Contract@end_contract -> [](WinningBidder == 1 && User[2]:isOwner -> tokens[1] == 20))}

// User 2 should get no tokens if they are the owner and won the auction themselves
ltl p15 {[](Contract@end_contract -> [](WinningBidder == 2 && User[3]:isOwner -> tokens[2] == 20))}

// The winning bidder should lose tokens equal to the highest bid if they arent the owner
ltl p16 {[](Contract@end_contract -> [](WinningBidder != Contract[4]:ownerId -> tokens[WinningBidder] == 20 - bid))}

// The total number of tokens in the system should be the same always
ltl p17 {[]((tokens[0] + tokens[1] + tokens[2] + pending[0] + pending[1] + pending[2] + bid) == 60)}