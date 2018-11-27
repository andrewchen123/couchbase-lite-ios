//
//  PredictiveQueryTest.m
//  CBL ObjC Tests
//
//  Created by Pasin Suriyentrakorn on 11/21/18.
//  Copyright © 2018 Couchbase. All rights reserved.
//

#import "CBLTestCase.h"

#define PREDICTION_VALUE(MODEL, IN, PROPERTY) \
    [[CBLQueryFunction predictionUsingModel: (MODEL) input: (IN)] property: PROPERTY]

#define SEL_PREDICTION_VALUE(MODEL, IN, PROPERTY) SEL_EXPR(PREDICTION_VALUE(MODEL, IN, PROPERTY))

#define PREDICTION(MODEL, IN) \
    [CBLQueryFunction predictionUsingModel: (MODEL) input: (IN)]

#define SEL_PREDICTION(MODEL, IN) SEL_EXPR(PREDICTION(MODEL, IN))

@interface CBLAggregateModel: NSObject <CBLPredictiveModel>

@property (nonatomic) NSInteger numberOfCalls;

@end

@interface PredictiveQueryTest : CBLTestCase

@end

@implementation PredictiveQueryTest

- (CBLMutableDocument*) createDocWithNumbers: (NSArray*)numbers {
    CBLMutableDocument* doc = [[CBLMutableDocument alloc] init];
    [doc setValue: numbers forKey: @"numbers"];
    [self saveDocument: doc];
    return doc;
}

- (void) testRegisterAndUnregisterModel {
    [self createDocWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocWithNumbers: @[@6, @7, @8, @9, @10]];
    
    // Query:
    id model = EXPR_VAL(@"aggregate");
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers"),
                                             SEL_PREDICTION(model, input)]
                                     from: kDATA_SRC_DB];
    
    // Test query before registering the model:
    [self expectError: @"CouchbaseLite.SQLite" code: 1 in:^BOOL(NSError **err) {
        return [q execute: err] != nil;
    }];
    
    [CBLDatabase.prediction registerModel: [[CBLAggregateModel alloc] init] withName: @"aggregate"];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        CBLDictionary* pred = [r dictionaryAtIndex: 1];
        
        Assert(numbers.count > 0);
        AssertNotNil(pred);
        AssertEqual([pred integerForKey: @"sum"], [[numbers valueForKeyPath:@"@sum.self"] integerValue]);
        AssertEqual([pred integerForKey: @"min"], [[numbers valueForKeyPath:@"@min.self"] integerValue]);
        AssertEqual([pred integerForKey: @"max"], [[numbers valueForKeyPath:@"@max.self"] integerValue]);
        AssertEqual([pred integerForKey: @"avg"], [[numbers valueForKeyPath:@"@avg.self"] integerValue]);
    }];
    AssertEqual(numRows, 2u);
    
    [CBLDatabase.prediction unregisterModelWithName: @"aggregate"];
    
    // Test query after unregistering the model:
    
    // TODO: Should we make SQLite error domain public:
    [self expectError: @"CouchbaseLite.SQLite" code: 1 in:^BOOL(NSError **err) {
        return [q execute: err] != nil;
    }];
}

- (void) testQueryDictionaryResult {
    
}

- (void) testQueryValueInDictionaryResult {
    [self createDocWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocWithNumbers: @[@6, @7, @8, @9, @10]];
    
    [CBLDatabase.prediction registerModel: [[CBLAggregateModel alloc] init]
                                 withName: @"aggregate"];
    
    // Query:
    id model = EXPR_VAL(@"aggregate");
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers"),
                                             SEL_EXPR_AS(PREDICTION_VALUE(model, input, @"sum"), @"sum")]
                                     from: kDATA_SRC_DB];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: YES
                                    test: ^(uint64_t n, CBLQueryResult *r)
    {
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        NSInteger sum = [r integerAtIndex: 1];
        AssertEqual(sum, [r integerForKey: @"sum"]);
        Assert(numbers.count > 0);
        AssertEqual(sum, [[numbers valueForKeyPath:@"@sum.self"] integerValue]);
    }];
    AssertEqual(numRows, 2u);
    
    [CBLDatabase.prediction unregisterModelWithName: @"aggregate"];
}

