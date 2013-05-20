//
//  GBIAP2.m
//  GBIAP2
//
//  Created by Luka Mirosevic on 20/05/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import "GBIAP2.h"

#import <StoreKit/StoreKit.h>

static CGFloat const kGBIAP2TimeoutInterval = 10;

#if !DEBUG
    static NSString * const kVerificationEndpointServerPath = @"production";
#else
    static NSString * const kVerificationEndpointServerPath = @"development";
#endif

@interface GBIAP2 () <SKProductsRequestDelegate, SKPaymentTransactionObserver>

//Some state
@property (copy, nonatomic) NSArray                         *validationServers;
@property (strong, nonatomic) NSMutableDictionary           *productCache;
@property (strong, nonatomic) NSMutableSet                  *solicitedPurchases;
@property (strong, nonatomic) id<GBIAP2AnalyticsModule>     analyticsModule;
@property (assign, nonatomic) BOOL                          isMetadataFetchInProgress;
@property (assign, nonatomic) BOOL                          isSolicitedRestoreInProgress;

//Queue for verification
@property (assign, nonatomic) dispatch_queue_t              myQueue;

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
        
        #if DEBUG
            NSLog(@"GBIAP2: Running with sandbox server API endpoint");
        #endif
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
    
    //handler storage
    self.didBeginMetadataFetchHandlers = nil;
    self.didEndMetadataFetchHandlers = nil;
    self.didBeginPurchasePhaseHandlers = nil;
    self.didEndPurchasePhaseHandlers = nil;
    self.didBeginRestorePhaseHandlers = nil;
    self.didEndRestorePhaseHandlers = nil;
    self.didBeginVerificationPhaseHandlers = nil;
    self.didEndVerificationPhaseHandlers = nil;
    self.didSuccessfullyAcquireProductHandlers = nil;
}

//Borrowed from GBToolbox, suffixed with 2 to prevent potential name clash//foo try renaming to _lazy and see if it works if the superproject uses GBToolbox
#define _lazy2(Class, propertyName, ivar) -(Class *)propertyName {if (!ivar) {ivar = [[Class alloc] init];}return ivar;}

_lazy2(NSMutableDictionary, productCache, _productCache)
_lazy2(NSMutableSet, solicitedPurchases, _solicitedPurchases)

_lazy2(NSMutableArray, didBeginMetadataFetchHandlers, _didBeginMetadataFetchHandlers)
_lazy2(NSMutableArray, didEndMetadataFetchHandlers, _didEndMetadataFetchHandlers)
_lazy2(NSMutableArray, didBeginPurchasePhaseHandlers, _didBeginPurchasePhaseHandlers)
_lazy2(NSMutableArray, didEndPurchasePhaseHandlers, _didEndPurchasePhaseHandlers)
_lazy2(NSMutableArray, didBeginRestorePhaseHandlers, _didBeginRestorePhaseHandlers)
_lazy2(NSMutableArray, didEndRestorePhaseHandlers, _didEndRestorePhaseHandlers)
_lazy2(NSMutableArray, didBeginVerificationPhaseHandlers, _didBeginVerificationPhaseHandlers)
_lazy2(NSMutableArray, didEndVerificationPhaseHandlers, _didEndVerificationPhaseHandlers)
_lazy2(NSMutableArray, didSuccessfullyAcquireProductHandlers, _didSuccessfullyAcquireProductHandlers)

#pragma mark - Setup phase

-(void)setAnalyticsModule:(id<GBIAP2AnalyticsModule>)analyticsModule {
    self.analyticsModule = analyticsModule;
}

-(void)resumePendingTransactions {
    //noop, as soon as our singleton is initialized, he registers as a payment observer and transactions will resume. If this is the first call, then this triggers the singleton init
    
    //analytics
    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidResumeTransactions)]) [self.analyticsModule iapManagerDidResumeTransactions];
}

-(void)registerValidationServers:(NSArray *)validationServers {
    self.validationServers = validationServers;
    
    //analytics
    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidRegisterValidationServers:)]) [self.analyticsModule iapManagerDidRegisterValidationServers:validationServers];
}

