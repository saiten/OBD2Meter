//
//  Copyright © 2017 saiten. All rights reserved.
//

import Foundation
import RxSwift
import RxCocoa

class OBDCommunicater {
    private typealias Command = (command: String, completion: (String) -> Void)
    
    private let connection: OBDSerialConnection
    private let commandQueue = PublishSubject<Command>()
    private let currentCommand = BehaviorRelay<Command?>(value: nil)
    
    private let disposeBag = DisposeBag()
    
    init(connection: OBDSerialConnection) {
        self.connection = connection
        setup()
    }
    
    fileprivate func setup() {
        let messageReceived = connection.read()
            .map { data -> String? in
                return String(data: data, encoding: .utf8)
            }
            .unwrap()
            .catchError { _ in .empty() }
            .share(replay: 1)
        
        let promptDetected = messageReceived
            .filter { $0.hasSuffix(">") }
            .map { _ in }
        
        let writeAvaialable = Observable
            .of(promptDetected.map { true },
                currentCommand.asObservable().filter { $0 != nil }.map { _ in false })
            .merge()
            .startWith(true)
        
        Observable
            .zip(writeAvaialable.filter { $0 }, commandQueue)
            .map { $1 }
            .observeOn(MainScheduler.asyncInstance)
            .bind(to: currentCommand)
            .disposed(by: disposeBag)
        
        messageReceived
            .buffer(promptDetected)
            .map { $0.filter { !$0.hasSuffix(">") }.joined() }
            .do(onNext: { print("receive : \($0)") })
            .withLatestFrom(currentCommand.asObservable()) { ($0, $1) }
            .subscribe(onNext: { (response, command) in
                command?.completion(response)
            })
            .disposed(by: disposeBag)
        
        commandQueue
            .subscribe(onNext: { print("queued : \($0)") })
            .disposed(by: disposeBag)
        
        currentCommand.asObservable()
            .unwrap()
            .flatMap { [weak self] command -> Observable<Void> in
                guard let wSelf = self else { return .empty() }
                
                print("write command: \(command.command)")
                guard let data = (command.command + "\r").data(using: .utf8) else {
                    print("invalid data")
                    return .empty()
                }

                return wSelf.connection.write(data).asObservable()
            }
            .subscribe()
            .disposed(by: disposeBag)
    }
    
    func send(command commandString: String) -> Single<String> {
        return Single.create { observer in
            let command = (command: commandString, completion: { (res: String) in
                observer(.success(res))
            })
            self.commandQueue.onNext(command)
            return Disposables.create { }
        }
    }
    
    func send(commands: [String]) -> Single<Void> {
        return Single.zip(commands.map { self.send(command: $0) }) { _ in }
    }
}