- (void) testQueryWithBlobInput {
    
}

- (void) testIndexPredictionValue {
    [self createDocWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [CBLDatabase.prediction registerModel: aggregateModel
                                 withName: @"aggregate"];
    
    id model = EXPR_VAL(@"aggregate");
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction = PREDICTION_VALUE(model, input, @"sum");
    
    // Query without index
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers"),
                                             SEL_EXPR_AS(sumPrediction, @"sum")]
                                     from: kDATA_SRC_DB
                                    where: [sumPrediction equalTo: EXPR_VAL(@15)]];
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO test: ^(uint64_t n, CBLQueryResult *r) {
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        NSInteger sum = [r integerAtIndex: 1];
        AssertEqual(sum, [r integerForKey: @"sum"]);
        Assert(numbers.count > 0);
        AssertEqual(sum, [[numbers valueForKeyPath:@"@sum.self"] integerValue]);
    }];
    AssertEqual(numRows, 1u);
    Assert(aggregateModel.numberOfCalls > 2); // Functions would be called manay times
    
    aggregateModel.numberOfCalls = 0;
    
    // Index:
    NSError* error;
    NSArray* indexItems = @[[CBLValueIndexItem expression: sumPrediction]];
    CBLValueIndex* index = [CBLIndexBuilder valueIndexWithItems: indexItems];
    Assert([self.db createIndex: index withName: @"SumIndex" error: &error]);
    
    // Query again:
    numRows = [self verifyQuery: q randomAccess: NO  test: ^(uint64_t n, CBLQueryResult *r) {
        NSArray* numbers = [[r arrayAtIndex:0] toArray];
        NSInteger sum = [r integerAtIndex: 1];
        AssertEqual(sum, [r integerForKey: @"sum"]);
        Assert(numbers.count > 0);
        AssertEqual(sum, [[numbers valueForKeyPath:@"@sum.self"] integerValue]);
    }];
    AssertEqual(numRows, 1u);
    AssertEqual(aggregateModel.numberOfCalls, 2u); // The value should be cached by the index
    
    // NOTE: Cannot unregister model as index is still using the model
    // [CBLDatabase.prediction unregisterModelWithName: @"aggregate"];
}

- (void) testIndexMultiplePredictiveValues {
    [self createDocWithNumbers: @[@1, @2, @3, @4, @5]];
    [self createDocWithNumbers: @[@6, @7, @8, @9, @10]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [CBLDatabase.prediction registerModel: aggregateModel
                                 withName: @"aggregate"];
    
    id model = EXPR_VAL(@"aggregate");
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction = PREDICTION_VALUE(model, input, @"sum");
    CBLQueryExpression* avgPrediction = PREDICTION_VALUE(model, input, @"avg");
    
    NSError* error;
    CBLValueIndex* avgIndex = [CBLIndexBuilder valueIndexWithItems: @[[CBLValueIndexItem expression: avgPrediction]]];
    Assert([self.db createIndex: avgIndex withName: @"AvgIndex" error: &error]);
    
    CBLValueIndex* sumIndex = [CBLIndexBuilder valueIndexWithItems: @[[CBLValueIndexItem expression: sumPrediction]]];
    Assert([self.db createIndex: sumIndex withName: @"SumIndex" error: &error]);
    
    // Query:
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers"),
                                             SEL_EXPR_AS(sumPrediction, @"sum"),
                                             SEL_EXPR_AS(avgPrediction, @"avg")]
                                     from: kDATA_SRC_DB
                                    where: [ [avgPrediction equalTo: EXPR_VAL(@8)] orExpression: [sumPrediction equalTo: EXPR_VAL(@15)] ]
                   ];
    
    NSLog(@"%@", [q explain: nil]);
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                    test: ^(uint64_t n, CBLQueryResult *r)
                        {
                            NSArray* numbers = [[r arrayAtIndex:0] toArray];
                            NSInteger sum = [r integerAtIndex: 1];
                            AssertEqual(sum, [r integerForKey: @"sum"]);
                            Assert(numbers.count > 0);
                            AssertEqual(sum, [[numbers valueForKeyPath:@"@sum.self"] integerValue]);
                        }];
    AssertEqual(numRows, 2u);
}

