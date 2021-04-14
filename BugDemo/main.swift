import AVFoundation

class TestingAU: AUAudioUnit {
    private var inputBusArray: [AUAudioUnitBus] = []
    private var outputBusArray: [AUAudioUnitBus] = []
    private var internalBuffers: [AVAudioPCMBuffer] = []
    
    /// Allocate the render resources
    override public func allocateRenderResources() throws {
        try super.allocateRenderResources()

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100,
                                   channels: 2) ?? AVAudioFormat()

        try inputBusArray.forEach { if $0.format != format { try $0.setFormat(format) } }
        try outputBusArray.forEach { if $0.format != format { try $0.setFormat(format) } }

        // we don't need to allocate a buffer if we can process in place
        if !canProcessInPlace || inputBusArray.count > 1 {
            for i in inputBusArray.indices {
                if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: maximumFramesToRender) {
                    internalBuffers.append(buffer)
                }
            }
        }
    }

    /// Delllocate Render Resources
    override public func deallocateRenderResources() {
        super.deallocateRenderResources()
        internalBuffers = []
    }
    
    private lazy var auInputBusArray: AUAudioUnitBusArray = {
        AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: inputBusArray)
    }()

    /// Input busses
    override public var inputBusses: AUAudioUnitBusArray {
        return auInputBusArray
    }

    private lazy var auOutputBusArray: AUAudioUnitBusArray = {
        AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: outputBusArray)
    }()

    /// Output bus array
    override public var outputBusses: AUAudioUnitBusArray {
        return auOutputBusArray
    }
    
    override var internalRenderBlock: AUInternalRenderBlock {
        return { ( _, _, _, _, _, _, _) in
            return noErr
        }
    }
    
    /// Initialize with component description and options
    /// - Parameters:
    ///   - componentDescription: Audio Component Description
    ///   - options: Audio Component Instantiation Options
    /// - Throws: error
    override public init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions = []) throws {
        try super.init(componentDescription: componentDescription, options: options)

        // create audio bus connection points
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100,
                                   channels: 2) ?? AVAudioFormat()
        for _ in 0..<2 {
            inputBusArray.append(try AUAudioUnitBus(format: format))
        }
        for _ in 0..<2 {
            outputBusArray.append(try AUAudioUnitBus(format: format))
        }
    }

}

public func fourCC(_ string: String) -> UInt32 {
    let utf8 = string.utf8
    precondition(utf8.count == 4, "Must be a 4 character string")
    var out: UInt32 = 0
    for char in utf8 {
        out <<= 8
        out |= UInt32(char)
    }
    return out
}

var dryWet: AVAudioUnit!

let engine = AVAudioEngine()

let player = AVAudioPlayerNode()
engine.attach(player)
let desc = AudioComponentDescription(componentType: kAudioUnitType_Mixer,
                                     componentSubType: fourCC("dwm2"),
                                     componentManufacturer: fourCC("AuKt"),
                                     componentFlags: AudioComponentFlags.sandboxSafe.rawValue,
                                     componentFlagsMask: 0)

AUAudioUnit.registerSubclass(TestingAU.self,
                             as: desc,
                             name: "Local DryWetMixer",
                             version: .max)
AVAudioUnit.instantiate(with: desc) { avAudioUnit, _ in
    guard let au = avAudioUnit else {
        fatalError("Unable to instantiate AVAudioUnit")
    }
    dryWet = au
    print("instantiated")
}

engine.attach(dryWet)

let outputMixer = AVAudioMixerNode()
engine.attach(outputMixer)
engine.connect(dryWet, to: outputMixer, format: nil)

let someOtherMixer = AVAudioMixerNode()
engine.attach(someOtherMixer)
engine.connect(someOtherMixer, to: outputMixer, format: nil)

engine.connect(outputMixer, to: engine.mainMixerNode, format: nil)

try! engine.start()
engine.connect(player, to: [.init(node: dryWet, bus: 0), .init(node: dryWet, bus: 1), .init(node: someOtherMixer, bus: someOtherMixer.nextAvailableInputBus)], fromBus: 0, format: nil)

sleep(2)

engine.stop()
