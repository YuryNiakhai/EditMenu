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
    public func editMenu(@ArrayBuilder<EditMenuItem> _ items: () -> [EditMenuItem], copyHandler: (() -> Void)?) -> some View {
        EditMenuView(content: self, items: items(), copyHandler: copyHandler)
            .fixedSize()
    }
}

public struct EditMenuView<Content: View>: UIViewControllerRepresentable {
    public typealias Item = EditMenuItem
    
    public let content: Content
    public let items: [Item]
    public let copyHandler: (() -> Void)?
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(items: items, copyHandler: copyHandler)
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
        let copyHandler: (() -> Void)
        var responder: UIResponder?
        
        init(items: [Item]) {
            self.items = items
        }
        
        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            let menu = UIMenuController.shared

            guard gesture.state == .began, let view = gesture.view, !menu.isMenuVisible else {
                return
            }
            
            // tell `responder` (the `HostingController`) to become first responder
            responder?.becomeFirstResponder()
            
            // each menu item sends a message selector to `responder` based on the index of the item
            menu.menuItems = items.enumerated().map { index, item in
                UIMenuItem(title: item.title, action: IndexedCallable.selector(for: index))
            }
            
            // show the menu from the root view
            menu.showMenu(from: view, rect: view.bounds)
        }
    }
    
    /// Subclass of `UIHostingController` to handle responder actions
    class HostingController<Content: View>: UIHostingController<Content> {
        private var callable: IndexedCallable?
        private let copyHandler: (() -> Void)?
        
        convenience init(rootView: Content, copyHandler: (() -> Void)?, handler: @escaping (Int) -> Void) {
            self.init(rootView: rootView)

            self.copyHandler = copyHandler

            // make sure this VC is sized to its' content
            preferredContentSize = view.intrinsicContentSize
            
            callable = IndexedCallable(handler: handler)

            view.backgroundColor = .clear
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
