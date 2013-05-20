//
//  GBIAP2.h
//  GBIAP2
//
//  Created by Luka Mirosevic on 20/05/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

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
    GBIAP2TransactionTypeRestore,
} GBIAP2TransactionType;


#pragma mark - Handler block types

//Enumeration
typedef void(^GBIAP2ProductHandler)(NSString *productIdentifier, NSString *title, NSString *description, NSString *formattedPrice);

//Metadata
typedef void(^GBIAP2MetadataFetchDidBeginHandler)(NSArray *productIdentifiers);
typedef void(^GBIAP2MetadataFetchDidEndHandler)(NSArray *productIdentifiers, GBIAP2MetadataFetchState fetchState);

//Purchase or restore phase
typedef void(^GBIAP2PurchasePhaseDidBeginHandler)(NSString *productIdentifier, BOOL solicited);
typedef void(^GBIAP2PurchasePhaseDidEndHandler)(NSString *productIdentifier, GBIAP2PurchaseState purchaseState, BOOL solicited);

//Verification phase
typedef void(^GBIAP2VerificationPhaseDidBeginHandler)(NSString *productIdentifier, BOOL solicited);
typedef void(^GBIAP2VerificationPhaseDidEndHandler)(NSString *productIdentifier, GBIAP2VerificationState verificationState, BOOL solicited);

//Purchase acquiry
typedef void(^GBIAP2PurchaseSuccessHandler)(NSString *productIdentifier, GBIAP2TransactionType transactionType);




@protocol GBIAP2AnalyticsModule;

@interface GBIAP2 : NSObject

#pragma mark - Singleton

+(GBIAP2 *)purchaseManager;
//Just a quick convenience
#define GBIAPManager [GBIAP2 purchaseManager]

#pragma mark - Setup phase

//Allows you to hook in an analytics or debugging module which will tell you when things happen. For pushing stuff to flurry, google analytics, localytics, etc. detecting piracy, etc. etc.
-(void)setAnalyticsModule:(id<GBIAP2AnalyticsModule>)analyticsModule;

//Call this on app launch to resume any previous transactions which never completed. But it's a good idea to put all your handling logic etc in place first
-(void)resumePendingTransactions;

//Servers used for validating IAP receipts
-(void)registerValidationServers:(NSArray *)validationServers;
-(NSArray *)validationServers;

#pragma mark - IAP prep phase

//Fetch metadata for products. Add a handler to process it
-(void)fetchMetadataForProducts:(NSArray *)productIdentifiers;

//Enumerate the different products
-(void)enumerateFetchedProductsWithBlock:(GBIAP2ProductHandler)block showCurrencySymbol:(BOOL)shouldShowCurrencySymbol;

#pragma mark - Purchasing phase

//Adds the purchase to the list of purchases
-(void)enqueuePurchaseWithIdentifier:(NSString *)productIdentifier;

//Starts the restore process
-(void)restorePurchases;

#pragma mark - Metadata flow

//Notifies you when the metadata fetch flow progresses. Use this to update UI primarily.
-(void)addHandlerForDidBeginMetadataFetch:(GBIAP2MetadataFetchDidBeginHandler)handler;
-(void)addHandlerForDidEndMetadataFetch:(GBIAP2MetadataFetchDidEndHandler)handler;

#pragma mark - Purchase flow

//Notifies you as the purchase flow progresses. Use these to update UI, but note that these might be called for transactions which were unfinished from a previous session, if this is the case the `solicited` flag will be set to NO. To unlock purchases, you should use `addHandlerForDidCompletePurchaseFlow:`, it will get called whether you've solicited the purchase in this session or whether it was left over from a previous session. You might not get called the verification ones if you don't get that far but you'll always get them in pairs.
-(void)addHandlerForDidBeginPurchasePhase:(GBIAP2PurchasePhaseDidBeginHandler)handler;
-(void)addHandlerForDidEndPurchasePhase:(GBIAP2PurchasePhaseDidEndHandler)handler;
-(void)addHandlerForDidBeginRestorePhase:(GBIAP2PurchasePhaseDidBeginHandler)handler;
-(void)addHandlerForDidEndRestorePhase:(GBIAP2PurchasePhaseDidEndHandler)handler;
-(void)addHandlerForDidBeginVerificationPhase:(GBIAP2VerificationPhaseDidBeginHandler)handler;
-(void)addHandlerForDidEndVerificationPhase:(GBIAP2VerificationPhaseDidEndHandler)handler;

#pragma mark - Product acquired

//You would use this to unlock the purchase, this gets called regardless of whether you've solicited the purchase or whether it was left over from a previous session, or whether it's a fresh purchase or restore
-(void)addHandlerForDidSuccessfullyAcquireProduct:(GBIAP2PurchaseSuccessHandler)handler;

@end

@protocol GBIAP2AnalyticsModule <NSObject>
@optional

-(void)iapManagerDidResumeTransactions;
-(void)iapManagerDidRegisterValidationServers:(NSArray *)servers;

-(void)iapManagerUserDidRequestMetadataForProducts:(NSArray *)productIdentifiers;
-(void)iapManagerUserDidRequestPurchaseForProduct:(NSString *)productIdentifier;
-(void)iapManagerUserDidRequestRestore;

-(void)iapManagerDidBeginMetadataFetchForProducts:(NSArray *)productIdentifiers;
-(void)iapManagerDidEndMetatdataFetchForProducts:(NSArray *)productIdentifiers state:(GBIAP2MetadataFetchState)state;

-(void)iapManagerDidBeginPurchaseForProduct:(NSString *)productIdentifier;
-(void)iapManagerDidEndPurchaseForProduct:(NSString *)productIdentifier state:(GBIAP2PurchaseState)state solicited:(BOOL)solicited;

-(void)iapManagerDidBeginRestore;
-(void)iapManagerDidEndRestoreForProduct:(NSString *)productIdentifier state:(GBIAP2PurchaseState)state solicited:(BOOL)solicited;

-(void)iapManagerDidBeginVerificationForProduct:(NSString *)productIdentifier onServer:(NSString *)server;
-(void)iapManagerDidEndVerificationForProduct:(NSString *)productIdentifier onServer:(NSString *)server state:(GBIAP2VerificationState)state;

-(void)iapManagerDidSuccessfullyAcquireProduct:(NSString *)productIdentifier withTransactionType:(GBIAP2TransactionType)solicited;

@end