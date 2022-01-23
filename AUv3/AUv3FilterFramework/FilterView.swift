/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The main audio unit interface that enables the user to visually configure the frequency and resonance parameters.
*/

public let defaultMinHertz: Float = 12.0
public let defaultMaxHertz: Float = 20_000.0

/// The delegate protocol for communicating changes to frequency and resonance.
protocol FilterViewDelegate: AnyObject {
    func filterViewTouchBegan(_ filterView: FilterView)
    func filterView(_ filterView: FilterView, didChangeResonance resonance: Float)
    func filterView(_ filterView: FilterView, didChangeFrequency frequency: Float)
    func filterView(_ filterView: FilterView, didChangeFrequency frequency: Float, andResonance resonance: Float)
    func filterViewTouchEnded(_ filterView: FilterView)
    func filterViewDataDidChange(_ filterView: FilterView)
}

extension Comparable {
    func clamp(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

extension CATransaction {
    class func noAnimation(_ completion: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        completion()
        CATransaction.commit()
    }
}

extension UIColor {
    var darker: UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return UIColor(hue: hue, saturation: saturation, brightness: brightness * 0.8, alpha: alpha)
    }
}

class FilterView: UIView {

    // MARK: Properties

    let logBase = 2
    let leftMargin: CGFloat = 54.0
    let rightMargin: CGFloat = 10.0
    let bottomMargin: CGFloat = 40.0

    let numDBLines = 4
    let defaultGain = 20

    let gridLineCount = 11

    let labelWidth: CGFloat = 40.0
    let maxNumberOfResponseFrequencies = 1024

    var frequencies: [Double]?

    var dbLines = [CALayer]()
    var dbLabels = [CATextLayer]()

    var freqLines = [CALayer]()
    var frequencyLabels = [CATextLayer]()

    var controls = [CALayer]()

    var graphLayer = CALayer()
    var containerLayer = CALayer()

    var curveLayer: CAShapeLayer = {
        let shapeLayer = CAShapeLayer()
        
        shapeLayer.fillColor = UIColor(named: "FillColor")!.cgColor

        return shapeLayer
    }()

    // The delegate to notify of paramater and size changes.
    weak var delegate: FilterViewDelegate?

    var editPoint = CGPoint.zero
    var touchDown = false

    var rootLayer: CALayer {
        return layer
    }

    var screenScale: CGFloat {
        return UIScreen.main.scale
    }

    // The cutoff frequency.
    var frequency: Float = defaultMinHertz {
        didSet {
            frequency = frequency.clamp(to: defaultMinHertz...defaultMaxHertz)

            editPoint.x = floor(locationForFrequencyValue(frequency))

            // Don't notify the delegate when the frequency changes
            // because that creates a feedback loop.
        }
    }

    // The narrow band of the cutoff frequency to boost or attenuate.
    var resonance: Float = 0.0 {
        didSet {
            // Clamp the resonance to minimum and maximum values.
            let gain = Float(defaultGain)
            resonance = resonance.clamp(to: -gain...gain)

            // Set the edit point y position.
            editPoint.y = floor(locationForDBValue(resonance))

            // Don't notify the delegate when the resonance changes
            // because that creates a feedback loop.
        }
    }

    /*
     The frequencies plot using a logorithmic scale. This method returns a
     frequency value from a fractional grid position.
     */
    func valueAtGridIndex(_ index: Float) -> Float {
        return defaultMinHertz * powf(Float(logBase), index)
    }

    func logValueForNumber(_ number: Float, base: Float) -> Float {
        return logf(number) / logf(base)
    }

    /*
     Prepares an array of frequencies that the audio unit needs to supply magnitudes
     for. This array caches until the view size changes (on device rotation, and so
     forth).
     */
    func frequencyDataForDrawing() -> [Double] {
        guard frequencies == nil else { return frequencies! }

        let width = graphLayer.bounds.width
        let rightEdge = width + leftMargin

        var pixelRatio = Int(ceil(width / CGFloat(maxNumberOfResponseFrequencies)))
        var location = leftMargin
        var locationsCount = maxNumberOfResponseFrequencies

        if pixelRatio <= 1 {
            pixelRatio = 1
            locationsCount = Int(width)
        }

        frequencies = (0..<locationsCount).map { _ in
            if location > rightEdge {
                return Double(defaultMaxHertz)
            } else {
                var frequency = frequencyValueForLocation(location)

                if frequency > defaultMaxHertz {
                    frequency = defaultMaxHertz
                }

                location += CGFloat(pixelRatio)

                return Double(frequency)
            }
        }
        return frequencies!
    }

