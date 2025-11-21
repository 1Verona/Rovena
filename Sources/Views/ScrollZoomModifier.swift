import SwiftUI

// A View Modifier to handle scroll wheel events for zooming
struct ScrollZoomModifier: ViewModifier {
    @Binding var zoomScale: CGFloat
    
    func body(content: Content) -> some View {
        content
            .background(ScrollWheelHandler(zoomScale: $zoomScale))
    }
}

struct ScrollWheelHandler: NSViewRepresentable {
    @Binding var zoomScale: CGFloat
    
    func makeNSView(context: Context) -> NSView {
        let view = ScrollListenerView()
        view.zoomBinding = $zoomScale
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? ScrollListenerView {
            view.zoomBinding = $zoomScale
        }
    }
    
    class ScrollListenerView: NSView {
        var zoomBinding: Binding<CGFloat>?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func scrollWheel(with event: NSEvent) {
            // Check for Command key
            if event.modifierFlags.contains(.command) {
                guard let binding = zoomBinding else { return }
                
                let delta = event.deltaY * 0.01
                let newScale = max(0.2, min(3.0, binding.wrappedValue + delta))
                
                DispatchQueue.main.async {
                    binding.wrappedValue = newScale
                }
            } else {
                super.scrollWheel(with: event)
            }
        }
    }
}

extension View {
    func scrollZoomable(scale: Binding<CGFloat>) -> some View {
        self.modifier(ScrollZoomModifier(zoomScale: scale))
    }
}

