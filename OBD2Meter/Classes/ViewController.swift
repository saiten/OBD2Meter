//
//  Copyright © 2017 saiten. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import RxBluetoothKit
import CoreBluetooth
import LMGaugeView

fileprivate let SubGuageValueFont = UIFont(name: "HelveticaNeue-CondensedBold", size: 44)!
fileprivate let SubGuageUnitMeasureFont = UIFont(name: "HelveticaNeue-CondensedBold", size: 12)!
fileprivate let SubGuageMinMaxFont = UIFont(name: "HelveticaNeue", size: 10)!

class ViewController: UIViewController {

    @IBOutlet fileprivate weak var speedGuageView: LMGaugeView!
    @IBOutlet fileprivate weak var rpmGuageView: LMGaugeView!
    @IBOutlet fileprivate weak var boostGuageView: LMGaugeView!
    
    @IBOutlet fileprivate weak var connectButton: UIButton!
    @IBOutlet fileprivate weak var logTextView: UITextView!

    private var viewModel: ViewModel!
    
    fileprivate let disposeBag = DisposeBag()

    override func viewDidLoad() {
        super.viewDidLoad()

        speedGuageView.minValue = 0;
        speedGuageView.maxValue = 140;
        speedGuageView.limitValue = 100;
        speedGuageView.value = 0

        boostGuageView.minValue = -1;
        boostGuageView.maxValue = 2;
        boostGuageView.value = 0.0
        boostGuageView.valueFont = SubGuageValueFont
        boostGuageView.unitOfMeasurementFont = SubGuageUnitMeasureFont
        boostGuageView.minMaxValueFont = SubGuageMinMaxFont

        rpmGuageView.minValue = 0;
        rpmGuageView.maxValue = 8000;
        rpmGuageView.value = 0.0
        rpmGuageView.valueFont = SubGuageValueFont
        rpmGuageView.unitOfMeasurementFont = SubGuageUnitMeasureFont
        rpmGuageView.minMaxValueFont = SubGuageMinMaxFont

        viewModel = ViewModel()
        bind()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    private func bind() {
        connectButton.rx.tap
            .bind(to: viewModel.inputs.connect)
            .disposed(by: disposeBag)
        
        viewModel.outputs.isConnected
            .do(onNext: {
                // 接続中はスリープさせない
                UIApplication.shared.isIdleTimerDisabled = $0
            })
            .map { $0 ? "Disconnect" : "Connect" }
            .drive(connectButton.rx.title(for: .normal))
            .disposed(by: disposeBag)
        
        viewModel.outputs.log
            .drive(logTextView.rx.text)
            .disposed(by: disposeBag)
        
        viewModel.outputs.speed
            .drive(onNext: { [weak self] in
                self?.speedGuageView.value = CGFloat($0)
            })
            .disposed(by: disposeBag)
        
        viewModel.outputs.rpm
            .drive(onNext: { [weak self] in
                self?.rpmGuageView.value = CGFloat($0)
            })
            .disposed(by: disposeBag)

        viewModel.outputs.boost
            .drive(onNext: { [weak self] in
                self?.boostGuageView.value = CGFloat($0)
            })
            .disposed(by: disposeBag)
    }
}
