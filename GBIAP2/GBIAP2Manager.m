//
//  GBIAP2Manager.m
//  GBIAP2
//
//  Created by Luka Mirosevic on 21/05/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import "GBIAP2Manager.h"

#import <StoreKit/StoreKit.h>

static CGFloat const kGBIAP2TimeoutInterval = 20;

#if !DEBUG
static NSString * const kVerificationEndpointServerPath = @"production";
#else
static NSString * const kVerificationEndpointServerPath = @"development";
#endif

@interface GBIAP2 () <SKProductsRequestDelegate, SKPaymentTransactionObserver> {
    BOOL                                                    _didRequestSolicitedRestore;
    CGFloat                                                 _solicitedRestoreTransactionsRemaining;
}

//Some state
@property (copy, nonatomic) NSArray                         *validationServers;
@property (strong, nonatomic) NSMutableDictionary           *productCache;
@property (strong, nonatomic) NSMutableSet                  *solicitedPurchases;
@property (strong, nonatomic) id<GBIAP2AnalyticsModule>     analyticsModule;
@property (assign, nonatomic) BOOL                          isMetadataFetchInProgress;
@property (copy, nonatomic) GBIAP2MetadataCompletionBlock   internalMetadataFetchCompletedBlock;

//Solicitation state
@property (assign, nonatomic, readonly) BOOL                isSolicitedRestoreInProgress;

//Queue for verification
@property (assign, nonatomic) dispatch_queue_t              myQueue;

//Purchase/restore requests
@property (strong, nonatomic) NSMutableArray                *didRequestPurchaseHandlers;
@property (strong, nonatomic) NSMutableArray                *didRequestRestoreHandlers;

//Metadata
@property (strong, nonatomic) NSMutableArray                *didBeginMetadataFetchHandlers;
@property (strong, nonatomic) NSMutableArray                *didEndMetadataFetchHandlers;

//Purchase flow
@property (strong, nonatomic) NSMutableArray                *didBeginPurchasePhaseHandlers;
@property (strong, nonatomic) NSMutableArray                *didEndPurchasePhaseHandlers;
@property (strong, nonatomic) NSMutableArray                *didBeginRestorePhaseHandlers;
@property (strong, nonatomic) NSMutableArray                *didEndRestorePhaseHandlers;
@property (strong, nonatomic) NSMutableArray                *didBeginVerificationPhaseHandlers;
@property (strong, nonatomic) NSMutableArray                *didEndVerificationPhaseHandlers;

//Purchase acquiry
@property (strong, nonatomic) NSMutableArray                *didSuccessfullyAcquireProductHandlers;
@property (strong, nonatomic) NSMutableArray                *didFailToAcquireProductHandlers;

@end


@implementation GBIAP2

#pragma mark - Singleton

+(GBIAP2 *)purchaseManager {
    static GBIAP2 *purchaseManager;
    
    @synchronized(self) {
        if (!purchaseManager) {
            purchaseManager = [[GBIAP2 alloc] init];
        }
        
        return purchaseManager;
    }
}

#pragma mark - Memory

