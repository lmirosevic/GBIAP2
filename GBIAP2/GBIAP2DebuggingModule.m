//
//  GBIAP2DebuggingModule.m
//  GBIAP2
//
//  Created by Luka Mirosevic on 21/05/2013.
//  Copyright (c) 2013 Goonbee. All rights reserved.
//

#import "GBIAP2DebuggingModule.h"

@implementation GBIAP2DebuggingModule

-(void)iapManagerDidResumeTransactions {
    NSLog(@"iapManagerDidResumeTransactions");
}

-(void)iapManagerDidRegisterValidationServers:(NSArray *)servers {
    NSLog(@"iapManagerDidRegisterValidationServers:%@", servers);
}

-(void)iapManagerUserDidRequestMetadataForProducts:(NSArray *)productIdentifiers {
    NSLog(@"iapManagerUserDidRequestMetadataForProducts:%@", productIdentifiers);
}

-(void)iapManagerUserDidRequestPurchaseForProduct:(NSString *)productIdentifier {
    NSLog(@"iapManagerUserDidRequestPurchaseForProduct:%@", productIdentifier);
}

-(void)iapManagerUserDidRequestRestore {
    NSLog(@"iapManagerUserDidRequestRestore");
}

-(void)iapManagerDidBeginMetadataFetchForProducts:(NSArray *)productIdentifiers {
    NSLog(@"iapManagerDidBeginMetadataFetchForProducts:%@", productIdentifiers);
}

-(void)iapManagerDidEndMetadataFetchForProducts:(NSArray *)productIdentifiers state:(GBIAP2MetadataFetchState)state  {
    NSLog(@"iapManagerDidEndMetatdataFetchForProducts:%@ state:%d", productIdentifiers, state);
}

-(void)iapManagerDidBeginPurchaseForProduct:(NSString *)productIdentifier {
    NSLog(@"iapManagerDidBeginPurchaseForProduct:%@", productIdentifier);
}

-(void)iapManagerDidEndPurchaseForProduct:(NSString *)productIdentifier state:(GBIAP2PurchaseState)state solicited:(BOOL)solicited {
    NSLog(@"iapManagerDidEndPurchaseForProduct:%@ state: %d solicited:%@", productIdentifier, state, solicited?@"YES":@"NO");
}

-(void)iapManagerDidBeginRestore {
    NSLog(@"iapManagerDidBeginRestore");
}

-(void)iapManagerDidEndRestoreForProduct:(NSString *)productIdentifier state:(GBIAP2PurchaseState)state solicited:(BOOL)solicited {
    NSLog(@"iapManagerDidEndRestoreForProduct:%@ state:%d solicited:%@", productIdentifier, state, solicited?@"YES":@"NO");
}

-(void)iapManagerDidBeginVerificationForProduct:(NSString *)productIdentifier onServer:(NSString *)server {
    NSLog(@"iapManagerDidBeginVerificationForProduct:%@ onServer:%@", productIdentifier, server);
}

-(void)iapManagerDidEndVerificationForProduct:(NSString *)productIdentifier onServer:(NSString *)server state:(GBIAP2VerificationState)state {
    NSLog(@"iapManagerDidEndVerificationForProduct:%@ onServer:%@ state:%d", productIdentifier, server, state);
}

-(void)iapManagerDidSuccessfullyAcquireProduct:(NSString *)productIdentifier withTransactionType:(GBIAP2TransactionType)transactionType transactionState:(GBIAP2TransactionState)transactionState solicited:(BOOL)solicited {
    NSLog(@"iapManagerDidSuccessfullyAcquireProduct:%@ withTransactionType:%d transactionState:%d solicited:%@", productIdentifier, transactionType, transactionState, solicited?@"YES":@"NO");
}

-(void)iapManagerDidFailToAcquireProduct:(NSString *)productIdentifier withTransactionType:(GBIAP2TransactionType)transactionType transactionState:(GBIAP2TransactionState)transactionState solicited:(BOOL)solicited {
    NSLog(@"iapManagerDidFailToAcquireProduct:%@ withTransactionType:%d transactionState:%d solicited:%@", productIdentifier, transactionType, transactionState, solicited?@"YES":@"NO");
}

@end
