//
//  Copyright © 2017 saiten. All rights reserved.
//

import RxSwift

extension Observable {
    
    func buffer<U: ObservableType>(_ boundary: U) -> Observable<[E]> {
        return Observable<[E]>.create { observer in
            var buffer: [E] = []
            let lock = NSRecursiveLock()
            
            let boundaryDisposable = boundary.subscribe { event in
                lock.lock(); defer { lock.unlock() }
                switch event {
                case .next:
                    observer.onNext(buffer)
                    buffer = []
                default:
                    break
                }
            }
            
            let disposable = self.subscribe { event in
                lock.lock(); defer { lock.unlock() }
                switch event {
                case .next(let element):
                    buffer.append(element)
                case .completed:
                    observer.onNext(buffer)
                    observer.onCompleted()
                case .error(let error):
                    observer.onError(error)
                    buffer = []
                }
            }

            return Disposables.create([disposable, boundaryDisposable])
        }
    }
    
}
