/*
See LICENSE folder for this sample’s licensing information.

Abstract:
An AUAudioUnit subclass that implements a low-pass filter with resonance.
*/

import Foundation
import AudioToolbox
import AVFoundation
import CoreAudioKit

fileprivate extension AUAudioUnitPreset {
    convenience init(number: Int, name: String) {
        self.init()
        self.number = number
        self.name = name
    }
}

public class AUv3FilterDemo: AUAudioUnit {

    private let parameters: AUv3FilterDemoParameters
    private let kernelAdapter: FilterDSPKernelAdapter

    lazy private var inputBusArray: AUAudioUnitBusArray = {
        AUAudioUnitBusArray(audioUnit: self,
                            busType: .input,
                            busses: [kernelAdapter.inputBus])
    }()

    lazy private var outputBusArray: AUAudioUnitBusArray = {
        AUAudioUnitBusArray(audioUnit: self,
                            busType: .output,
                            busses: [kernelAdapter.outputBus])
    }()

    // The owning view controller.
    weak var viewController: AUv3FilterDemoViewController?

    /// The filter's input busses.
    public override var inputBusses: AUAudioUnitBusArray {
        return inputBusArray
    }

    /// The filter's output busses.
    public override var outputBusses: AUAudioUnitBusArray {
        return outputBusArray
    }
    
    /// The tree of parameters that this audio unit provides.
    public override var parameterTree: AUParameterTree? {
        get { return parameters.parameterTree }
        set { /* The sample doesn't allow modification of this property. */ }
    }

    public override var factoryPresets: [AUAudioUnitPreset] {
        return [
            AUAudioUnitPreset(number: 0, name: "Prominent"),
            AUAudioUnitPreset(number: 1, name: "Bright"),
            AUAudioUnitPreset(number: 2, name: "Warm")
        ]
    }

    private let factoryPresetValues:[(cutoff: AUValue, resonance: AUValue)] = [
        (2500.0, 5.0),    // "Prominent"
        (14_000.0, 12.0), // "Bright"
        (384.0, -3.0)     // "Warm"
    ]

    private var _currentPreset: AUAudioUnitPreset?
    
    /// The currently selected preset.
    public override var currentPreset: AUAudioUnitPreset? {
        get { return _currentPreset }
        set {
            // If the newValue is nil, return.
            guard let preset = newValue else {
                _currentPreset = nil
                return
            }
            
            // Factory presets need to always have a number >= 0.
            if preset.number >= 0 {
                let values = factoryPresetValues[preset.number]
                parameters.setParameterValues(cutoff: values.cutoff, resonance: values.resonance)
                _currentPreset = preset
            }
            // User presets are always negative.
            else {
                // Attempt to restore the archived state for this user preset.
                do {
                    fullStateForDocument = try presetState(for: preset)
                    // Set the currentPreset after successfully restoring the state.
                    _currentPreset = preset
                } catch {
                    print("Unable to restore set for preset \(preset.name)")
                }
            }
        }
    }
    
    /// Indicates that this audio unit supports persisting user presets.
    public override var supportsUserPresets: Bool {
        return true
    }

    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {

        // Create the adapter to communicate to the underlying C++ DSP code.
        kernelAdapter = FilterDSPKernelAdapter()
        
        // Create the parameters object to control the cutoff frequency and resonance.
        parameters = AUv3FilterDemoParameters(kernelAdapter: kernelAdapter)

        // Create the super class.
        try super.init(componentDescription: componentDescription, options: options)

        // Log the component description values.
        log(componentDescription)
        
        // Set the default preset.
        currentPreset = factoryPresets.first
    }

    private func log(_ acd: AudioComponentDescription) {

        let info = ProcessInfo.processInfo
        print("\nProcess Name: \(info.processName) PID: \(info.processIdentifier)\n")

        let message = """
        AUv3FilterDemo (
                  type: \(acd.componentType.stringValue)
               subtype: \(acd.componentSubType.stringValue)
          manufacturer: \(acd.componentManufacturer.stringValue)
                 flags: \(String(format: "%#010x", acd.componentFlags))
        )
        """
        print(message)
    }

    // Gets the magnitudes that correspond to the specified frequencies.
    func magnitudes(forFrequencies frequencies: [Double]) -> [Double] {
        return kernelAdapter.magnitudes(forFrequencies: frequencies as [NSNumber]).map { $0.doubleValue }
    }

    public override var maximumFramesToRender: AUAudioFrameCount {
        get {
            return kernelAdapter.maximumFramesToRender
        }
        set {
            if !renderResourcesAllocated {
                kernelAdapter.maximumFramesToRender = newValue
            }
        }
    }

    public override func allocateRenderResources() throws {
        if kernelAdapter.outputBus.format.channelCount != kernelAdapter.inputBus.format.channelCount {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(kAudioUnitErr_FailedInitialization), userInfo: nil)
        }
        try super.allocateRenderResources()
        kernelAdapter.allocateRenderResources()
    }

    public override func deallocateRenderResources() {
        super.deallocateRenderResources()
        kernelAdapter.deallocateRenderResources()
    }

    public override var internalRenderBlock: AUInternalRenderBlock {
        return kernelAdapter.internalRenderBlock()
    }

    // A Boolean value that indicates whether the audio unit can process the input
    // audio in-place in the input buffer without requiring a separate output buffer.
    public override var canProcessInPlace: Bool {
        return true
    }

    // MARK: View Configurations
    public override func supportedViewConfigurations(_ availableViewConfigurations: [AUAudioUnitViewConfiguration]) -> IndexSet {
        var indexSet = IndexSet()

        let min = CGSize(width: 400, height: 100)
        let max = CGSize(width: 800, height: 500)

        for (index, config) in availableViewConfigurations.enumerated() {

            let size = CGSize(width: config.width, height: config.height)

            if size.width <= min.width && size.height <= min.height ||
                size.width >= max.width && size.height >= max.height ||
                size == .zero {

                indexSet.insert(index)
            }
        }
        return indexSet
    }

    public override func select(_ viewConfiguration: AUAudioUnitViewConfiguration) {
        viewController?.selectViewConfiguration(viewConfiguration)
    }
}

extension FourCharCode {
    var stringValue: String {
        let value = CFSwapInt32BigToHost(self)
        let bytes = [0, 8, 16, 24].map { UInt8(value >> $0 & 0x000000FF) }
        guard let result = String(bytes: bytes, encoding: .utf8) else {
            return "fail"
        }
        return result
    }
}
