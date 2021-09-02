//
//  ViewController.swift
//  In-App-PurchaseDemo
//
//  Created on 01/09/21.
//

import UIKit
import StoreKit
import SwiftyStoreKit

class ViewController: UIViewController {
    //MARK:- IBOutlet
    @IBOutlet weak var btnRestore: UIButton!
    @IBOutlet weak var btnSubscription: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        appDelegate.fetchAvailableProducts()
        self.fetchSubscriptionDetail()
        
        if appDelegate.getSubscriptionStatus() == .active {
            self.btnSubscription.isHidden = true
        }
    }
    
    //MARK:- Custom Method
    private func fetchSubscriptionDetail() {
        appDelegate.getSubscriptionInfo(Subscription.kWEEKLY_SUBSCRIPTION) { (status, price, errorMsg) in
            //Update the details that required such as Price and product details.
            
        }
    }
}

//MARK:- IBAction of Subscription button and Restore button.
extension ViewController {
    @IBAction func clickSubscription(_ sender : UIButton) {
        if Reachability.isInternetAvailable() {
            appDelegate.purchaseProduct(Subscription.kWEEKLY_SUBSCRIPTION) { status, message in
                if status == false {
                    self.showOkAlert(message ?? "")
                }
            }
        }
        else {
            self.showOkAlert("Internet not available")
        }
    }
    
    //Restore Product IBAction
    @IBAction func clickRestore(_ sender : UIButton) {
        if Reachability.isInternetAvailable() {
            appDelegate.restorePurchases { (status, message) in
                if status == false {
                    self.showOkAlert(message ?? "")
                } else {
                    self.showOkAlert("Subscription has been successfully restored")
                }
            }
        }
        else {
            self.showOkAlert("Internet not available")
        }
    }
    
    //Called on Success with NotificationCenter
    @objc func purchaseSuccess() {
        self.dismiss(animated: true, completion: nil)
    }
}