-(id)init {
    if (self = [super init]) {
        [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
        self.myQueue = dispatch_queue_create("GBIAP2 queue", NULL);
    }
    
    return self;
}

-(void)dealloc {
    dispatch_release(self.myQueue);
    self.myQueue = nil;
    
    self.analyticsModule = nil;
    self.validationServers = nil;
    self.productCache = nil;
    self.solicitedPurchases = nil;
    self.internalMetadataFetchCompletedBlock = nil;
    
    //handler storage
    self.didRequestPurchaseHandlers = nil;
    self.didRequestRestoreHandlers = nil;
    self.didBeginMetadataFetchHandlers = nil;
    self.didEndMetadataFetchHandlers = nil;
    self.didBeginPurchasePhaseHandlers = nil;
    self.didEndPurchasePhaseHandlers = nil;
    self.didBeginRestorePhaseHandlers = nil;
    self.didEndRestorePhaseHandlers = nil;
    self.didBeginVerificationPhaseHandlers = nil;
    self.didEndVerificationPhaseHandlers = nil;
    self.didSuccessfullyAcquireProductHandlers = nil;
    self.didFailToAcquireProductHandlers = nil;
}

//Borrowed from GBToolbox
#define _lazy(Class, propertyName, ivar) -(Class *)propertyName {if (!ivar) {ivar = [[Class alloc] init];}return ivar;}

_lazy(NSMutableDictionary, productCache, _productCache)
_lazy(NSMutableSet, solicitedPurchases, _solicitedPurchases)

_lazy(NSMutableArray, didRequestPurchaseHandlers, _didRequestPurchaseHandlers)
_lazy(NSMutableArray, didRequestRestoreHandlers, _didRequestRestoreHandlers)
_lazy(NSMutableArray, didBeginMetadataFetchHandlers, _didBeginMetadataFetchHandlers)
_lazy(NSMutableArray, didEndMetadataFetchHandlers, _didEndMetadataFetchHandlers)
_lazy(NSMutableArray, didBeginPurchasePhaseHandlers, _didBeginPurchasePhaseHandlers)
_lazy(NSMutableArray, didEndPurchasePhaseHandlers, _didEndPurchasePhaseHandlers)
_lazy(NSMutableArray, didBeginRestorePhaseHandlers, _didBeginRestorePhaseHandlers)
_lazy(NSMutableArray, didEndRestorePhaseHandlers, _didEndRestorePhaseHandlers)
_lazy(NSMutableArray, didBeginVerificationPhaseHandlers, _didBeginVerificationPhaseHandlers)
_lazy(NSMutableArray, didEndVerificationPhaseHandlers, _didEndVerificationPhaseHandlers)
_lazy(NSMutableArray, didSuccessfullyAcquireProductHandlers, _didSuccessfullyAcquireProductHandlers)
_lazy(NSMutableArray, didFailToAcquireProductHandlers, _didFailToAcquireProductHandlers)

#pragma mark - Solicited restore phase tracking (private)

-(void)_startSolicitedRestore {
    _didRequestSolicitedRestore = YES;
    _solicitedRestoreTransactionsRemaining = 0;
}

-(void)_resetRestoreSolicitationState {
    _didRequestSolicitedRestore = NO;
    _solicitedRestoreTransactionsRemaining = 0;
}

-(void)_decrementSolicitedRestoreCount {
    _solicitedRestoreTransactionsRemaining -= 1;
    
    //if our restore flow has come to an end
    if (_solicitedRestoreTransactionsRemaining <= 0) {
        [self _resetRestoreSolicitationState];
    }
}

-(void)_initializeSolicitedRestoreCount:(NSInteger)count {
    if (count > 0) {
        _solicitedRestoreTransactionsRemaining = count;
    }
    else {
        [self _resetRestoreSolicitationState];
    }
}

-(BOOL)_shouldInitializeSolicitedRestoreCount {
    return (_didRequestSolicitedRestore && _solicitedRestoreTransactionsRemaining == 0);
}

-(BOOL)isSolicitedRestoreInProgress {
    return (_didRequestSolicitedRestore || _solicitedRestoreTransactionsRemaining > 0);
}

-(NSUInteger)_numberOfRestoredTransactionsCurrentlyInQueue:(SKPaymentQueue *)queue {
    NSUInteger count = 0;
    for (SKPaymentTransaction *transaction in queue.transactions) {
        if (transaction.transactionState == SKPaymentTransactionStateRestored) {
            count += 1;
        }
    }
    return count;
}

#pragma mark - Setup phase

-(void)setAnalyticsModule:(id<GBIAP2AnalyticsModule>)analyticsModule {
    _analyticsModule = analyticsModule;
}

-(void)resumePendingTransactions {
    //noop, as soon as our singleton is initialized, he registers as a payment observer and transactions will resume. If this is the first call, then this triggers the singleton init
    
    //analytics
    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidResumeTransactions)]) [self.analyticsModule iapManagerDidResumeTransactions];
}

