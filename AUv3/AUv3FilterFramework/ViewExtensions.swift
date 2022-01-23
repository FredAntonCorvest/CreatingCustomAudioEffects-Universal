/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Small extensions to simplify view handling in the demo app.
*/

public extension UIView {
    func pinToSuperviewEdges() {
        guard let superview = superview else { return }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: superview.topAnchor),
            leadingAnchor.constraint(equalTo: superview.leadingAnchor),
            bottomAnchor.constraint(equalTo: superview.bottomAnchor),
            trailingAnchor.constraint(equalTo: superview.trailingAnchor)
        ])
    }

    func setBorder(color: UIColor, width: CGFloat) {
        layer.borderColor = color.cgColor
        layer.borderWidth = CGFloat(width)
    }
}
