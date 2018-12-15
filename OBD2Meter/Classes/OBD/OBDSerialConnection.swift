//
//  Copyright © 2017 saiten. All rights reserved.
//

import Foundation
import RxSwift
import RxBluetoothKit

protocol OBDSerialConnection {
    func write(_ data: Data) -> Single<Void>
    func read() -> Observable<Data>
}

class BLEOBDSerialConnection: OBDSerialConnection {
    typealias Characteristics = (notify: Characteristic, write: Characteristic)
    
    let notifyCharacteristic: Characteristic
    let writeCharacteristic: Characteristic
    
    init(characteristics: Characteristics) {
        notifyCharacteristic = characteristics.notify
        writeCharacteristic = characteristics.write
    }
    
    func read() -> Observable<Data> {
        return notifyCharacteristic.observeValueUpdateAndSetNotification()
            .map { $0.value }
            .filter { $0 != nil }
            .map { $0! }
    }
    
    func write(_ data: Data) -> Single<Void> {
        return writeCharacteristic.writeValue(data, type: .withResponse)
            .map { _ in }
    }
}


