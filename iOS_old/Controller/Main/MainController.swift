//
//  MainController.swift
//  Kiwix
//
//  Created by Chris Li on 11/13/16.
//  Copyright © 2016 Chris Li. All rights reserved.
//

import UIKit
import SafariServices
import CoreSpotlight
import CloudKit
import NotificationCenter

class MainController: UIViewController {
    
    @IBOutlet weak var dimView: UIView!
    @IBOutlet weak var tabContainerView: UIView!
    @IBOutlet weak var tocVisiualEffectView: UIVisualEffectView!
    @IBOutlet weak var tocTopToSuperViewBottomSpacing: NSLayoutConstraint!
    @IBOutlet weak var tocHeightConstraint: NSLayoutConstraint!
    @IBOutlet weak var tocLeadSpacing: NSLayoutConstraint!
    
    let searchBar = UISearchBar()
    let controllers = Controllers()
    let buttons = Buttons()
    fileprivate(set) var currentTab: TabController?
    
    var shouldPresentBookmark = false
    var isShowingTableOfContents = false
    private(set) var tableOfContentsController: TableOfContentsController!
    
    // MARK: - Basic
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        searchBar.delegate = self
        buttons.delegate = self
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        searchBar.delegate = self
        buttons.delegate = self
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.titleView = searchBar
        showWelcome()
        AppNotification.shared.rateApp()
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.horizontalSizeClass != previousTraitCollection?.horizontalSizeClass ||
            traitCollection.verticalSizeClass != previousTraitCollection?.verticalSizeClass else {return}
        
        // buttons
        switch traitCollection.horizontalSizeClass {
        case .compact:
            navigationController?.setToolbarHidden(false, animated: false)
            navigationItem.leftBarButtonItems = nil
            navigationItem.rightBarButtonItems = nil
            if searchBar.isFirstResponder {
                navigationItem.rightBarButtonItem = buttons.cancel
            }
            toolbarItems = buttons.toolbar
        case .regular:
            navigationController?.setToolbarHidden(true, animated: false)
            toolbarItems = nil
            navigationItem.leftBarButtonItems = buttons.navLeft
            navigationItem.rightBarButtonItems = buttons.navRight
        default:
            return
        }
        configureTOCConstraints()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "EmbeddedTOCController" {
            guard let controller = segue.destination as? TableOfContentsController else {return}
            tableOfContentsController = controller
            tableOfContentsController.delegate = self
        }
    }
    
    func dismissPresentedControllers(animated: Bool) {
        presentedViewController?.dismiss(animated: animated, completion: {
            self.presentedViewController?.dismiss(animated: animated, completion: nil)
        })
    }
}

// MARK: - Tabs

extension MainController: TabControllerDelegate {
    func showEmptyTab() {
        removeCurrentTab()
        let controller = controllers.createTab()
        controller.delegate = self
        addChildViewController(controller)
        tabContainerView.addSubview(controller.view)
        currentTab = controller
    }
    
    func removeCurrentTab() {
        guard let currentTab = currentTab else {return}
        currentTab.delegate = nil
        currentTab.removeFromParentViewController()
        currentTab.view.removeFromSuperview()
        searchBar.title = ""
        buttons.back.tintColor = UIColor.gray
        buttons.forward.tintColor = UIColor.gray
        buttons.bookmark.isHighlighted = false
        showWelcome()
    }
    
    // MARK: TabControllerDelegate
    
    func didFinishLoading(tab: TabController) {
        let webView = tab.webView!
        searchBar.title = currentTab?.article?.title ?? ""
        tableOfContentsController.headings = JS.getTableOfContents(webView: webView)
        buttons.back.tintColor = webView.canGoBack ? nil : UIColor.gray
        buttons.forward.tintColor = webView.canGoForward ? nil : UIColor.gray
        buttons.bookmark.isHighlighted = currentTab?.article?.isBookmarked ?? false
    }
    
    func didTapOnExternalLink(url: URL) {
        let controller = SFSafariViewController(url: url)
        controller.delegate = self
        present(controller, animated: true, completion: nil)
    }
    
    func pageDidScroll(start: Int, length: Int) {
        tableOfContentsController?.visibleRange = (start, length)
    }
}

// MARK: - Search

extension MainController: UISearchBarDelegate, SearchContainerDelegate {
    
//    func didBecomeFirstResponder(searchBar: SearchBar) {
//        showSearch(animated: true)
//    }
//
//    func didResignFirstResponder(searchBar: SearchBar) {
//        hideSearch(animated: true)
//    }
//
//    func textDidChange(text: String, searchBar: SearchBar) {
//        controllers.search.searchText = text
//    }
//
//    func shouldReturn(searchBar: SearchBar) -> Bool {
//        let controller = controllers.search.resultController!
//        controller.selectFirstResult()
//        return controller.searchResults.count > 0
//    }
    
