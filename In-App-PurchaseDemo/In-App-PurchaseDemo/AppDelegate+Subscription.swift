//
//  Appdelegate+Subscription.swift
//  
//
//  Created on 23/12/19.
//  Copyright ©2019. All rights reserved.
//

import UIKit
import Foundation
import StoreKit
import SwiftyStoreKit
import SwiftyJSON

struct APIParametersKey {
    static let bundle_id = "bundle_id"
    static let receipt_data = "receipt_data"
}

enum SubscriptionStatus {
    case active
    case expired
}

extension AppDelegate: SKProductsRequestDelegate, SKPaymentTransactionObserver {
    func actionBuyProduct() {
        if iapProducts.count != 0 {
            buyProduct(iapProducts[0])
        }
    }
    
    //MARK: IAP METHODS
    func checkSubscription() {
        self.fetchAvailableProducts()
        self.appleRecieptValidator()
    }
    
    //Fetch the Available Products
    func fetchAvailableProducts() {
        // Put here your IAP Products ID's
        let productIdentifiers = NSSet(objects: acrossMultipleApp) // Fix by Mohit
        productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers as! Set<String>)
        productsRequest.delegate = self
        productsRequest.start()
    }
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        if (response.products.count > 0) {
            iapProducts = response.products
        }
    }
    
    //Request For buy the Available Product
    func buyProduct(_ product: SKProduct) {
        //Add the StoreKit Payment Queue for ServerSide
        SKPaymentQueue.default().add(self)
        if SKPaymentQueue.canMakePayments() {
            let payment = SKPayment(product: product)
            SKPaymentQueue.default().add(self)
            SKPaymentQueue.default().add(payment)
            productID = product.productIdentifier
        }
        else {
            print_debug("cant purchase")
        }
    }
    
    //Failed request
    func request(_ request: SKRequest, didFailWithError error: Error) {
        print_debug(error.localizedDescription)
    }
    
    //function for details of all the transtion done for spacific Account
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction:AnyObject in transactions {
            if let trans = transaction as? SKPaymentTransaction {
                let trn = trans.transactionState
                if trn == .purchased {
                    SKPaymentQueue.default().finishTransaction(transaction as! SKPaymentTransaction)
                    UserDefaults.standard.setValue(productID, forKey: "currentSubscription")
                    self.dismissAllPresentScreen()
                    break
                }
                else if trn == .failed {
                    SKPaymentQueue.default().finishTransaction(transaction as! SKPaymentTransaction)
                    restorePurchase()
                    break
                }
                else if trn == .restored {
                     SKPaymentQueue.default().restoreCompletedTransactions()
                    UserDefaults.standard.setValue(productID, forKey: "currentSubscription")
                    self.dismissAllPresentScreen()
                    NotificationCenter.default.post(name: .kPurchaseSuccess, object: nil)
                    break
                }
            }
        }
    }
    
    //Apple Reciept Validation
    func appleRecieptValidator(_ isFromPurchase: Bool = false, _ completion:((Bool, String) -> Void)? = nil) {
        let isLive = Envirnoment.isProduction()
        let secretKey = Subscription.kiTUNES_SHARED_SECRET
        let service = isLive ? AppleReceiptValidator.VerifyReceiptURLType.production : AppleReceiptValidator.VerifyReceiptURLType.sandbox
        
        let appleRecieptValidator = AppleReceiptValidator(service: service, sharedSecret: secretKey)
        
        SwiftyStoreKit.verifyReceipt(using: appleRecieptValidator) { (result) in
            switch result {
            case .success(let receipt):
            if let data = JSON(receipt["latest_receipt_info"] as Any).arrayValue.first {
                let productIds = Set([data["product_id"].stringValue])
                var recieptData:[String:Any] = data.dictionaryObject != nil ? ["appPurchaseResponse" : data.dictionaryObject ?? [:]] : [:]
                recieptData["latest_receipt"] = JSON(receipt["latest_receipt"] as Any).stringValue
                let purchaseResult = SwiftyStoreKit.verifySubscriptions(productIds: productIds, inReceipt: receipt)
                
                switch purchaseResult {
                case .purchased(let expiryDate, let items):
                    print("\(productIds) are valid until \(expiryDate)\n\(items)\n")
                    let expInMs = JSON(data["expires_date_ms"]).stringValue
                    UserDefaults.standard.setValue(expInMs, forKey: Subscription.kSubscriptionEndDateInMS)
                    if self.getSubscriptionStatus() != .expired {
                        NotificationCenter.default.post(name: .kPurchaseSuccess, object: nil)
                    }
                    completion?(true, "Success")
                case .expired(let expiryDate, let items):
                    print("\(productIds) are expired since \(expiryDate)\n\(items)\n")
                    completion?(false, "App subscription has been expired since \(expiryDate), Please subscribe again.")
                case .notPurchased:
                    print("The user has never purchased \(productIds)")
                    completion?(false, "The user has never purchased subscription")
                }
            }
            case .error(error: let error):
                completion?(false, error.localizedDescription)
            }
        }
    }
    
    func restorePurchase() {
        if (SKPaymentQueue.canMakePayments()) {
            SKPaymentQueue.default().add(self)
            SKPaymentQueue.default().restoreCompletedTransactions()
        }
    }
    
    func dismissAllPresentScreen() {
        var vc = self.window?.rootViewController?.presentedViewController
        if vc is ViewController {
            vc?.dismiss(animated: true, completion: nil)
        }

        vc = (self.window?.rootViewController as? UINavigationController)?.topViewController?.presentedViewController

        if vc is ViewController {
            vc?.dismiss(animated: true, completion: nil)
        }
    }
}