    /*
     Generates a Bezier path from the frequency response curve data that the view
     controller provides. It also responsible for keeping the control point in sync.
     */
    func setMagnitudes(_ magnitudeData: [Double]) {

        let bezierPath = CGMutablePath()
        let width = graphLayer.bounds.width

        bezierPath.move(to: CGPoint(x: leftMargin, y: graphLayer.frame.height + bottomMargin))

        var lastDBPosition: CGFloat = 0.0

        var location: CGFloat = leftMargin

        let frequencyCount = frequencies?.count ?? 0

        let pixelRatio = Int(ceil(width / CGFloat(frequencyCount)))

        for i in 0 ..< frequencyCount {
            let dbValue = 20.0 * log10(magnitudeData[i])
            var dbPosition: CGFloat = 0.0

            switch dbValue {
            case let x where x < Double(-defaultGain):
                dbPosition = locationForDBValue(Float(-defaultGain))

            case let x where x > Double(defaultGain):
                dbPosition = locationForDBValue(Float(defaultGain))

            default:
                dbPosition = locationForDBValue(Float(dbValue))
            }

            if abs(lastDBPosition - dbPosition) >= 0.1 {
                bezierPath.addLine(to: CGPoint(x: location, y: dbPosition))
            }

            lastDBPosition = dbPosition
            location += CGFloat(pixelRatio)

            if location > width + graphLayer.frame.origin.x {
                location = width + graphLayer.frame.origin.x
                break
            }
        }

        bezierPath.addLine(to: CGPoint(x: location,
                                       y: graphLayer.frame.origin.y + graphLayer.frame.height + bottomMargin))

        bezierPath.closeSubpath()

        // Turn off implict animation on the curve layer.
        CATransaction.noAnimation {
            curveLayer.path = bezierPath
        }

        updateControls(refreshColor: true)
    }

    // Calculates the pixel position on the x-axis of the graph corresponding to the frequency value.
    func locationForFrequencyValue(_ value: Float) -> CGFloat {
        let pixelIncrement = graphLayer.frame.width / CGFloat(gridLineCount)
        let number = value / defaultMinHertz
        let location = logValueForNumber(number, base: Float(logBase)) * Float(pixelIncrement)
        return floor(CGFloat(location) + graphLayer.frame.origin.x) + 0.5
    }

    // Calculates the frequency value corresponding to a position value on the x-axis of the graph.
    func frequencyValueForLocation(_ location: CGFloat) -> Float {
        let pixelIncrement = graphLayer.frame.width / CGFloat(gridLineCount)
        let index = (location - graphLayer.frame.origin.x) / CGFloat(pixelIncrement)
        return valueAtGridIndex(Float(index))
    }

    // Calculates the dB value corresponding to a position value on the y-axis of the graph.
    func dbValueForLocation(_ location: CGFloat) -> Float {
        let step = graphLayer.frame.height / CGFloat(defaultGain * 2)
        return Float(-(((location - bottomMargin) / step) - CGFloat(defaultGain)))
    }

    // Calculates the pixel position on the y-axis of the graph corresponding to the dB value.
    func locationForDBValue(_ value: Float) -> CGFloat {
        let step = graphLayer.frame.height / CGFloat(defaultGain * 2)
        let location = (CGFloat(value) + CGFloat(defaultGain)) * step
        return graphLayer.frame.height - location + bottomMargin
    }

    /*
     Provides a properly formatted string with an appropriate precision for the
     input value.
     */
    func stringForValue(_ value: Float) -> String {
        var temp = value

        if value >= 1000 {
            temp /= 1000
        }

        temp = floor((temp * 100.0) / 100.0)

        if floor(temp) == temp {
            return String(format: "%.0f", temp)
        } else {
            return String(format: "%.1f", temp)
        }
    }

