//
//  Copyright © 2017 saiten. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa
import RxSwiftExt
import CoreBluetooth
import RxBluetoothKit

private let ServiceUUID = CBUUID(data: Data(bytes: [0xff, 0xf0]))
private let NotifyCharacteristicUUID = CBUUID(data: Data(bytes: [0xff, 0xf1]))
private let WriteCharacteristicUUID = CBUUID(data: Data(bytes: [0xff, 0xf2]))

private let InitializeCommands: [String] = [
    // 電圧を取得
    "AT RV",
    // ELM インターフェイス名取得
    "ATI",
    "AT PC",
    "AT D",
    "AT E0",
    // Set Protocol to h and save it
    "AT SP 5",
    "AT IB 10",
    "AT KW0",
    // レスポンスタイムアウト設定
    "AT ST 80",
    "AT IIA 10",
    // Set Header to wwxxyyzz
    "AT SH 81 10 F0",
    // サポートするPID[01-20]を取得
    // ex) 08 3E 98 01
    //       0000 1000 0011 1110 1001 1000 0000 0001
    //     Support PID
    //       05,0B,0C,0D,0E,0F,11,14,15,20
    "21 00 01",
]

private let GetSpeedCommand = "21 0D 01"
private let GetEngineRPMCommand = "21 0C 01"
private let GetBoostCommand = "21 0B 01"

protocol ViewModelInputs {
    var connect: PublishSubject<Void> { get }
}

protocol ViewModelOutputs {
    var isConnected: Driver<Bool> { get }
    var isInitialized: Driver<Bool> { get }
    
    var speed: Driver<Double> { get }
    var rpm: Driver<Double> { get }
    var boost: Driver<Double> { get }
    
    var log: Driver<String> { get }
}

protocol ViewModelType {
    var inputs: ViewModelInputs { get }
    var outputs: ViewModelOutputs { get }
}

class ViewModel: ViewModelType, ViewModelInputs, ViewModelOutputs {
    var inputs: ViewModelInputs { return self }
    var outputs: ViewModelOutputs { return self }

    // Inputs
    let connect = PublishSubject<Void>()

    // Outputs
    var isConnected: Driver<Bool> {
        return peripheral.asObservable()
            .map { $0?.isConnected ?? false }
            .asDriver(onErrorJustReturn: false)
    }
    
    var isInitialized: Driver<Bool> {
        return _isInitialized.asDriver()
    }
    let _isInitialized = BehaviorRelay<Bool>(value: false)

    private(set) lazy var speed: Driver<Double> = {
        isInitialized
            .flatMapLatest { [weak self] initialized -> Driver<Double> in
                guard let wSelf = self else { return .empty() }
                if initialized {
                    return wSelf.observeSpeed()
                        .asDriver(onErrorDriveWith: .empty())
                } else {
                    return .just(0.0)
                }
            }
        
    }()
    
    private(set) lazy var rpm: Driver<Double> = {
        isInitialized
            .flatMapLatest { [weak self] initialized -> Driver<Double> in
                guard let wSelf = self else { return .empty() }
                if initialized {
                    return wSelf.observeEngineRPM()
                        .asDriver(onErrorDriveWith: .empty())
                } else {
                    return .just(0.0)
                }
        }
        
    }()

    private(set) lazy var boost: Driver<Double> = {
        isInitialized
            .flatMapLatest { [weak self] initialized -> Driver<Double> in
                guard let wSelf = self else { return .empty() }
                if initialized {
                    return wSelf.observeBoost()
                        .asDriver(onErrorDriveWith: .empty())
                } else {
                    return .just(-1.0)
                }
        }
        
    }()

    var log: Driver<String> {
        return _log.asDriver(onErrorDriveWith: .empty())
    }
    var _log = BehaviorRelay<String>(value: "")
    
    var error: Driver<Error> {
        return _error.asDriver(onErrorDriveWith: .empty())
    }
    let _error = PublishSubject<Error>()
    
    private let communicator = BehaviorRelay<OBDCommunicater?>(value: nil)
    private let peripheral = BehaviorRelay<Peripheral?>(value: nil)
    private let disposeBag = DisposeBag()
    
