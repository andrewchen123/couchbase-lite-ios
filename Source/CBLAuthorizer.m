//
//  CBLAuthorizer.m
//  CouchbaseLite
//
//  Created by Jens Alfke on 5/21/12.
//  Copyright (c) 2012-2013 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//    http://www.apache.org/licenses/LICENSE-2.0
//  Unless required by applicable law or agreed to in writing, software distributed under the
//  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
//  either express or implied. See the License for the specific language governing permissions
//  and limitations under the License.

#import "CBLAuthorizer.h"
#import "CBLMisc.h"
#import "CBLBase64.h"
#import "MYURLUtils.h"
#import <Security/Security.h>


@implementation CBLPasswordAuthorizer

@synthesize credential=_credential;


- (instancetype) initWithCredential: (NSURLCredential*)credential {
    self = [super init];
    if (self) {
        if (!credential)
            return nil;
        Assert(credential.hasPassword);
        _credential = credential;
    }
    return self;
}


- (instancetype) initWithUser: (NSString*)user password: (NSString*)password {
    return [self initWithCredential: [NSURLCredential credentialWithUser: user
                                                                password: password
                                                     persistence: NSURLCredentialPersistenceNone]];
}


- (instancetype) initWithURL: (NSURL*)url {
    return [self initWithCredential: [url my_credentialForRealm: nil
                                      authenticationMethod: NSURLAuthenticationMethodHTTPBasic]];
}


- (NSString*) description {
    return $sprintf(@"%@[%@/****]", self.class, _credential.user);
}

@end


#pragma mark - ANCHOR CERTS:


static NSArray* sAnchorCerts;
static BOOL sOnlyTrustAnchorCerts;


void CBLSetAnchorCerts(NSArray* certs, BOOL onlyThese) {
    @synchronized([CBLPasswordAuthorizer class]) {
        sAnchorCerts = certs.copy;
        sOnlyTrustAnchorCerts = onlyThese;
    }
}


// Checks whether the reported problems with a SecTrust are OK for us
static BOOL acceptProblems(SecTrustRef trust, NSString* host) {
    BOOL localDomain = ([host hasSuffix: @".local"] || [host hasSuffix: @".local."]);
    NSDictionary* resultDict = CFBridgingRelease(SecTrustCopyResult(trust));
    NSArray* detailsArray = resultDict[@"TrustResultDetails"];
    NSUInteger i = 0;
    for (NSDictionary* details in detailsArray) {
        for (NSString* problem in details) {
            BOOL accept = NO;
            if ([problem isEqualToString: @"SSLHostname"] ||
                        [problem isEqualToString: @"AnchorTrusted"])
            {
                // Accept a self-signed cert from a local host (".local" domain)
                accept = (i == 0 && SecTrustGetCertificateCount(trust) == 1 && localDomain);
            }
            if (!accept)
                return NO;
        }
        i++;
    }
    return YES;
}


// Updates a SecTrust's result to kSecTrustResultProceed
static BOOL makeTrusted(SecTrustRef trust) {
    CFDataRef exception = SecTrustCopyExceptions(trust);
    if (!exception)
        return NO;
    SecTrustResultType result;
    SecTrustSetExceptions(trust, exception);
    SecTrustEvaluate(trust, &result);
    return YES;
}


BOOL CBLCheckSSLServerTrust(SecTrustRef trust, NSString* host, UInt16 port) {
    @synchronized([CBLPasswordAuthorizer class]) {
        if (sAnchorCerts.count > 0) {
            SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)sAnchorCerts);
            SecTrustSetAnchorCertificatesOnly(trust, sOnlyTrustAnchorCerts);
        }
    }
    SecTrustResultType result;
    OSStatus err = SecTrustEvaluate(trust, &result);
    if (err) {
        Warn(@"CBLCheckSSLServerTrust: SecTrustEvaluate failed with err %d", (int)err);
        return NO;
    }
    if (result == kSecTrustResultRecoverableTrustFailure) {
        if (acceptProblems(trust, host)) {
            makeTrusted(trust);
            result = kSecTrustResultUnspecified;
        }
    }
    if (result != kSecTrustResultProceed && result != kSecTrustResultUnspecified) {
        Warn(@"CBLCheckSSLServerTrust: SSL cert is not trustworthy (result=%d)", result);
        return NO;
    }
    return YES;
}