    private func showSearch(animated: Bool) {
        let controller = controllers.search
        controller.delegate = self
        guard !childViewControllers.contains(controller) else {return}
        
        // hide toolbar
        // add cancel button
        if traitCollection.horizontalSizeClass == .compact {
            navigationController?.setToolbarHidden(true, animated: animated)
            navigationItem.setRightBarButton(buttons.cancel, animated: animated)
        }
        
        // manage view hierarchy
        addChildViewController(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        
        let views: [String: Any] = ["view": controller.view]
        view.addConstraints(NSLayoutConstraint.constraints(
            withVisualFormat: "H:|[view]|", options: .alignAllCenterY, metrics: nil, views: views))
        view.addConstraint(controller.view.topAnchor.constraint(equalTo: topLayoutGuide.bottomAnchor))
        view.addConstraint(controller.view.bottomAnchor.constraint(equalTo: bottomLayoutGuide.topAnchor))
        
        if animated {
            controller.view.alpha = 0.5
            UIView.animate(withDuration: 0.15, delay: 0.0, options: .curveEaseOut, animations: { () -> Void in
                controller.view.alpha = 1.0
            }, completion: nil)
        } else {
            controller.view.alpha = 1.0
        }
        controller.didMove(toParentViewController: self)
    }
    
    private func hideSearch(animated: Bool) {
        guard let searchController = childViewControllers.flatMap({$0 as? SearchContainer}).first else {return}
        
        // show toolbar
        // remove cancel button
        if traitCollection.horizontalSizeClass == .compact {
            navigationController?.setToolbarHidden(false, animated: animated)
            navigationItem.setRightBarButton(nil, animated: animated)
        }
        
        let completion = { (complete: Bool) -> Void in
            guard complete else {return}
            searchController.view.removeFromSuperview()
            searchController.removeFromParentViewController()
            guard self.traitCollection.horizontalSizeClass == .compact else {return}
            self.navigationController?.setToolbarHidden(false, animated: animated)
        }
        
        searchController.willMove(toParentViewController: nil)
        if animated {
            UIView.animate(withDuration: 0.15, delay: 0.0, options: .beginFromCurrentState, animations: {
                searchController.view.alpha = 0.0
            }, completion: completion)
        } else {
            completion(true)
        }
    }
    
    func didTapSearchDimView() {
        _ = searchBar.resignFirstResponder()
    }
}

// MARK: - Button Delegates

extension MainController: ButtonDelegates {
    func didTapBackButton() {
        currentTab?.webView.goBack()
    }
    
    func didTapForwardButton() {
        currentTab?.webView.goForward()
    }
    
    func didTapTOCButton() {
        isShowingTableOfContents ? hideTableOfContents(animated: true) : showTableOfContents(animated: true)
    }
    
    func didTapBookmarkButton() {
        showBookmarkController()
    }
    
    func didTapLibraryButton() {
         present(controllers.library, animated: true, completion: nil)
    }
    
    func didTapSettingButton() {
        present(controllers.setting, animated: true, completion: nil)
    }
    
    func didTapCancelButton() {
        _ = searchBar.resignFirstResponder()
    }
    
    func didLongPressBackButton() {
    }
    
    func didLongPressForwardButton() {
    }
    
    func didLongPressBookmarkButton() {
        func indexCoreSpotlight(article: Article) {
            if article.isBookmarked {
                CSSearchableIndex.default().indexSearchableItems([article.searchableItem], completionHandler: nil)
            } else {
                guard let url = article.url else {return}
                CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [url.absoluteString], completionHandler: nil)
            }
        }
        
        func updateBookmarkWidget() {
            guard let defaults = UserDefaults(suiteName: "group.kiwix") else {return}
            let bookmarks = Article
                .fetchRecentBookmarks(count: 30, context: AppDelegate.persistentContainer.viewContext)
                .flatMap { (article) -> [String: Any]? in
                guard let title = article.title,
                    let data = article.thumbImageData,
                    let urlString = article.url?.absoluteString else {return nil}
                return [
                    "title": title,
                    "thumbImageData": data,
                    "url": urlString,
                    "isMainPage": NSNumber(value: article.isMainPage)
                ]
            }
            defaults.set(bookmarks, forKey: "bookmarks")
            NCWidgetController.widgetController().setHasContent(bookmarks.count > 0, forWidgetWithBundleIdentifier: "self.Kiwix.Bookmarks")
            
        }
        