-(void)registerValidationServers:(NSArray *)validationServers {
    _validationServers = validationServers;
    
    //analytics
    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidRegisterValidationServers:)]) [self.analyticsModule iapManagerDidRegisterValidationServers:validationServers];
}

-(NSArray *)validationServers {
    return _validationServers;
}

#pragma mark - IAP prep phase

-(void)fetchMetadataForProducts:(NSArray *)productIdentifiers completed:(GBIAP2MetadataCompletionBlock)block {
    //analytics
    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerUserDidRequestMetadataForProducts:)]) [self.analyticsModule iapManagerUserDidRequestMetadataForProducts:productIdentifiers];
    
    //remove a dangling block if there was one
    self.internalMetadataFetchCompletedBlock = nil;
    
    if (!self.isMetadataFetchInProgress) {
        if (productIdentifiers) {
            self.isMetadataFetchInProgress = YES;
            
            //remember the block
            self.internalMetadataFetchCompletedBlock = block;
            
            //create products request
            SKProductsRequest *productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:productIdentifiers]];
            productsRequest.delegate = self;
            
            //kick off request
            [productsRequest start];
            
            //call handlers
            for (GBIAP2MetadataFetchDidBeginHandler handler in self.didBeginMetadataFetchHandlers) {
                handler(productIdentifiers);
            }
            
            //analytics
            if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidBeginMetadataFetchForProducts:)]) [self.analyticsModule iapManagerDidBeginMetadataFetchForProducts:productIdentifiers];
        }
        else {
            @throw [NSException exceptionWithName:@"BadParams" reason:@"productIdentifiers, can't request products without identifiers" userInfo:nil];
        }
    }
    //busy
    else {
        //let client know that it failed already
        if (block) block(NO);
    }
}

-(void)enumerateFetchedProductsWithBlock:(GBIAP2ProductHandler)block showCurrencySymbol:(BOOL)shouldShowCurrencySymbol {
    //set up number formatter
    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    [numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
    
    //decide whether or not to show currency symbol
    if (shouldShowCurrencySymbol) {
        [numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
    }
    else {
        [numberFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
    }
    
    for (NSString *productIdentifier in self.productCache) {
        SKProduct *product = self.productCache[productIdentifier];
        //set locale
        [numberFormatter setLocale:product.priceLocale];
        
        //create simple strings to describe product
        NSString *productIdentifier = product.productIdentifier;
        NSString *title = product.localizedTitle;
        NSString *description = product.localizedDescription;
        NSString *formattedPrice = [numberFormatter stringFromNumber:product.price];
        
        //call block
        if (block) block(productIdentifier, title, description, formattedPrice);
    }
}

#pragma mark - SKProductsRequestDelegate

-(void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    //to get back to the main thread because sometimes this is called on a different thread (this was the case on OS X 10.8.2)
    dispatch_async(dispatch_get_main_queue(), ^{
        //cache the products
        for (SKProduct *product in response.products) {
            self.productCache[product.productIdentifier] = product;
        }
        
        //no longer in process
        self.isMetadataFetchInProgress = NO;
        
        //call the handlers
        for (GBIAP2MetadataFetchDidEndHandler handler in self.didEndMetadataFetchHandlers) {
            handler([self.productCache allKeys], GBIAP2MetadataFetchStateSuccess);
        }
        
        //analytics
        if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidEndMetatdataFetchForProducts:state:)]) [self.analyticsModule iapManagerDidEndMetadataFetchForProducts:[self.productCache allKeys] state:GBIAP2MetadataFetchStateSuccess];
        
        //call the internal handler if we have one. call this last in case the client inside it chooses to make a purchase, so the metadata fetch state has had time to propagete through the system before the purchase state kicks off
        if (self.internalMetadataFetchCompletedBlock) {
            self.internalMetadataFetchCompletedBlock(YES);
            self.internalMetadataFetchCompletedBlock = nil;
        }
    });
}