- (void) testIndexCompoundPredictiveValues {
    [self createDocWithNumbers: @[@1, @2, @3, @4, @5]];
    
    CBLAggregateModel* aggregateModel = [[CBLAggregateModel alloc] init];
    [CBLDatabase.prediction registerModel: aggregateModel
                                 withName: @"aggregate"];
    
    id model = EXPR_VAL(@"aggregate");
    id input = EXPR_VAL(@{ @"numbers": EXPR_PROP(@"numbers") });
    CBLQueryExpression* sumPrediction1 = [CBLQueryFunction abs: PREDICTION_VALUE(model, input, @"sum")];
    CBLQueryExpression* sumPrediction2 = [CBLQueryFunction power: PREDICTION_VALUE(model, input, @"sum") exponent:EXPR_VAL(@2)];
    
    NSError* error;
    CBLValueIndex* sumIndex1 = [CBLIndexBuilder valueIndexWithItems:
                                @[[CBLValueIndexItem expression: sumPrediction1]]];
    Assert([self.db createIndex: sumIndex1 withName: @"SumIndex1" error: &error]);
    
    CBLValueIndex* sumIndex2 = [CBLIndexBuilder valueIndexWithItems:
                                @[[CBLValueIndexItem expression: sumPrediction2]]];
    Assert([self.db createIndex: sumIndex2 withName: @"SumIndex2" error: &error]);
    
    // Query:
    CBLQuery *q = [CBLQueryBuilder select: @[SEL_PROP(@"numbers"),
                                             SEL_EXPR_AS(sumPrediction1, @"sum")]
                                     from: kDATA_SRC_DB
                                    where: [[sumPrediction1 equalTo: EXPR_VAL(@15)] orExpression:
                                            [sumPrediction2 greaterThan: EXPR_VAL(@17)]]];
    
    NSLog(@"%@", [q explain: nil]);
    
    uint64_t numRows = [self verifyQuery: q randomAccess: NO
                                    test: ^(uint64_t n, CBLQueryResult *r)
                        {
                            NSArray* numbers = [[r arrayAtIndex:0] toArray];
                            NSInteger sum = [r integerAtIndex: 1];
                            AssertEqual(sum, [r integerForKey: @"sum"]);
                            Assert(numbers.count > 0);
                            AssertEqual(sum, [[numbers valueForKeyPath:@"@sum.self"] integerValue]);
                        }];
    AssertEqual(numRows, 1u);
    AssertEqual(aggregateModel.numberOfCalls, 2u); // Query was executed twice
}

@end

#pragma mark - CBLAggregateModel

@implementation CBLAggregateModel

@synthesize numberOfCalls=_numberOfCalls;

- (CBLDictionary*) prediction: (CBLDictionary*)input {
    _numberOfCalls++;
    
    NSArray* numbers = [[input arrayForKey: @"numbers"] toArray];
    if (!numbers)
        return nil;

    CBLMutableDictionary* output = [[CBLMutableDictionary alloc] init];
    [output setValue: [numbers valueForKeyPath:@"@sum.self"] forKey: @"sum"];
    [output setValue: [numbers valueForKeyPath:@"@min.self"] forKey: @"min"];
    [output setValue: [numbers valueForKeyPath:@"@max.self"] forKey: @"max"];
    [output setValue: [numbers valueForKeyPath:@"@avg.self"] forKey: @"avg"];
    return output;
}

@end