    private func newLayer(of size: CGSize) -> CALayer {
        let layer = CALayer()
        layer.anchorPoint = .zero
        layer.frame = CGRect(origin: .zero, size: size)
        layer.contentsScale = screenScale
        return layer
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        // Create all of the CALayers for the graph, lines, and labels.

        containerLayer.name = "container"
        containerLayer.anchorPoint = .zero
        containerLayer.frame = CGRect(origin: .zero, size: rootLayer.bounds.size)
        containerLayer.bounds = containerLayer.frame
        containerLayer.contentsScale = screenScale
        rootLayer.addSublayer(containerLayer)
        rootLayer.masksToBounds = false

        graphLayer.name = "graph background"
        graphLayer.borderColor = UIColor.darkGray.cgColor
        graphLayer.borderWidth = 1.0
        graphLayer.backgroundColor = UIColor(white: 0.88, alpha: 1.0).cgColor
        graphLayer.bounds = CGRect(x: 0, y: 0,
                                   width: rootLayer.frame.width - leftMargin,
                                   height: rootLayer.frame.height - bottomMargin)
        graphLayer.position = CGPoint(x: leftMargin, y: 0)
        graphLayer.anchorPoint = CGPoint.zero
        graphLayer.contentsScale = screenScale

        containerLayer.addSublayer(graphLayer)

        rootLayer.contentsScale = screenScale

        createDBLabelsAndLines()
        createFrequencyLabelsAndLines()

        // Add the curve layer before creating the control point so layers are
        // stacked as necessary
        graphLayer.addSublayer(curveLayer)

        createControlPoint()
    }

    var graphLabelColor: UIColor {
        return UIColor(white: 0.1, alpha: 1.0)
    }

    /*
     Creates the decibel label layers for the vertical axis of the graph and adds
     them as sublayers of the graph layer. Also creates the dB lines.
     */
    func createDBLabelsAndLines() {
        let range = -numDBLines...numDBLines
        for index in range where range.contains(index) {
            // Calculate the value.
            let value = index * (defaultGain / numDBLines)

            // Create the label.
            let labelLayer = makeLabelLayer(alignment: .right)
            labelLayer.string = "\(value) db"

            dbLabels.append(labelLayer)
            containerLayer.addSublayer(labelLayer)

            // Create the line labels.
            let lineLayer = ColorLayer(white: index == 0 ? 0.65 : 0.8)
            dbLines.append(lineLayer)
            graphLayer.addSublayer(lineLayer)
        }
    }

    class ColorLayer: CALayer {

        init(white: CGFloat) {
            super.init()
            backgroundColor = UIColor(white: white, alpha: 1.0).cgColor
        }

        init(color: UIColor) {
            super.init()
            backgroundColor = color.cgColor
        }

        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    /*
     Creates the frequency label layers for the horizontal axis of the graph and
     adds them as sublayers of the graph layer. It also creates the frequency line
     layers.
     */
    func createFrequencyLabelsAndLines() {

        var firstK = true

        for index in 0 ... gridLineCount {

            let value = valueAtGridIndex(Float(index))

            // Create the label layers and set their properties.
            let labelLayer = makeLabelLayer()
            frequencyLabels.append(labelLayer)

            // Create the line layers.
            switch index {
            case 0:
                labelLayer.string = "\(stringForValue(value)) Hz"

            case let i where i > 0 && i < gridLineCount:
                let lineLayer = ColorLayer(white: 0.8)
                freqLines.append(lineLayer)
                graphLayer.addSublayer(lineLayer)

                var string = stringForValue(value)

                if value >= 1000 && firstK {
                    string += "K"
                    firstK = false
                }

                labelLayer.string = string

            default:
                labelLayer.string = "\(stringForValue(defaultMaxHertz)) K"

            }

            containerLayer.addSublayer(labelLayer)
        }
    }