//this one isnt technically in the SKProductsRequestDelegate but he might as well be
-(void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        //call the internal handler if we have one
        if (self.internalMetadataFetchCompletedBlock) {
            self.internalMetadataFetchCompletedBlock(NO);
            self.internalMetadataFetchCompletedBlock = nil;
        }
        
        //call the handlers
        for (GBIAP2MetadataFetchDidEndHandler handler in self.didEndMetadataFetchHandlers) {
            handler(nil, GBIAP2MetadataFetchStateFailed);
        }
        
        //analytics
        if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidEndMetatdataFetchForProducts:state:)]) [self.analyticsModule iapManagerDidEndMetadataFetchForProducts:@[] state:GBIAP2MetadataFetchStateFailed];
    });
}

#pragma mark - Purchasing phase

//Adds the purchase to the list of purchases
-(void)enqueuePurchaseWithIdentifier:(NSString *)productIdentifier {
    //analytics
    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerUserDidRequestPurchaseForProduct:)]) [self.analyticsModule iapManagerUserDidRequestPurchaseForProduct:productIdentifier];
    
    //send payment to apple
    SKPayment *payment = [SKPayment paymentWithProduct:self.productCache[productIdentifier]];
    [[SKPaymentQueue defaultQueue] addPayment:payment];
    
    //remember whom we've solicited this time
    [self.solicitedPurchases addObject:productIdentifier];
    
    //tell handlers
    for (GBIAP2DidRequestPurchaseHandler handler in self.didRequestPurchaseHandlers) {
        handler(productIdentifier);
    }
    
    //call didEnterPurchasePhaseHandlers
    for (GBIAP2PurchasePhaseDidBeginHandler handler in self.didBeginPurchasePhaseHandlers) {
        handler(productIdentifier, YES);
    }
    
    //analytics
    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidBeginPurchaseForProduct:)]) [self.analyticsModule iapManagerDidBeginPurchaseForProduct:productIdentifier];
}

-(void)restorePurchases {
    //analytics
    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerUserDidRequestRestore)]) [self.analyticsModule iapManagerUserDidRequestRestore];
    
    //send restore to apple
    [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
    
    //remember that we've solicited a restore
    [self _startSolicitedRestore];
    
    //tell handlers
    for (GBIAP2DidRequestRestoreHandler handler in self.didRequestRestoreHandlers) {
        handler();
    }
    
    //call didEnterPurchasePhaseHandlers
    for (GBIAP2PurchasePhaseDidBeginHandler handler in self.didBeginRestorePhaseHandlers) {
        handler(nil, YES);
    }
    
    //analytics
    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidBeginRestore)]) [self.analyticsModule iapManagerDidBeginRestore];
}

#pragma mark - SKPaymentTransactionObserver

-(void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        //determine purchase state
        GBIAP2PurchaseState purchaseState = (error.code == SKErrorPaymentCancelled) ? GBIAP2PurchaseStateCancelled : GBIAP2PurchaseStateFailed;
        
        //determine overall state
        GBIAP2TransactionState transactionState = (error.code == SKErrorPaymentCancelled) ? GBIAP2TransactionStateCancelled : GBIAP2TransactionStateFailed;
        
        //tell handlers
        for (GBIAP2PurchasePhaseDidEndHandler handler in self.didEndRestorePhaseHandlers) {
            handler(nil, purchaseState, self.isSolicitedRestoreInProgress);
        }
        
        //tell handlers
        for (GBIAP2PurchaseDidCompleteHandler handler in self.didFailToAcquireProductHandlers) {
            handler(nil, GBIAP2TransactionTypeRestore, transactionState, self.isSolicitedRestoreInProgress);
        }
        
        //analytics
        if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidFailToAcquireProduct:withTransactionType:transactionState:solicited:)]) [self.analyticsModule iapManagerDidFailToAcquireProduct:nil withTransactionType:GBIAP2TransactionTypeRestore transactionState:transactionState solicited:self.isSolicitedRestoreInProgress];
        
        //this is an exit point for the solicited restore
        [self _resetRestoreSolicitationState];
    });
}

