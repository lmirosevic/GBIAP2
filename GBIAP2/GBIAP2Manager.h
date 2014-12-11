//
//  GBIAP2Manager.h
//  GBIAP2
//
//  Created by Luka Mirosevic on 21/05/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import <Foundation/Foundation.h>

#pragma mark - Types

typedef enum {
    GBIAP2MetadataFetchStateUnknown,
    GBIAP2MetadataFetchStateSuccess,
    GBIAP2MetadataFetchStateFailed,
} GBIAP2MetadataFetchState;

typedef enum {
    GBIAP2PurchaseStateUnknown,
    GBIAP2PurchaseStateSuccess,
    GBIAP2PurchaseStateCancelled,
    GBIAP2PurchaseStateFailed,
} GBIAP2PurchaseState;

typedef enum {
    GBIAP2VerificationStateUnknown,
    GBIAP2VerificationStateSuccess,
    GBIAP2VerificationStateFailed,
} GBIAP2VerificationState;

typedef enum {
    GBIAP2TransactionTypeUnknown,
    GBIAP2TransactionTypePurchase,
    GBIAP2TransactionTypeRePurchase,
    GBIAP2TransactionTypeRestore,
} GBIAP2TransactionType;

typedef enum {
    GBIAP2TransactionStateUnknown,
    GBIAP2TransactionStateSuccess,
    GBIAP2TransactionStateCancelled,
    GBIAP2TransactionStateFailed,
} GBIAP2TransactionState;

#pragma mark - Handler block types

//Enumeration
typedef void(^GBIAP2ProductHandler)(NSString *productIdentifier, NSString *title, NSString *description, NSString *formattedPrice, NSDecimalNumber *rawPrice);

//Metadata
typedef void(^GBIAP2MetadataFetchDidBeginHandler)(NSArray *productIdentifiers);
typedef void(^GBIAP2MetadataFetchDidEndHandler)(NSArray *productIdentifiers, GBIAP2MetadataFetchState fetchState);

//Purchase/restore requests
typedef void(^GBIAP2DidRequestPurchaseHandler)(NSString *productIdentifier);
typedef void(^GBIAP2DidRequestRestoreHandler)(void);

//Purchase or restore phase
typedef void(^GBIAP2PurchasePhaseDidBeginHandler)(NSString *productIdentifier, BOOL solicited);
typedef void(^GBIAP2PurchasePhaseDidEndHandler)(NSString *productIdentifier, GBIAP2PurchaseState purchaseState, BOOL solicited);

//Verification phase
typedef void(^GBIAP2VerificationPhaseDidBeginHandler)(NSString *productIdentifier, BOOL solicited);
typedef void(^GBIAP2VerificationPhaseDidEndHandler)(NSString *productIdentifier, GBIAP2VerificationState verificationState, BOOL solicited);

//Purchase acquiry
typedef void(^GBIAP2PurchaseDidCompleteHandler)(NSString *productIdentifier, GBIAP2TransactionType transactionType, GBIAP2TransactionState transactionState, BOOL solicited);


@protocol GBIAP2AnalyticsModule;

@interface GBIAP2 : NSObject

#pragma mark - Singleton

/**
 The shared purchase manager sinlgeton.
 */
+ (GBIAP2 *)purchaseManager;

//Conveniences
#define GBIAPManager [GBIAP2 purchaseManager]
#define GBIAP [GBIAP2 purchaseManager]

#pragma mark - Setup phase

/**
 Allows you to hook in an analytics or debugging module which will tell you when things happen. You can use this for debugging, or for pushing analytics data to yor favourite analytics provider.
 */
- (void)setAnalyticsModule:(id<GBIAP2AnalyticsModule>)analyticsModule;

/**
 Call this on app launch to resume any previous transactions which never completed. It's a good idea to register your handlers for the state transitions your interested in first (usually `addHandlerForDidSuccessfullyAcquireProduct`).
 */
- (void)resumePendingTransactions;

/**
 Use this property to set the location of the GBIAP2 validation servers.
 */
@property (copy, nonatomic, setter=registerValidationServers:) NSArray *validationServers;

#pragma mark - IAP prep phase

/**
 Initiate a metadata fetch for the products. Any handlers you added for (didBegin|didEnd)MetadataFetch will be called here.
 */
- (void)fetchMetadataForProducts:(NSArray *)productIdentifiers;

/**
 Initiate a metadata fetch for the products. Pass an optional block to send along some code to be executed upon success/failure. This method will also trigger any handlers you added for (didBegin|didEnd)MetadataFetch; the block you specify here will be called first (before any stored handlers).
 */
- (void)fetchMetadataForProducts:(NSArray *)productIdentifiers block:(GBIAP2MetadataFetchDidEndHandler)handler;

/**
 Enumerate the different products.
 */
- (void)enumerateFetchedProductsWithBlock:(GBIAP2ProductHandler)block showCurrencySymbol:(BOOL)shouldShowCurrencySymbol;

#pragma mark - Purchasing phase

/**
 Adds the purchase to the purchases queue.
 */
- (void)purchaseProductWithIdentifier:(NSString *)productIdentifier;

/**
 Starts the restore process
 */
- (void)restorePurchases;

#pragma mark - Purchase/Restore requests

/**
 Notifies you when a purchase was requested.
 */
- (void)addHandlerForDidRequestPurchase:(GBIAP2DidRequestPurchaseHandler)handler;