-(NSArray *)validationServers {
    return self.validationServers;
}

#pragma mark - IAP prep phase

-(void)fetchMetadataForProducts:(NSArray *)productIdentifiers {
    //analytics
    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerUserDidRequestMetadataForProducts:)]) [self.analyticsModule iapManagerUserDidRequestMetadataForProducts:productIdentifiers];
    
    if (!self.isMetadataFetchInProgress) {
        if (productIdentifiers) {
            self.isMetadataFetchInProgress = YES;
            
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
        if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidEndMetatdataFetchForProducts:state:)]) [self.analyticsModule iapManagerDidEndMetatdataFetchForProducts:[self.productCache allKeys] state:GBIAP2MetadataFetchStateSuccess];
    });
}

//this one isnt technically in the SKProductsRequestDelegate but he might as well be
-(void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        //call the handlers
        for (GBIAP2MetadataFetchDidEndHandler handler in self.didEndMetadataFetchHandlers) {
            handler(nil, GBIAP2MetadataFetchStateFailed);
        }
        
        //analytics
        if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidEndMetatdataFetchForProducts:state:)]) [self.analyticsModule iapManagerDidEndMetatdataFetchForProducts:@[] state:GBIAP2MetadataFetchStateFailed];
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
    self.isSolicitedRestoreInProgress = YES;
    
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
        //determine state
        GBIAP2PurchaseState state = (error.code == SKErrorPaymentCancelled) ? GBIAP2PurchaseStateCancelled : GBIAP2PurchaseStateFailed;
        
        //tell handlers
        for (GBIAP2PurchasePhaseDidEndHandler handler in self.didEndRestorePhaseHandlers) {
            handler(nil, state, self.isSolicitedRestoreInProgress);
        }
        
        //we've no longer solicited a restore
        self.isSolicitedRestoreInProgress = NO;
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
                    
                    //verify transaction
                    [self _verifyTransaction:transaction withType:GBIAP2TransactionTypePurchase];
                } break;
                case SKPaymentTransactionStateRestored: {
                    NSString *productIdentifier = transaction.originalTransaction.payment.productIdentifier;

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
                    
                    //foo shud I do this here? try not doing it and see what happens
                    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                    
                    //determine state
                    GBIAP2PurchaseState state = (transaction.error.code == SKErrorPaymentCancelled) ? GBIAP2PurchaseStateCancelled : GBIAP2PurchaseStateFailed;
                    
                    //tell handlers that he exited the purchase phase
                    for (GBIAP2PurchasePhaseDidEndHandler handler in self.didEndPurchasePhaseHandlers) {
                        handler(productIdentifier, state, [self.solicitedPurchases containsObject:productIdentifier]);
                    }
                    
                    //analytics
                    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidEndPurchaseForProduct:state:solicited:)]) [self.analyticsModule iapManagerDidEndPurchaseForProduct:productIdentifier state:state solicited:[self.solicitedPurchases containsObject:productIdentifier]];
                    
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
    
    //purchase
    if (transactionType == GBIAP2TransactionTypePurchase) {
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
    
    //start verifying receipt
    if (transaction.transactionReceipt) {
        //first get a server url
        NSUInteger serverCount = self.validationServers.count;
        NSString *randomServer = self.validationServers[arc4random() % serverCount];
        NSString *serverPath = [randomServer stringByAppendingPathComponent:@"production"];
        NSURL *url = [NSURL URLWithString:serverPath];
        
        //analytics
        if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidBeginVerificationForProduct:onServer:)]) [self.analyticsModule iapManagerDidBeginVerificationForProduct:productIdentifier onServer:serverPath];
        
        //prep url request
        NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:kGBIAP2TimeoutInterval];
        [urlRequest setHTTPMethod:@"POST"];
        [urlRequest setValue:@"application/octet-stream" forHTTPHeaderField:@"Content-Type"];
        [urlRequest setHTTPBody:transaction.transactionReceipt];
        
        //send url request
        dispatch_async(self.myQueue, ^{
            NSURLResponse *response;
            NSData *resultData = [NSURLConnection sendSynchronousRequest:urlRequest returningResponse:&response error:NULL];
            
            //process data into a string
            NSString *resultString = [[NSString alloc] initWithData:resultData encoding:NSUTF8StringEncoding];
            BOOL resultBool = [resultString isEqualToString:@"1"];
            
            //completed
            dispatch_async(dispatch_get_main_queue(), ^{
                //finish transaction
                [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
                
                //foo get the state
                GBIAP2VerificationState state = resultBool ? GBIAP2VerificationStateSuccess : GBIAP2VerificationStateFailed;
                
                //tell handlers that he exited the verification phase
                for (GBIAP2VerificationPhaseDidEndHandler handler in self.didEndVerificationPhaseHandlers) {
                    handler(productIdentifier, state, [self.solicitedPurchases containsObject:productIdentifier]);
                }
                
                //analytics
                if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidEndVerificationForProduct:onServer:success:)]) [self.analyticsModule iapManagerDidEndVerificationForProduct:productIdentifier onServer:serverPath state:state];
                
                //purchase
                if (transactionType == GBIAP2TransactionTypePurchase) {
                    //remove the product from the solicited purchases
                    [self.solicitedPurchases removeObject:productIdentifier];
                }
                //restore
                else if (transactionType == GBIAP2TransactionTypeRestore) {
                    self.isSolicitedRestoreInProgress = NO;
                }
                
                //if succesful
                if (state == GBIAP2VerificationStateSuccess) {
                    //call success handlers
                    for (GBIAP2PurchaseSuccessHandler handler in self.didSuccessfullyAcquireProductHandlers) {
                        handler(productIdentifier, transactionType);
                    }
                    
                    //analytics
                    if (self.analyticsModule && [self.analyticsModule respondsToSelector:@selector(iapManagerDidSuccessfullyAcquireProduct:withTransactionType:)]) [self.analyticsModule iapManagerDidSuccessfullyAcquireProduct:productIdentifier withTransactionType:transactionType];
                }
            });
        });
    }
}

