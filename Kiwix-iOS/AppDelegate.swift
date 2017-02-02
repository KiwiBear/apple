//  AppDelegate.swift
//  Kiwix
//
//  Created by Chris on 12/11/15.
//  Copyright © 2016 Chris Li. All rights reserved.
//

import UIKit
import CoreData
import CloudKit
import CoreSpotlight
import UserNotifications
import ProcedureKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    class var mainController: MainController {return ((UIApplication.shared.delegate as! AppDelegate)
        .window?.rootViewController as! UINavigationController)
        .topViewController as! MainController}
    
    // MARK: - App State Change
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]? = nil) -> Bool {
        URLProtocol.registerClass(KiwixURLProtocol.self)
        _ = Network.shared
        _ = AppNotification.shared
        application.setMinimumBackgroundFetchInterval(86400)
        return true
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        ZimMultiReader.shared.startScan()
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        let type = "org.kiwix.recent"
        let previousIndex: Int? = {
            guard let recent = UIApplication.shared.shortcutItems?.filter({$0.type == type}).first else {return nil}
            return UIApplication.shared.shortcutItems?.index(of: recent)
        }()
        
        if let index = previousIndex { UIApplication.shared.shortcutItems?.remove(at: index) }
        
        if let article = AppDelegate.mainController.article,
            let title = article.title, let url = article.url?.absoluteString {
            let item = UIMutableApplicationShortcutItem(type: type,
                                                        localizedTitle: title,
                                                        localizedSubtitle: nil,
                                                        icon: UIApplicationShortcutIcon(templateImageName: "Recent"),
                                                        userInfo: ["URL": url])
            if let index = previousIndex {
                UIApplication.shared.shortcutItems?.insert(item, at: index)
            } else {
                UIApplication.shared.shortcutItems?.append(item)
            }
        }
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        self.saveContext()
    }
    
    // MARK: - Background
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let refresh = RefreshLibraryOperation()
        refresh.addDidFinishBlockObserver { (operation, errors) in
            guard Preference.Notifications.libraryRefresh else {return}
            if let _ = errors.first {
                completionHandler(.failed)
            } else {
                OperationQueue.main.addOperation({ 
                    AppNotification.shared.libraryRefreshed(completion: { 
                        completionHandler(operation.hasUpdate ? .newData : .noData)
                    })
                })
            }
        }
        GlobalQueue.shared.add(operation: refresh)
    }
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        Network.shared.backgroundEventsCompleteProcessing[identifier] = completionHandler
    }
    
    // MARK: - Quick Actions
    
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        switch shortcutItem.type {
        case "org.kiwix.search":
            AppDelegate.mainController.dismissPresentedControllers()
            _ = AppDelegate.mainController.searchBar.becomeFirstResponder()
            completionHandler(true)
        case "org.kiwix.bookmarks":
            if AppDelegate.mainController.searchBar.isFirstResponder {_ = AppDelegate.mainController.searchBar.resignFirstResponder()}
            AppDelegate.mainController.showBookmarkController()
            completionHandler(true)
        case "org.kiwix.recent":
            guard let urlString = shortcutItem.userInfo?["URL"] as? String,
                let url = URL(string: urlString) else {completionHandler(false); return}
            GlobalQueue.shared.add(articleLoad: ArticleLoadOperation(url: url))
            completionHandler(true)
        default:
            completionHandler(false)
            return
        }
    }
    
    // MARK: - Core Data
    
    lazy var persistentContainer = CoreDataContainer()
    
    class var persistentContainer: CoreDataContainer {
        return (UIApplication.shared.delegate as! AppDelegate).persistentContainer
    }
    
    func saveContext () {
        let context = persistentContainer.viewContext
        if context.hasChanges { try? context.save() }
    }
    
    

    
    
    
    
    // MARK: - Continuity
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
        switch userActivity.activityType {
        case CSSearchableItemActionType:
            return true
        default:
            return false
        }
    }
    
    
    
    
    
    
    
    
    private let recentShortcutTypeString = "org.kiwix.recent"
    
    func recordActiveSession() {
        Preference.activeUseHistory.append(Date()) 
    }
    
    func registerNotification() {
        if #available(iOS 10, *) {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound], completionHandler: { _ in })
        } else {
            let settings = UIUserNotificationSettings(types: [.sound, .alert, .badge], categories: nil)
            UIApplication.shared.registerUserNotificationSettings(settings)
        }
    }
    
    func registerCloudKit() {
        if #available(iOS 10, *) {
            guard !Preference.hasSubscribedToCloudKitChanges else {return}
            
            let subscription = CKDatabaseSubscription(subscriptionID: "")
            let notificationInfo = CKNotificationInfo()
            notificationInfo.shouldSendContentAvailable = true
            subscription.notificationInfo = notificationInfo
            
            let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: [])
            operation.modifySubscriptionsCompletionBlock = { savedSubscriptions, _, error in
                if let error = error {
                    print(error.localizedDescription)
                } else {
                    Preference.hasSubscribedToCloudKitChanges = true
                }
            }
            
            let database = CKContainer(identifier: "iCloud.org.kiwix").privateCloudDatabase
            database.add(operation)
        }
    }
    
    // MARK: -