        let context = AppDelegate.persistentContainer.viewContext
        guard let article = currentTab?.article else {return}
        article.isBookmarked = !article.isBookmarked
        if article.isBookmarked {article.bookmarkDate = Date()}
        if context.hasChanges {try? context.save()}
        
        showBookmarkHUD()
        controllers.bookmarkHUD.bookmarkAdded = article.isBookmarked
        buttons.bookmark.isHighlighted = article.isBookmarked
        
        indexCoreSpotlight(article: article)
        updateBookmarkWidget()
    }
}

// MARK: - Table Of Content

extension MainController: TableOfContentsDelegate {
    func showTableOfContents(animated: Bool) {
        guard welcomeController == nil else {return}
        isShowingTableOfContents = true
        tocVisiualEffectView.isHidden = false
        dimView.isHidden = false
        dimView.alpha = 0.0
        view.layoutIfNeeded()
        
        configureTOCConstraints()
        
        if animated {
            UIView.animate(withDuration: 0.3, delay: 0.0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.0, options: .curveEaseOut, animations: {
                self.view.layoutIfNeeded()
                self.dimView.alpha = 0.5
            }) { (completed) in }
        } else {
            view.layoutIfNeeded()
            dimView.alpha = 0.5
        }
    }
    
    func hideTableOfContents(animated: Bool) {
        isShowingTableOfContents = false
        view.layoutIfNeeded()
        
        configureTOCConstraints()
        if animated {
            UIView.animate(withDuration: 0.2, delay: 0.0, options: .curveEaseIn, animations: {
                self.view.layoutIfNeeded()
                self.dimView.alpha = 0.0
            }) { (completed) in
                self.dimView.isHidden = true
                self.tocVisiualEffectView.isHidden = true
            }
        } else {
            view.layoutIfNeeded()
            dimView.alpha = 0.0
            dimView.isHidden = true
            tocVisiualEffectView.isHidden = true
        }
    }
    
    fileprivate func configureTOCConstraints() {
        switch traitCollection.horizontalSizeClass {
        case .compact:
            let toolBarHeight: CGFloat = traitCollection.horizontalSizeClass == .regular ? 0.0 : (traitCollection.verticalSizeClass == .compact ? 32.0 : 44.0)
            let tocHeight = tableOfContentsController.preferredContentSize.height
            tocHeightConstraint.constant = tocHeight
            tocTopToSuperViewBottomSpacing.constant = isShowingTableOfContents ? tocHeight + toolBarHeight + 10 : 0.0
        case .regular:
            tocLeadSpacing.constant = isShowingTableOfContents ? 0.0 : 270
        default:
            break
        }
    }
    
    func didSelectHeading(index: Int) {
        guard let webView = currentTab?.webView else {return}
        JS.scrollToHeading(webView: webView, index: index)
        if traitCollection.horizontalSizeClass == .compact {
            hideTableOfContents(animated: true)
        }
    }
    
    @IBAction func didTapTOCDimView(_ sender: UITapGestureRecognizer) {
        hideTableOfContents(animated: true)
    }
}

// MARK: - Bookmark

extension MainController: UIViewControllerTransitioningDelegate {
    func showBookmarkController() {
        let controller = controllers.bookmark
        controller.modalPresentationStyle = .fullScreen
        present(controller, animated: true, completion: nil)
    }
    
    func showBookmarkHUD() {
        let controller = controllers.bookmarkHUD
        controller.bookmarkAdded = !controller.bookmarkAdded
        controller.transitioningDelegate = self
        controller.modalPresentationStyle = .overFullScreen
        present(controller, animated: true, completion: nil)
    }
    
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return BookmarkHUDAnimator(animateIn: true)
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return BookmarkHUDAnimator(animateIn: false)
    }
}

// MARK: - Welcome

extension MainController {
    func showWelcome() {
        let controller = controllers.welcome
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        addChildViewController(controller)
        view.insertSubview(controller.view, aboveSubview: tabContainerView)
        let views: [String: Any] = ["view": controller.view]
        view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "H:|[view]|", options: .alignAllTop, metrics: nil, views: views))
        view.addConstraints(NSLayoutConstraint.constraints(withVisualFormat: "V:|[view]|", options: .alignAllLeft, metrics: nil, views: views))
        controller.didMove(toParentViewController: self)
    }
    
    func hideWelcome() {
        guard let controller = welcomeController else {return}
        controller.removeFromParentViewController()
        controller.view.removeFromSuperview()
    }
    
    var welcomeController: WelcomeController? {
        return childViewControllers.flatMap({$0 as? WelcomeController}).first
    }
}

// MARK: - SFSafariViewControllerDelegate

extension MainController: SFSafariViewControllerDelegate {
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        controller.dismiss(animated: true, completion: nil)
    }
}
