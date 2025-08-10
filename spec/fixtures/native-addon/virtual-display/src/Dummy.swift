import Foundation
import Cocoa
import os.log
import Darwin

class DummyManager {
    struct DefinedDummy {
        var dummy: Dummy
    }

    static var definedDummies: [Int: DefinedDummy] = [:]
    static var dummyCounter: Int = 0
    static var testRunId: UInt32 = 0

    static func createDummy(_ dummyDefinition: DummyDefinition, isPortrait _: Bool = false, serialNum: UInt32 = 0, doConnect: Bool = true) -> Int? {
        print("DummyManager: Creating dummy \(self.dummyCounter + 1) (testRunId: \(self.testRunId))")
        let dummy = Dummy(dummyDefinition: dummyDefinition, serialNum: serialNum, doConnect: doConnect)
        print("DummyManager: Dummy created, isConnected: \(dummy.isConnected)")
        // Check if dummy was created successfully
        if !dummy.isConnected {
            print("DummyManager: Failed to create dummy - not connected")
            return nil
        }
        self.dummyCounter += 1
        self.definedDummies[self.dummyCounter] = DefinedDummy(dummy: dummy)
        print("DummyManager: Successfully created dummy \(self.dummyCounter), total active: \(self.definedDummies.count)")
        return self.dummyCounter
    }

    static func discardDummyByNumber(_ number: Int) {
        print("DummyManager: Discarding dummy \(number)")

        if let definedDummy = self.definedDummies[number] {
            if definedDummy.dummy.isConnected {
                definedDummy.dummy.disconnect()
            }
        }
        self.definedDummies[number] = nil

        print("DummyManager: Discarded dummy \(number), remaining active: \(self.definedDummies.count)")
    }

    static func forceCleanup() {
        print("DummyManager: DISPLAY ID RESET cleanup")
        
        // Step 1: Disconnect all displays
        for (_, definedDummy) in self.definedDummies {
            if definedDummy.dummy.isConnected {
                definedDummy.dummy.virtualDisplay = nil
                definedDummy.dummy.displayIdentifier = 0
                definedDummy.dummy.isConnected = false
            }
        }
        
        // Step 2: Clear our state
        self.definedDummies.removeAll()
        self.dummyCounter = 0
    
        // Step 3: FORCE CoreGraphics to reset display ID pool
        var config: CGDisplayConfigRef? = nil
        if CGBeginDisplayConfiguration(&config) == .success {
            // Force a complete display reconfiguration
            CGCompleteDisplayConfiguration(config, .permanently)
            print("DummyManager: Forced permanent display reconfiguration")
        }
        
        // Step 4: Wait for CoreGraphics to settle
        usleep(2000000) // 2 seconds
        
        // Step 5: Trigger another config cycle to reset ID allocation
        if CGBeginDisplayConfiguration(&config) == .success {
            CGCompleteDisplayConfiguration(config, .forSession)
            print("DummyManager: Reset session display configuration")
        }
        
        print("DummyManager: DISPLAY ID RESET cleanup complete")
    }
 

}

struct DummyDefinition {
    let aspectWidth, aspectHeight, multiplierStep, minMultiplier, maxMultiplier: Int
    let refreshRates: [Double]
    let description: String
    let addSeparatorAfter: Bool

    init(_ aspectWidth: Int, _ aspectHeight: Int, _ step: Int, _ refreshRates: [Double], _ description: String, _ addSeparatorAfter: Bool = false) {
        let minX: Int = 720
        let minY: Int = 720
        let maxX: Int = 8192
        let maxY: Int = 8192
        let minMultiplier = max(Int(ceil(Float(minX) / (Float(aspectWidth) * Float(step)))), Int(ceil(Float(minY) / (Float(aspectHeight) * Float(step)))))
        let maxMultiplier = min(Int(floor(Float(maxX) / (Float(aspectWidth) * Float(step)))), Int(floor(Float(maxY) / (Float(aspectHeight) * Float(step)))))
        
        self.aspectWidth = aspectWidth
        self.aspectHeight = aspectHeight
        self.minMultiplier = minMultiplier
        self.maxMultiplier = maxMultiplier
        self.multiplierStep = step
        self.refreshRates = refreshRates
        self.description = description
        self.addSeparatorAfter = addSeparatorAfter
    }
}

class Dummy: Equatable {
    var virtualDisplay: CGVirtualDisplay?
    var dummyDefinition: DummyDefinition
    let serialNum: UInt32
    var isConnected: Bool = false
    var displayIdentifier: CGDirectDisplayID = 0

    static func == (lhs: Dummy, rhs: Dummy) -> Bool {
        lhs.serialNum == rhs.serialNum
    }

    init(dummyDefinition: DummyDefinition, serialNum: UInt32 = 0, doConnect: Bool = true) {
        var storedSerialNum: UInt32 = serialNum
        if storedSerialNum == 0 {
            storedSerialNum = UInt32.random(in: 0 ... UInt32.max)
        }
        self.dummyDefinition = dummyDefinition
        self.serialNum = storedSerialNum
        if doConnect {
            _ = self.connect()
        }
    }

    func getName() -> String {
        "Dummy \(self.dummyDefinition.description.components(separatedBy: " ").first ?? self.dummyDefinition.description)"
    }

