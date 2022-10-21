// Users will call this
mtype = {DistributeAssets, BidHigher, BidLower, None};


typedef Log{
    mtype Message = None;
    int Caller = 0;
    bool isSuccess = false;
}

Log log;

int WinningBidder = -1;
//TODO
int Earnings = -1;


// Rendevouz Messaging Channel
chan ToContract = [0] of {mtype, int};

// Process Synchronisation Variables
bool hasContract = false;

bool auctionFinish = false;

int usersWaiting = 0;


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
        ::atomic{ticks > 0 ->
            if
                // If this is a higher bid, update the highest bidder and notify the caller
                ::ToContract?BidHigher, current ->
                    usersWaiting--;
                    hasBid = true;
                    highestBidder = current;
                    printf("%d is the highest bidder.\n", highestBidder);
                    log.Message = BidHigher;
                    log.Caller = current;
                    log.isSuccess = true;
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
                        log.Message = BidLower;
                        log.Caller = current;
                        log.isSuccess = true;
                        current = -1;
                    ::else ->
                        printf("Call to contract invalid: Bid too low.\n");
                        log.Message = BidLower;
                        log.Caller = current;
                        log.isSuccess = false;
                        current = -1;
                    fi
                // Attempting to distribute assets before the auction ends should fail.
                ::ToContract?DistributeAssets, current ->
                    usersWaiting--;
                    printf("Call to contract invalid: Bidding still in progress.\n");
                    log.Message = DistributeAssets;
                    log.Caller = current;
                    log.isSuccess = false;
                    current = -1;
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
        ::atomic{ToContract?DistributeAssets, _ ->
            usersWaiting--;
            if
                // If there's a highest bidder then the bidder should get the item and the contract owner should get the earnings.
                ::hasBid ->
                    printf("%d received the earnings from the auction.\n", ownerId);
                    //ToUser[ownerId]!ReceiveEarnings;
                    printf("%d received the item from the auction.\n", highestBidder);
                    //ToUser[highestBidder]!ReceiveItem;
                    log.Message = DistributeAssets;
                    log.Caller = current;
                    log.isSuccess = true;
                // Otherwise the item is returned to the owner.
                ::else ->
                    printf("%d received the item from the auction as there was no bidder.\n", ownerId);
                    //ToUser[ownerId]!ReceiveItem;
                    log.Message = DistributeAssets;
                    log.Caller = current;
                    log.isSuccess = true;
            fi
            goto cleanup;}

        // Calling other functions after the auction has ended should fail.
        ::atomic{ToContract?BidHigher, current ->
            usersWaiting--;
            printf("Call to contract invalid: Bidding is over.\n");
            log.Message = BidHigher;
            log.Caller = current;
            log.isSuccess = false;
            current = -1;}
        ::atomic{ToContract?BidLower, current ->
            usersWaiting--;
            printf("Call to contract invalid: Bidding is over.\n");
            log.Message = BidLower;
            log.Caller = current;
            log.isSuccess = false;
            current = -1;}
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

// Contract should eventually end
ltl p1 {<>Contract@end_contract}

// Contract should always time out eventually
ltl p2 {<>Contract@auctionEnd}

// Calling bid higher before timeout should always succeed
#define bidHigherAlwaysSucceed ((log.Message != BidHigher) || (log.isSuccess))
ltl p3 {bidHigherAlwaysSucceed U Contract@auctionEnd}

// If Distribute assets called before timeout,  it will fail
#define distributeAssetsShouldFail ((log.Message != DistributeAssets) || (!log.isSuccess))
ltl p4 {distributeAssetsShouldFail U Contract@auctionEnd}

// Calling bid higher after timeout should always fail