/**
 Notifies you when a restore was requested.
 */
- (void)addHandlerForDidRequestRestore:(GBIAP2DidRequestRestoreHandler)handler;

#pragma mark - Metadata flow

/**
 Notifies you when the metadata fetch did begin. You can use this to update your UI or start showing a loading indicator.
 */
- (void)addHandlerForDidBeginMetadataFetch:(GBIAP2MetadataFetchDidBeginHandler)handler;

/**
 Notifies you when the metadata fetch did end. You can use this to update your UI, stop showing a loading indicator, and show a potential error message.
 */
- (void)addHandlerForDidEndMetadataFetch:(GBIAP2MetadataFetchDidEndHandler)handler;

#pragma mark - Purchase flow

/* The following notify you as the purchase flow progresses. Use these to update UI, but note that these might be called for transactions which were unfinished from a previous session, if this is the case the `solicited` flag will be set to NO. To unlock purchases, you should use `addHandlerForDidCompletePurchaseFlow:`, it will get called both whether you've solicited the purchase in this session or if it was left over from a previous session. You might not get called the verification ones if you don't get that far, but you'll always get them in pairs. */

/**
 The purchase phase did begin, this step usually involves talking to Apple's servers (unless the device is jailbroken, in which case not).
 */
- (void)addHandlerForDidBeginPurchasePhase:(GBIAP2PurchasePhaseDidBeginHandler)handler;

/**
 The purchase phase concluded. If the device was jailbroken, then this might return a success purchase state; for this reason you should not use this method to unlock purchases!
 */
- (void)addHandlerForDidEndPurchasePhase:(GBIAP2PurchasePhaseDidEndHandler)handler;

/**
 The restore phase did begin, this step usually involves talking to Apple's servers (unless the device is jailbroken, in which case not).
 */
- (void)addHandlerForDidBeginRestorePhase:(GBIAP2PurchasePhaseDidBeginHandler)handler;

/**
 The restore phases concluded. If the device was jailbroken, then this might return a success purchase state; for this reason you should not use this method to unlock purchases!
 */
- (void)addHandlerForDidEndRestorePhase:(GBIAP2PurchasePhaseDidEndHandler)handler;

/**
 The verification phase began with your own validation servers. This should not be affected by jailbroken devices and their IAP hacks.
 */
- (void)addHandlerForDidBeginVerificationPhase:(GBIAP2VerificationPhaseDidBeginHandler)handler;

/**
 The verification phase concluded. This is the last stage in the purchase flow. Even though this method could be used to unlock purchases, it is advised that you use the more aptly named method `addHandlerForDidSuccessfullyAcquireProduct`, as it will simplify your code and isolate you from the individual purchase steps.
 */
- (void)addHandlerForDidEndVerificationPhase:(GBIAP2VerificationPhaseDidEndHandler)handler;

#pragma mark - Product acquired

/**
 You should use this to unlock the purchase, this gets called regardless of whether you've solicited the purchase or whether it was left over from a previous session, or whether it's a fresh purchase or restore. This is genrally what you want.
 */
- (void)addHandlerForDidSuccessfullyAcquireProduct:(GBIAP2PurchaseDidCompleteHandler)handler;

/**
 The purchase failed to conclude. You are not given information as to why it failed, for this use the "Purchase flow" handlers.
 */
- (void)addHandlerForDidFailToAcquireProduct:(GBIAP2PurchaseDidCompleteHandler)handler;

@end

@protocol GBIAP2AnalyticsModule <NSObject>
@optional

- (void)iapManagerDidResumeTransactions;
- (void)iapManagerDidRegisterValidationServers:(NSArray *)servers;

- (void)iapManagerUserDidRequestMetadataForProducts:(NSArray *)productIdentifiers;
- (void)iapManagerUserDidRequestPurchaseForProduct:(NSString *)productIdentifier;
- (void)iapManagerUserDidRequestRestore;

- (void)iapManagerDidBeginMetadataFetchForProducts:(NSArray *)productIdentifiers;
- (void)iapManagerDidEndMetadataFetchForProducts:(NSArray *)productIdentifiers state:(GBIAP2MetadataFetchState)state;

- (void)iapManagerDidBeginPurchaseForProduct:(NSString *)productIdentifier;
- (void)iapManagerDidEndPurchaseForProduct:(NSString *)productIdentifier state:(GBIAP2PurchaseState)state solicited:(BOOL)solicited;

- (void)iapManagerDidBeginRestore;
- (void)iapManagerDidEndRestoreForProduct:(NSString *)productIdentifier state:(GBIAP2PurchaseState)state solicited:(BOOL)solicited;

- (void)iapManagerDidBeginVerificationForProduct:(NSString *)productIdentifier onServer:(NSString *)server;
- (void)iapManagerDidEndVerificationForProduct:(NSString *)productIdentifier onServer:(NSString *)server state:(GBIAP2VerificationState)state;

- (void)iapManagerDidSuccessfullyAcquireProduct:(NSString *)productIdentifier withTransactionType:(GBIAP2TransactionType)transactionType transactionState:(GBIAP2TransactionState)transactionState solicited:(BOOL)solicited;
- (void)iapManagerDidFailToAcquireProduct:(NSString *)productIdentifier withTransactionType:(GBIAP2TransactionType)transactionType transactionState:(GBIAP2TransactionState)transactionState solicited:(BOOL)solicited;

@end