    func connect() -> Bool {
        print("Dummy: Attempting to connect \(self.getName())")
        
        if self.virtualDisplay != nil || self.isConnected {
            print("Dummy: Disconnecting existing display first")
            self.disconnect()
        }
        let name: String = self.getName()
        
        print("Dummy: Creating virtual display with name: \(name), serialNum: \(self.serialNum)")
        
        if let virtualDisplay = Dummy.createVirtualDisplay(self.dummyDefinition, name: name, serialNum: self.serialNum) {
            self.virtualDisplay = virtualDisplay
            self.displayIdentifier = virtualDisplay.displayID
            self.isConnected = true
            print("Display \(name) successfully connected with ID: \(virtualDisplay.displayID)")
            return true
        } else {
            print("Failed to connect display \(name) - createVirtualDisplay returned nil")
            return false
        }
    }

    func disconnect() {
        print("Dummy: Disconnecting virtual display: \(self.getName())")
        self.virtualDisplay = nil
        self.isConnected = false
        print("Dummy: Disconnected virtual display: \(self.getName())")
    }

   private static func waitForDisplayRegistration(_ displayId: CGDirectDisplayID) -> Bool {
        print("waitForDisplayRegistration: Waiting for display \(displayId) to register...")
        
        for attempt in 0..<20 {
            var count: UInt32 = 0, displays = [CGDirectDisplayID](repeating: 0, count: 32)
            if CGGetActiveDisplayList(32, &displays, &count) == .success && displays[0..<Int(count)].contains(displayId) {
                print("waitForDisplayRegistration: Display \(displayId) registered successfully after \(attempt + 1) attempts")
                return true
            }
            print("waitForDisplayRegistration: Attempt \(attempt + 1) - display not found, current count: \(count)")
            usleep(100000)
        }
        print("waitForDisplayRegistration: TIMEOUT - Display \(displayId) never registered")
        return false
    }

    static func createVirtualDisplay(_ definition: DummyDefinition, name: String, serialNum: UInt32, hiDPI: Bool = false) -> CGVirtualDisplay? {
        print("createVirtualDisplay: Starting creation for \(name)")
        
        if let descriptor = CGVirtualDisplayDescriptor() {
            print("createVirtualDisplay: CGVirtualDisplayDescriptor created successfully")
            
            descriptor.queue = DispatchQueue.global(qos: .userInteractive)
            descriptor.name = "\(name)-run\(DummyManager.testRunId)"
            descriptor.whitePoint = CGPoint(x: 0.950, y: 1.000)
            descriptor.redPrimary = CGPoint(x: 0.454, y: 0.242)
            descriptor.greenPrimary = CGPoint(x: 0.353, y: 0.674)
            descriptor.bluePrimary = CGPoint(x: 0.157, y: 0.084)
            descriptor.maxPixelsWide = UInt32(definition.aspectWidth * definition.multiplierStep * definition.maxMultiplier)
            descriptor.maxPixelsHigh = UInt32(definition.aspectHeight * definition.multiplierStep * definition.maxMultiplier)
            let diagonalSizeRatio: Double = (24 * 25.4) / sqrt(Double(definition.aspectWidth * definition.aspectWidth + definition.aspectHeight * definition.aspectHeight))
            descriptor.sizeInMillimeters = CGSize(width: Double(definition.aspectWidth) * diagonalSizeRatio, height: Double(definition.aspectHeight) * diagonalSizeRatio)
            descriptor.serialNum = serialNum + (DummyManager.testRunId * 1000)
            descriptor.productID = UInt32(min(definition.aspectWidth - 1, 255) * 256 + min(definition.aspectHeight - 1, 255))
            descriptor.vendorID = UInt32(0xF0F0 + DummyManager.testRunId)
        
            print("createVirtualDisplay: Descriptor configured - serialNum: \(descriptor.serialNum), vendorID: \(descriptor.vendorID), name: \(descriptor.name)")
            
            if let display = CGVirtualDisplay(descriptor: descriptor) {
                print("createVirtualDisplay: CGVirtualDisplay created successfully, displayID: \(display.displayID)")
                
                var modes = [CGVirtualDisplayMode?](repeating: nil, count: definition.maxMultiplier - definition.minMultiplier + 1)
                for multiplier in definition.minMultiplier ... definition.maxMultiplier {
                    for refreshRate in definition.refreshRates {
                        let width = UInt32(definition.aspectWidth * multiplier * definition.multiplierStep)
                        let height = UInt32(definition.aspectHeight * multiplier * definition.multiplierStep)
                        modes[multiplier - definition.minMultiplier] = CGVirtualDisplayMode(width: width, height: height, refreshRate: refreshRate)!
                    }
                }
                print("createVirtualDisplay: Display modes created, count: \(modes.count)")
                
                if let settings = CGVirtualDisplaySettings() {
                    print("createVirtualDisplay: CGVirtualDisplaySettings created")
                    settings.hiDPI = hiDPI ? 1 : 0
                    settings.modes = modes as [Any]
                    
                    print("createVirtualDisplay: Applying settings...")
                    if display.applySettings(settings) {
                        print("createVirtualDisplay: Settings applied successfully, waiting for registration...")
                        let registered = waitForDisplayRegistration(display.displayID)
                        print("createVirtualDisplay: Registration result: \(registered)")
                        return registered ? display : nil
                    } else {
                        print("createVirtualDisplay: FAILED to apply settings")
                        return nil
                    }
                } else {
                    print("createVirtualDisplay: FAILED to create CGVirtualDisplaySettings")
                    return nil
                }
            } else {
                print("createVirtualDisplay: FAILED to create CGVirtualDisplay")
                return nil
            }
        } else {
            print("createVirtualDisplay: FAILED to create CGVirtualDisplayDescriptor")
            return nil
        }
    }
}