    func makeLabelLayer(alignment: CATextLayerAlignmentMode = .center) -> CATextLayer {
        let labelLayer = CATextLayer()
        
        labelLayer.font = UIFont.systemFont(ofSize: 14)
        labelLayer.fontSize = 14
        labelLayer.contentsScale = screenScale
        labelLayer.foregroundColor = graphLabelColor.cgColor
        labelLayer.alignmentMode = alignment
        labelLayer.anchorPoint = .zero
        return labelLayer
    }

    /*
     Creates the control point layers comprising a horizontal and vertical
     line (crosshairs) and a circle at the intersection.
     */
    func createControlPoint() {

        guard let color = touchDown ? tintColor : UIColor.darkGray else {
            fatalError("Unable to get color value.")
        }

        var lineLayer = ColorLayer(color: color)
        lineLayer.name = "x"
        controls.append(lineLayer)
        graphLayer.addSublayer(lineLayer)

        lineLayer = ColorLayer(color: color)
        lineLayer.name = "y"
        controls.append(lineLayer)
        graphLayer.addSublayer(lineLayer)

        let circleLayer = ColorLayer(color: color)
        circleLayer.borderWidth = 2.0
        circleLayer.cornerRadius = 3.0
        circleLayer.name = "point"
        controls.append(circleLayer)

        graphLayer.addSublayer(circleLayer)
    }

    /*
     Updates the position of the control layers and the color if the refreshColor
     parameter is true. The controls draw in a blue color if the user's finger
     is touching the graph and is still down.
     */
    func updateControls(refreshColor: Bool) {
        let color = touchDown ? tintColor.darker.cgColor: UIColor.darkGray.cgColor

        // Turn off implicit animations for the control layers to avoid any control lag.
        CATransaction.noAnimation {

            for layer in controls {
                switch layer.name! {
                case "point":
                    layer.frame = CGRect(x: editPoint.x - 3, y: editPoint.y - 3, width: 7, height: 7).integral
                    layer.position = editPoint

                    if refreshColor {
                        layer.borderColor = color
                    }

                case "x":
                    layer.frame = CGRect(x: graphLayer.frame.origin.x,
                                         y: floor(editPoint.y + 0.5),
                                         width: graphLayer.frame.width,
                                         height: 1.0)

                    if refreshColor {
                        layer.backgroundColor = color
                    }

                case "y":
                    layer.frame = CGRect(x: floor(editPoint.x) + 0.5,
                                         y: bottomMargin,
                                         width: 1.0,
                                         height: graphLayer.frame.height)

                    if refreshColor {
                        layer.backgroundColor = color
                    }

                default:
                    layer.frame = .zero
                }
            }
        }
    }

    func updateDBLayers() {
        
        // Update the positions of the dBLine and label layers.
        let range = -numDBLines...numDBLines
        for index in range where range.contains(index) {
            let value = Float(index * (defaultGain / numDBLines))
            let location = floor(locationForDBValue(value))

            dbLines[index + 4].frame = CGRect(x: graphLayer.frame.origin.x,
                                              y: location,
                                              width: graphLayer.frame.width,
                                              height: 1.0)

            dbLabels[index + 4].frame = CGRect(x: 0.0,
                                               y: location - bottomMargin - 8,
                                               width: leftMargin - 7.0,
                                               height: 16.0)
        }
    }

    func updateFrequencyLayers() {

        let graphHeight = graphLayer.frame.height

        // Update the positions of the frequency line and label layers.
        for index in 0...gridLineCount {
            let value = valueAtGridIndex(Float(index))
            let location = floor(locationForFrequencyValue(value))

            if index > 0 && index < gridLineCount {
                freqLines[index - 1].frame = CGRect(x: location,
                                                    y: bottomMargin,
                                                    width: 1.0,
                                                    height: graphHeight)

                frequencyLabels[index].frame = CGRect(x: location - labelWidth / 2.0,
                                                      y: graphHeight,
                                                      width: labelWidth,
                                                      height: 16.0)
            }

            frequencyLabels[index].frame = CGRect(x: location - (labelWidth / 2.0) - rightMargin,
                                                  y: graphHeight + 16,
                                                  width: labelWidth + rightMargin,
                                                  height: 16.0)
        }
    }

