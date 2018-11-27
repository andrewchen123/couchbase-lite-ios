//
//  Prediction.swift
//  CouchbaseLite
//
//  Copyright (c) 2018 Couchbase, Inc. All rights reserved.
//
//  Licensed under the Couchbase License Agreement (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  https://info.couchbase.com/rs/302-GJY-034/images/2017-10-30_License_Agreement.pdf
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation

public protocol PredictiveModel {
    
    func prediction(input: DictionaryObject) -> DictionaryObject?
    
}

public class Prediction {
    
    public func registerModel(_ model: PredictiveModel, withName name: String) {
        CBLDatabase.prediction().register(PredictiveModelBridge(model: model), withName: name)
    }
    
    public func unregisterModel(withName name: String) {
        CBLDatabase.prediction().unregisterModel(withName: name)
    }
    
}

class PredictiveModelBridge: NSObject, CBLPredictiveModel {
    
    let model: PredictiveModel
    
    init(model: PredictiveModel) {
        self.model = model
    }
    
    func prediction(_ input: CBLDictionary) -> CBLDictionary? {
        let inDict = DataConverter.convertGETValue(input) as! DictionaryObject
        return DataConverter.convertSETValue(model.prediction(input: inDict)) as? CBLDictionary
    }
    
}