#pragma mark - Metadata flow

-(void)addHandlerForDidBeginMetadataFetch:(GBIAP2MetadataFetchDidBeginHandler)handler {
    [self.didBeginMetadataFetchHandlers addObject:[handler copy]];
}

-(void)addHandlerForDidEndMetadataFetch:(GBIAP2MetadataFetchDidEndHandler)handler {
    [self.didEndMetadataFetchHandlers addObject:[handler copy]];
}

#pragma mark - Purchase flow

-(void)addHandlerForDidBeginPurchasePhase:(GBIAP2PurchasePhaseDidBeginHandler)handler {
    [self.didBeginPurchasePhaseHandlers addObject:[handler copy]];
}

-(void)addHandlerForDidEndPurchasePhase:(GBIAP2PurchasePhaseDidEndHandler)handler {
    [self.didEndPurchasePhaseHandlers addObject:[handler copy]];
}

-(void)addHandlerForDidBeginRestorePhase:(GBIAP2PurchasePhaseDidBeginHandler)handler {
    [self.didBeginRestorePhaseHandlers addObject:[handler copy]];
}

-(void)addHandlerForDidEndRestorePhase:(GBIAP2PurchasePhaseDidEndHandler)handler {
    [self.didEndRestorePhaseHandlers addObject:[handler copy]];
}

-(void)addHandlerForDidBeginVerificationPhase:(GBIAP2VerificationPhaseDidBeginHandler)handler {
    [self.didBeginVerificationPhaseHandlers addObject:[handler copy]];
}

-(void)addHandlerForDidEndVerificationPhase:(GBIAP2VerificationPhaseDidEndHandler)handler {
    [self.didEndVerificationPhaseHandlers addObject:[handler copy]];
}

#pragma mark - Product acquired

-(void)addHandlerForDidSuccessfullyAcquireProduct:(GBIAP2PurchaseSuccessHandler)handler {
    [self.didSuccessfullyAcquireProductHandlers addObject:[handler copy]];
}

@end