//// MARK: Get Subscription Infomation and restore
extension AppDelegate {
    func getSubscriptionInfo(_ subscriptionType: String, _ completion:@escaping (_ status:Bool, _ priceString:String?, _ errorMessage:String?) -> Void) {
        SVProgressHUD.show()
        SwiftyStoreKit.retrieveProductsInfo([subscriptionType]) { result in
            SVProgressHUD.dismiss()
            if let product = result.retrievedProducts.first {
                let priceString = product.localizedPrice ?? "{YOUR_DEFAULT_PRICE}"
                completion(true, priceString, nil)
            } else if let invalidProductId = result.invalidProductIDs.first {
                completion(false, nil, "Could not retrieve product info, Invalid product identifier: \(invalidProductId)")
            } else {
                let errorString = result.error?.localizedDescription ?? "Unknown error. Please contact support"
                completion(false, nil, errorString)
            }
        }
    }
    
    func purchaseProduct(_ productId:String, completion:@escaping(_ status:Bool, _ errorMsg:String?) -> Void) {
        DispatchQueue.main.async {
            SVProgressHUD.show()
        }
        //Purchase Product
        SwiftyStoreKit.purchaseProduct(productId) { result in
            switch result {
            case .success:
                //Apple Receipt Validator
                appDelegate.appleRecieptValidator { (isSuccess, message) in
                    DispatchQueue.main.async {
                        SVProgressHUD.dismiss()
                    }
                    completion(isSuccess, message)
                }
            case .error(let error):
                DispatchQueue.main.async {
                    SVProgressHUD.dismiss()
                }
                completion(false, error.localizedDescription)
            }
        }
    }
    
    func restorePurchases(_ completion:@escaping(_ status:Bool, _ errorMsg:String?) -> Void) {
        DispatchQueue.main.async {
            SVProgressHUD.show()
        }
        //Restore Purchase
        SwiftyStoreKit.restorePurchases(atomically: true) { results in
            DispatchQueue.main.async {
                SVProgressHUD.dismiss()
            }
            if results.restoreFailedPurchases.count > 0 {
                debugPrint("Restore Failed: \(results.restoreFailedPurchases)")
            }
            else if results.restoredPurchases.count > 0 {
                debugPrint("Restore Success: \(results.restoredPurchases)")
                
                DispatchQueue.main.async {
                    SVProgressHUD.show()
                }
                
                //Apple Receipt Validator
                appDelegate.appleRecieptValidator { (isSuccess, message) in
                    DispatchQueue.main.async {
                        SVProgressHUD.dismiss()
                    }
                    completion(isSuccess, message)
                }
            }
            else {
//                debugPrint("Nothing to Restore")
                completion(false, "Nothing to Restore")
            }
        }
    }
}

// MARK: Get Subscription Status
extension AppDelegate {
    func getSubscriptionStatus() -> SubscriptionStatus {
        // return .expired
        if let expDtInMS = UserDefaults.standard.value(forKey: Subscription.kSubscriptionEndDateInMS) as? String {
            if JSON(expDtInMS).intValue > (Int(Date().timeIntervalSince1970) * 1000) {
                return .active
            }
            else {
                return .expired
            }
        }
        else {
            return .expired
        }
    }
    
    func getExpirationDateFromResponse(_ jsonResponse: NSDictionary) -> Date? {
        if let receiptInfo: NSArray = jsonResponse["latest_receipt_info"] as? NSArray {
            let lastReceipt = receiptInfo.lastObject as! NSDictionary
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss VV"
            if let expiresDate = lastReceipt["expires_date"] as? String {
                return formatter.date(from: expiresDate)
            }
            return nil
        }
        else {
            return nil
        }
    }
}

//MARK:- Date Conversion with String Extension
extension String {
    func getdDateInstance(_ validFormatter:String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = validFormatter
        if let objDate = dateFormatter.date(from: self) {
            return objDate
        }
        return Date()
    }
    
    func getdDateInstance2(_ validFormatter:String) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = validFormatter
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        if let objDate = dateFormatter.date(from: self) {
            return objDate
        }
        return Date()
    }
}

//MARK:- Check the Enviornment(Sandbox or Production)
struct Envirnoment {
    private static let production : Bool = {
        #if DEBUG
            print("DEBUG")
            return false
        #elseif ADHOC
            print("ADHOC")
            return false
        #else
            print("PRODUCTION")
            return true
        #endif
    }()

    static func isProduction () -> Bool {
        return self.production
    }
}

//MARK:- Extra methods that required for IAP
func print_debug<T>(_ obj:T, file: String = #file, line: Int = #line, function: String = #function) {
    print("File:'\(file.description)' Line:'\(line)' Function:'\(function)' ::\(obj)")
}

extension Notification.Name {
    static let kPurchaseSuccess = Notification.Name("PurchaseSuccess")
}

struct Subscription {
    static let kWEEKLY_SUBSCRIPTION         = "{YOUR_SUBSCRIPTION_PRODUCT_ID}" // Set your subscription product id
    static let kiTUNES_SHARED_SECRET        = "{YOUR_SUBSCRIPTION_SECRET_KEY}" // Set your subscription secret key
    
    static let kSubscriptionEndDate         = "SubscriptionEndDate"
    static let kSubscriptionEndDateInMS     = "SubscriptionEndDateInMS"
    static let kDeviceToken                 = "DeviceToken"
}

//MARK:- UIViewController Extension for Alert View
extension UIViewController {
    func showOkAlert(_ msg: String) {
        let alert = UIAlertController(title: "Subscription", message: msg, preferredStyle: .alert)
        let okAction = UIAlertAction(title:"OK", style: .default, handler: nil)
        alert.addAction(okAction)
        self.present(alert, animated: true, completion: nil)
    }
}