    /*
     This function positions all of the layers of the view starting with
     the horizontal dbLines and labels on the y-axis. Next, it positions
     the vertical frequency lines and labels on the x-axis. Finally, it
     positions the controls and the curve layer.

     The system also calls this method when the orientation of the device changes
     and the view needs to relayout for the new view size.
     */
    override func layoutSublayers(of layer: CALayer) {
        performLayout(of: layer)
    }

    func performLayout(of layer: CALayer) {
        if layer === rootLayer {
            // Disable implicit layer animations.
            CATransaction.noAnimation {
                containerLayer.bounds = rootLayer.bounds

                graphLayer.bounds = CGRect(x: leftMargin, y: bottomMargin,
                                           width: layer.bounds.width - leftMargin - rightMargin,
                                           height: layer.bounds.height - bottomMargin - 10.0)

                updateDBLayers()

                updateFrequencyLayers()

                editPoint = CGPoint(x: locationForFrequencyValue(frequency), y: locationForDBValue(resonance))

                curveLayer.bounds = graphLayer.bounds

                curveLayer.frame = CGRect(x: graphLayer.frame.origin.x,
                                          y: graphLayer.frame.origin.y + bottomMargin,
                                          width: graphLayer.frame.width,
                                          height: graphLayer.frame.height)
            }
        }

        updateControls(refreshColor: false)

        frequencies = nil

        /*
         Notify the view controller when the bounds change -- meaning that new
         frequency data is available.
         */
        delegate?.filterViewDataDidChange(self)
    }

    /*
     If either the frequency or resonance (or both) change, notify the delegate
     as appropriate.
     */
    func updateFrequenciesAndResonance() {
        let lastFrequency = frequencyValueForLocation(editPoint.x)
        let lastResonance = dbValueForLocation(editPoint.y)

        if lastFrequency != frequency && lastResonance != resonance {
            frequency = lastFrequency
            resonance = lastResonance

            // Notify the delegate when the frequency changes.
            delegate?.filterView(self, didChangeFrequency: frequency, andResonance: resonance)
        }

        if lastFrequency != frequency {
            frequency = lastFrequency

            // Notify the delegate when the frequency changes.
            delegate?.filterView(self, didChangeFrequency: frequency)
        }

        if lastResonance != resonance {
            resonance = lastResonance

            // Notify the delegate when the frequency changes.
            delegate?.filterView(self, didChangeResonance: resonance)
        }
    }

    // MARK: Touch Event Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var pointOfTouch = touches.first?.location(in: self) else { return }

        pointOfTouch = CGPoint(x: pointOfTouch.x, y: pointOfTouch.y + bottomMargin)

        if graphLayer.contains(pointOfTouch) {
            touchDown = true
            editPoint = pointOfTouch
            updateFrequenciesAndResonance()
            delegate?.filterViewTouchBegan(self)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var pointOfTouch = touches.first?.location(in: self) else { return }

        pointOfTouch = CGPoint(x: pointOfTouch.x, y: pointOfTouch.y + bottomMargin)

        if graphLayer.contains(pointOfTouch) {
            handleDrag(pointOfTouch)

            updateFrequenciesAndResonance()
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var pointOfTouch = touches.first?.location(in: self) else { return }

        pointOfTouch = CGPoint(x: pointOfTouch.x, y: pointOfTouch.y + bottomMargin)

        if graphLayer.contains(pointOfTouch) {
            handleDrag(pointOfTouch)
        }

        touchDown = false

        updateFrequenciesAndResonance()
        delegate?.filterViewTouchEnded(self)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchDown = false
    }

    func handleDrag(_ dragPoint: CGPoint) {
        if dragPoint.x < 0 {
            editPoint.x = 0
        } else if dragPoint.x > graphLayer.frame.width + leftMargin {
            editPoint.x = graphLayer.frame.width + leftMargin
        } else {
            editPoint.x = dragPoint.x
        }

        if dragPoint.y < 0 {
            editPoint.y = 0
        } else if dragPoint.y > graphLayer.frame.height + bottomMargin {
            editPoint.y = graphLayer.frame.height + bottomMargin
        } else {
            editPoint.y = dragPoint.y
        }
    }
}