    init() {
        let start = connect.withLatestFrom(isConnected).filter { !$0 }
        let stop = connect.withLatestFrom(isConnected).filter { $0 }

        start
            .flatMapLatest { [unowned self] _ in self.scan(ServiceUUID) }
            .catchError { [unowned self] in
                self._error.onNext($0)
                return .empty()
            }
            .bind(to: peripheral)
            .disposed(by: disposeBag)
        
        stop
            .withLatestFrom(peripheral.asObservable())
            .unwrap()
            .observeOn(MainScheduler.instance)
            .map { _ -> Peripheral? in nil }
            .bind(to: peripheral)
            .disposed(by: disposeBag)
        
        peripheral.asObservable()
            .do(onNext: { [weak self] in
                if $0 != nil {
                    self?.logged("OBD2 device connected")
                } else {
                    self?.logged("OBD2 device disconnected")
                }
            })
            .flatMapLatest { [unowned self] peripheral -> Observable<OBDCommunicater?> in
                if let peripheral = peripheral {
                    return self.createOBDCommunicater(peripheral,
                                                      ServiceUUID,
                                                      NotifyCharacteristicUUID,
                                                      WriteCharacteristicUUID)
                        .map { Optional($0) }
                        .catchError {
                            self._error.onNext($0)
                            return .just(nil)
                        }
                } else {
                    return .just(nil)
                }
            }
            .bind(to: communicator)
            .disposed(by: disposeBag)

        let sendInitializeCommands = communicator
            .unwrap()
            .do(onNext: { [weak self] _ in self?.logged("send initialize command") })
            .flatMap { communicator -> Observable<Void> in
                return communicator.send(commands: InitializeCommands).asObservable()
            }
            .share(replay: 1)
        
        Observable
            .of(sendInitializeCommands.map { true },
                peripheral.asObservable().filter { $0 == nil }.map { _ in false })
            .merge()
            .do(onNext: { [weak self] in
                if $0 { self?.logged("OBD2 communictor initialized") }
            })
            .bind(to: _isInitialized)
            .disposed(by: disposeBag)
        
        _error
            .map { "error: \($0)" }
            .subscribe(onNext: logged)
            .disposed(by: disposeBag)
    }
    
    private func scan(_ serviceUUID: CBUUID) -> Observable<Peripheral> {
        let manager = CentralManager(queue: .main, options: nil)

        return manager.observeState()
            .filter { $0 == .poweredOn }
            .timeout(15.0, scheduler: MainScheduler.asyncInstance)
            .take(1)
            .flatMap { _ -> Observable<ScannedPeripheral> in
                manager.scanForPeripherals(withServices: [serviceUUID])
            }
            .flatMap { $0.peripheral.establishConnection() }
    }
    
    private func createOBDCommunicater(_ peripheral: Peripheral,
                                           _ serviceUUID: CBUUID,
                                           _ notifyCharacteristicUUID: CBUUID,
                                           _ writeCharacteristicUUID: CBUUID) -> Observable<OBDCommunicater> {
        return peripheral.discoverServices([serviceUUID])
            .asObservable()
            .flatMap { Observable.from($0) }
            .flatMap { $0.discoverCharacteristics([notifyCharacteristicUUID, writeCharacteristicUUID]) }
            .flatMap { characteristics -> Observable<BLEOBDSerialConnection.Characteristics> in
                if let notify = characteristics.first(where: { $0.uuid == notifyCharacteristicUUID }),
                   let write = characteristics.first(where: {$0.uuid == writeCharacteristicUUID }) {
                    return .just((notify: notify, write: write))
                } else {
                    return .empty()
                }
            }
            .map { BLEOBDSerialConnection(characteristics: $0) }
            .map { OBDCommunicater(connection: $0) }
    }
    
    private func observeSpeed() -> Observable<Double> {
        // 定期的に速度を取得する
        return Observable<Int>.interval(1.0, scheduler: MainScheduler.asyncInstance)
            .withLatestFrom(communicator)
            .unwrap()
            .concatMap {
                $0.send(command: GetSpeedCommand).asObservable()
            }
            .map {  Double(parse(response: $0)) }
    }

    private func observeEngineRPM() -> Observable<Double> {
        // 定期的にエンジン回転数を取得する
        return Observable<Int>.interval(1.0, scheduler: MainScheduler.asyncInstance)
            .withLatestFrom(communicator)
            .unwrap()
            .concatMap {
                $0.send(command: GetEngineRPMCommand).asObservable()
            }
            .map {  Double(parse(response: $0)) * 0.25 }
    }

    private func observeBoost() -> Observable<Double> {
        // 定期的にブースト値を取得する
        return Observable<Int>.interval(1.0, scheduler: MainScheduler.asyncInstance)
            .withLatestFrom(communicator)
            .unwrap()
            .concatMap {
                $0.send(command: GetBoostCommand).asObservable()
            }
            .map {  Double(parse(response: $0)) / 100.0 }
    }
    
    private func logged(_ log: String) {
        _log.accept(_log.value + log + "\n")
    }
    
}

private func parse(response: String) -> Int {
    // 雑
    let value = response.trimmingCharacters(in: .whitespacesAndNewlines).filter { $0 != " " }.dropFirst(4)
    return Int(value, radix: 16)!
}

