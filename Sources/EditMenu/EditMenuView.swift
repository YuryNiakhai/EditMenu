import SwiftUI
import UIKit

public struct EditMenuItem {
    public let title: String
    public let action: () -> Void
    
    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }
}

public extension View {
    /// Attaches a long-press action to this `View` withe the given item titles & actions
    public func editMenu(@ArrayBuilder<EditMenuItem> _ items: () -> [EditMenuItem] = { [EditMenuItem]() }, copyHandler: (() -> Void)?, responderHandler: ((UIResponder?) -> Void)?) -> some View {
        EditMenuView(content: self, items: items(), copyHandler: copyHandler, responderHandler: responderHandler)
    }
}

public struct EditMenuView<Content: View>: UIViewControllerRepresentable {
    public typealias Item = EditMenuItem
    
    public let content: Content
    public let items: [Item]
    public let copyHandler: (() -> Void)?
    public let responderHandler: ((UIResponder?) -> Void)?
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(items: items, copyHandler: copyHandler, responderHandler: responderHandler)
    }
    
    public func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let coordinator = context.coordinator
        
        // `handler` dispatches calls to each item's action
        let hostVC = HostingController(rootView: content, copyHandler: copyHandler) { [weak coordinator] index in
            guard let items = coordinator?.items else { return }
            
            if !items.indices.contains(index) {
                assertionFailure()
                return
            }

            items[index].action()
        }
        
        coordinator.responder = hostVC
        
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress))
        hostVC.view.addGestureRecognizer(longPress)
        
        return hostVC
    }
    
    public func updateUIViewController(_ uiViewController: UIHostingController<Content>, context: Context) {
        
    }
    
    public class Coordinator: NSObject {
        let items: [Item]
        let copyHandler: (() -> Void)?
        let responderHandler: ((UIResponder?) -> Void)?
        var responder: UIResponder?
        private var wasActive = false
        
        init(items: [Item], copyHandler: (() -> Void)?, responderHandler: ((UIResponder?) -> Void)?) {
            self.items = items
            self.copyHandler = copyHandler
            self.responderHandler = responderHandler
        }
        
        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            let menu = UIMenuController.shared

            guard gesture.state == .began, let view = gesture.view, !menu.isMenuVisible else {
                return
            }

            responderHandler?(responder)
            NotificationCenter.default.addObserver(self, selector: #selector(willHideMenuNotification), name: UIMenuController.willHideMenuNotification, object: nil)
            wasActive = true
            // tell `responder` (the `HostingController`) to become first responder
            // responder?.becomeFirstResponder()
            
            // each menu item sends a message selector to `responder` based on the index of the item
            menu.menuItems = items.enumerated().map { index, item in
                UIMenuItem(title: item.title, action: IndexedCallable.selector(for: index))
            }
            
            // show the menu from the root view
            let drawingViews = view.subviews.compactMap { String(describing: $0).lowercased().contains("drawing") ? $0 : nil }
            let targetView = drawingViews.count > 1 ? drawingViews[drawingViews.count - 2] : view.subviews.first
            let validatedTargetViee = targetView ?? view
            menu.showMenu(from: validatedTargetViee, rect: validatedTargetViee.bounds)
        }

        @objc func willHideMenuNotification() {
            responderHandler?(nil)
            wasActive = false
        }

        deinit {
            if wasActive {
                responderHandler?(nil)
            }
        }
    }
    
    /// Subclass of `UIHostingController` to handle responder actions
    class HostingController<Content: View>: UIHostingController<Content> {
        private var callable: IndexedCallable?
        private var copyHandler: (() -> Void)?
        
        convenience init(rootView: Content, copyHandler: (() -> Void)?, handler: @escaping (Int) -> Void) {        
            self.init(rootView: rootView)
            
            callable = IndexedCallable(handler: handler)

            self.copyHandler =  copyHandler

            view.backgroundColor = .clear
        }

        override func viewDidLoad() {
            super.viewDidLoad()

            var expectedSize = view.systemLayoutSizeFitting(.init(width: UIScreen.main.bounds.width - 40, height: CGFloat.infinity))
            expectedSize.height += 1
            preferredContentSize = expectedSize
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()

            var expectedSize = view.systemLayoutSizeFitting(.init(width: view.frame.width, height: CGFloat.infinity))
            expectedSize.height += 1
            if expectedSize != preferredContentSize {
                preferredContentSize = expectedSize
                view.invalidateIntrinsicContentSize()
            }
        }
        
        override var canBecomeFirstResponder: Bool {
            true
        }

        public override func copy(_ sender: Any?) {
            copyHandler?()
        }
        
        override func responds(to aSelector: Selector!) -> Bool {
            return super.responds(to: aSelector) || IndexedCallable.willRespond(to: aSelector)
        }
        
        // forward valid selectors to `callable`
        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            guard IndexedCallable.willRespond(to: aSelector) else {
                return super.forwardingTarget(for: aSelector)
            }
            
            return callable
        }
    }

}