-(void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (SKPaymentTransaction *transaction in transactions) {
            switch (transaction.transactionState) {
                case SKPaymentTransactionStatePurchased: {
                    NSString *productIdentifier = transaction.payment.productIdentifier;
                    
                    //tell handlers that he exited the purchase phase
                    for (GBIAP2PurchasePhaseDidEndHandler handler in self.didEndPurchasePhaseHandlers) {
                        handler(productIdentifier, GBIAP2PurchaseStateSuccess, [self.solicitedPurchases containsObject:productIdentifier]);
                    }
                    
                    //analytics
                    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidEndPurchaseForProduct:state:solicited:)]) [self.analyticsModule iapManagerDidEndPurchaseForProduct:productIdentifier state:GBIAP2PurchaseStateSuccess solicited:[self.solicitedPurchases containsObject:productIdentifier]];
                    
                    GBIAP2TransactionType transactionType = (transaction.originalTransaction != nil) ? GBIAP2TransactionTypeRePurchase : GBIAP2TransactionTypePurchase;
                    
                    //verify transaction
                    [self _verifyTransaction:transaction withType:transactionType];
                } break;
                case SKPaymentTransactionStateRestored: {
                    NSString *productIdentifier = transaction.originalTransaction.payment.productIdentifier;
                    
                    //if the user solicited the restore and we didn't init yet, then do so
                    if ([self _shouldInitializeSolicitedRestoreCount]) [self _initializeSolicitedRestoreCount:[self _numberOfRestoredTransactionsCurrentlyInQueue:queue]];
                    
                    //tell handlers that he exited the restore phase
                    for (GBIAP2PurchasePhaseDidEndHandler handler in self.didEndRestorePhaseHandlers) {
                        handler(productIdentifier, GBIAP2PurchaseStateSuccess, self.isSolicitedRestoreInProgress);
                    }
                    
                    //analytics
                    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidEndRestoreForProduct:state:solicited:)]) [self.analyticsModule iapManagerDidEndRestoreForProduct:productIdentifier state:GBIAP2PurchaseStateSuccess solicited:self.isSolicitedRestoreInProgress];
                    
                    //verify transaction
                    [self _verifyTransaction:transaction withType:GBIAP2TransactionTypeRestore];
                } break;
                case SKPaymentTransactionStateFailed: {
                    NSString *productIdentifier = transaction.payment.productIdentifier;
                    
                    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                    
                    //determine state
                    GBIAP2PurchaseState purchaseState = (transaction.error.code == SKErrorPaymentCancelled) ? GBIAP2PurchaseStateCancelled : GBIAP2PurchaseStateFailed;
                    GBIAP2TransactionState transactionState = (transaction.error.code == SKErrorPaymentCancelled) ? GBIAP2TransactionStateCancelled : GBIAP2TransactionStateFailed;
                    
                    //tell handlers that he exited the purchase phase
                    for (GBIAP2PurchasePhaseDidEndHandler handler in self.didEndPurchasePhaseHandlers) {
                        handler(productIdentifier, purchaseState, [self.solicitedPurchases containsObject:productIdentifier]);
                    }
                    
                    //analytics
                    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidEndPurchaseForProduct:state:solicited:)]) [self.analyticsModule iapManagerDidEndPurchaseForProduct:productIdentifier state:purchaseState solicited:[self.solicitedPurchases containsObject:productIdentifier]];
                    
                    //tell handlers that this product purchase failed
                    for (GBIAP2PurchaseDidCompleteHandler handler in self.didFailToAcquireProductHandlers) {
                        handler(productIdentifier, GBIAP2TransactionTypePurchase, transactionState, [self.solicitedPurchases containsObject:productIdentifier]);
                    }
                    
                    //analytics
                    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidFailToAcquireProduct:withTransactionType:transactionState:solicited:)]) [self.analyticsModule iapManagerDidFailToAcquireProduct:productIdentifier withTransactionType:GBIAP2TransactionTypePurchase transactionState:transactionState solicited:[self.solicitedPurchases containsObject:productIdentifier]];
                    
                    //remove the product from the solicited purchases
                    [self.solicitedPurchases removeObject:productIdentifier];
                } break;
                    
                default:
                    break;
            }
        }
    });
}