//    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
//
    
    
        
        // Register notification
//        if let _ = Preference.libraryLastRefreshTime { registerNotification() }
        
        // Set background refresh interval
//        application.setMinimumBackgroundFetchInterval(86400)
//        
//        return true
//    }
    
//    func application(_ application: UIApplication, didRegister notificationSettings: UIUserNotificationSettings) {
//        // Here we get what notification permission user currently allows
//    }
    

    
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any]) -> Bool {
        guard url.isKiwixURL else {return false}
//        let operation = ArticleLoadOperation(url: url)
//        GlobalQueue.shared.add(load: operation)
        return true
    }
    
//    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
//        if userActivity.activityType == "org.kiwix.kiwix.article-view" {
//            guard let navController = window?.rootViewController as? UINavigationController,
//                let controller = navController.topViewController as? MainController else {return false}
//            controller.restoreUserActivityState(userActivity)
//            return true
//        } else {
//            return false
//        }
//    }
    
    // MARK: - Active
    
//    func applicationDidBecomeActive(_ application: UIApplication) {
//        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
//        Timer.scheduledTimer(timeInterval: 60.0, target: self, selector: #selector(AppDelegate.recordActiveSession), userInfo: nil, repeats: false)
//        ZimMultiReader.shared.startScan()
//        removeAllDynamicShortcutItems()
//    }

//    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
        
        //UIApplication.updateApplicationIconBadgeNumber()
        
//        if let article = mainController?.article {
//            addRecentArticleShortCutItem(article)
//        }
//    }
    
    //    class func updateApplicationIconBadgeNumber() {
    //        guard let settings = UIApplication.sharedApplication().currentUserNotificationSettings() else {return}
    //        guard settings.types.contains(UIUserNotificationType.Badge) else {return}
    //        //UIApplication.sharedApplication().applicationIconBadgeNumber = downloader.taskCount ?? 0
    //    }
    
    // MARK: - Shotcut Items
    
    func addRecentArticleShortCutItem(_ article: Article) {
        guard let title = article.title, let url = article.url?.absoluteString else {return}
        let icon = UIApplicationShortcutIcon(templateImageName: "Recent")
        let item = UIMutableApplicationShortcutItem(type: recentShortcutTypeString,
                                                    localizedTitle: title, localizedSubtitle: "",
                                                    icon: icon,
                                                    userInfo: ["URL": url])
        UIApplication.shared.shortcutItems?.append(item)
    }
    
    func removeAllDynamicShortcutItems() {
        guard let items = UIApplication.shared.shortcutItems?.filter({$0.type == recentShortcutTypeString}) else {return}
        for item in items {
            guard let index = UIApplication.shared.shortcutItems?.index(of: item) else {continue}
            UIApplication.shared.shortcutItems?.remove(at: index)
        }
    }
    
//    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
//        case recentShortcutTypeString:
//            let operation = ArticleLoadOperation(url: url)
//            GlobalQueue.shared.add(load: operation)
//            completionHandler(true)
//        default:
//            completionHandler(false)
//            return
//        }
//    }

    

}