#pragma mark - Transaction verification (private)

-(void)_verifyTransaction:(SKPaymentTransaction *)transaction withType:(GBIAP2TransactionType)transactionType {
    NSString *productIdentifier = transaction.payment.productIdentifier;
    
    NSUInteger serverCount = self.validationServers.count;
    NSString *randomServer = self.validationServers[arc4random() % serverCount];
    NSURL *url = [NSURL URLWithString:randomServer];
    
    //purchase
    if (transactionType == GBIAP2TransactionTypePurchase || transactionType == GBIAP2TransactionTypeRePurchase) {
        //tell delegates that he started the verification phase
        for (GBIAP2PurchasePhaseDidBeginHandler handler in self.didBeginVerificationPhaseHandlers) {
            handler(productIdentifier, [self.solicitedPurchases containsObject:productIdentifier]);
        }
    }
    //restore
    else if (transactionType == GBIAP2TransactionTypeRestore) {
        //tell delegates that he started the verification phase
        for (GBIAP2PurchasePhaseDidBeginHandler handler in self.didBeginVerificationPhaseHandlers) {
            handler(productIdentifier, self.isSolicitedRestoreInProgress);
        }
    }
    
    //analytics
    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidBeginVerificationForProduct:onServer:)]) [self.analyticsModule iapManagerDidBeginVerificationForProduct:productIdentifier onServer:randomServer];
    
    //start verifying receipt
    if (transaction.transactionReceipt) {
        //prep url request
        NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kGBIAP2TimeoutInterval];
        [urlRequest setHTTPMethod:@"POST"];
        [urlRequest setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
        [urlRequest setHTTPBody:transaction.transactionReceipt];
        
        //send url request
        dispatch_async(self.myQueue, ^{
            NSURLResponse *response;
            NSError *error;
            NSData *resultData = [NSURLConnection sendSynchronousRequest:urlRequest returningResponse:&response error:&error];
            
            //process data into a string
            NSString *resultString = [[NSString alloc] initWithData:resultData encoding:NSUTF8StringEncoding];
            BOOL resultBool = [resultString isEqualToString:@"1"];
            
            //completed
            dispatch_async(dispatch_get_main_queue(), ^{
                //finish transaction
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                
                //get the state
                GBIAP2VerificationState purchaseState = resultBool ? GBIAP2VerificationStateSuccess : GBIAP2VerificationStateFailed;
                GBIAP2TransactionState transactionState = resultBool ? GBIAP2TransactionStateSuccess : GBIAP2TransactionStateFailed;
                
                //conclude whether he was solicited or not
                BOOL wasSolicited = NO;
                if (transactionType == GBIAP2TransactionTypePurchase || transactionType == GBIAP2TransactionTypeRePurchase) {
                    wasSolicited = [self.solicitedPurchases containsObject:productIdentifier];
                }
                else if (transactionType == GBIAP2TransactionTypeRestore) {
                    wasSolicited = self.isSolicitedRestoreInProgress;
                }
                
                //tell handlers that he exited the verification phase
                for (GBIAP2VerificationPhaseDidEndHandler handler in self.didEndVerificationPhaseHandlers) {
                    handler(productIdentifier, purchaseState, wasSolicited);
                }
                
                //analytics
                if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidEndVerificationForProduct:onServer:state:)]) [self.analyticsModule iapManagerDidEndVerificationForProduct:productIdentifier onServer:randomServer state:purchaseState];
                
                //if succesful
                if (purchaseState == GBIAP2VerificationStateSuccess) {
                    //call success handlers
                    for (GBIAP2PurchaseDidCompleteHandler handler in self.didSuccessfullyAcquireProductHandlers) {
                        handler(productIdentifier, transactionType, transactionState, wasSolicited);
                    }
                    
                    //analytics
                    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidSuccessfullyAcquireProduct:withTransactionType:transactionState:solicited:)]) [self.analyticsModule iapManagerDidSuccessfullyAcquireProduct:productIdentifier withTransactionType:transactionType transactionState:transactionState solicited:wasSolicited];
                }
                //if failed
                else {
                    //tell handlers
                    for (GBIAP2PurchaseDidCompleteHandler handler in self.didFailToAcquireProductHandlers) {
                        handler(productIdentifier, transactionType, transactionState, wasSolicited);
                    }
                    
                    //analytics
                    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidFailToAcquireProduct:withTransactionType:transactionState:solicited:)]) [self.analyticsModule iapManagerDidFailToAcquireProduct:productIdentifier withTransactionType:transactionType transactionState:transactionState solicited:wasSolicited];
                }
                
                //reset solicited internal state keepers
                if (transactionType == GBIAP2TransactionTypePurchase || transactionType == GBIAP2TransactionTypeRePurchase) {
                    //remove the product from the solicited purchases
                    [self.solicitedPurchases removeObject:productIdentifier];
                }
                else if (transactionType == GBIAP2TransactionTypeRestore) {
                    //this is an exit point for the solicited restore
                    [self _decrementSolicitedRestoreCount];
                }
            });
        });
    }
}

#pragma mark - Purchase/Restore requests

//Notifies you when a purchase or restore was requested
-(void)addHandlerForDidRequestPurchase:(GBIAP2DidRequestPurchaseHandler)handler {
    if (handler) [self.didRequestPurchaseHandlers addObject:[handler copy]];
}

-(void)addHandlerForDidRequestRestore:(GBIAP2DidRequestRestoreHandler)handler {
    if (handler) [self.didRequestRestoreHandlers addObject:[handler copy]];
}

#pragma mark - Metadata flow

-(void)addHandlerForDidBeginMetadataFetch:(GBIAP2MetadataFetchDidBeginHandler)handler {
    if (handler) [self.didBeginMetadataFetchHandlers addObject:[handler copy]];
}

-(void)addHandlerForDidEndMetadataFetch:(GBIAP2MetadataFetchDidEndHandler)handler {
    if (handler) [self.didEndMetadataFetchHandlers addObject:[handler copy]];
}

#pragma mark - Purchase flow

-(void)addHandlerForDidBeginPurchasePhase:(GBIAP2PurchasePhaseDidBeginHandler)handler {
    if (handler) [self.didBeginPurchasePhaseHandlers addObject:[handler copy]];
}

-(void)addHandlerForDidEndPurchasePhase:(GBIAP2PurchasePhaseDidEndHandler)handler {
    if (handler) [self.didEndPurchasePhaseHandlers addObject:[handler copy]];
}

-(void)addHandlerForDidBeginRestorePhase:(GBIAP2PurchasePhaseDidBeginHandler)handler {
    if (handler) [self.didBeginRestorePhaseHandlers addObject:[handler copy]];
}

-(void)addHandlerForDidEndRestorePhase:(GBIAP2PurchasePhaseDidEndHandler)handler {
    if (handler) [self.didEndRestorePhaseHandlers addObject:[handler copy]];
}

-(void)addHandlerForDidBeginVerificationPhase:(GBIAP2VerificationPhaseDidBeginHandler)handler {
    if (handler) [self.didBeginVerificationPhaseHandlers addObject:[handler copy]];
}

-(void)addHandlerForDidEndVerificationPhase:(GBIAP2VerificationPhaseDidEndHandler)handler {
    if (handler) [self.didEndVerificationPhaseHandlers addObject:[handler copy]];
}

#pragma mark - Product acquired

-(void)addHandlerForDidSuccessfullyAcquireProduct:(GBIAP2PurchaseDidCompleteHandler)handler {
    if (handler) [self.didSuccessfullyAcquireProductHandlers addObject:[handler copy]];
}

-(void)addHandlerForDidFailToAcquireProduct:(GBIAP2PurchaseDidCompleteHandler)handler {
    if (handler) [self.didFailToAcquireProductHandlers addObject:[handler copy]];
}

@end
