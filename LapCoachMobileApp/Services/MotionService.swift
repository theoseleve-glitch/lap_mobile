import CoreMotion
import Foundation

protocol MotionServiceType: AnyObject {
    var onMotionUpdate: ((MotionSnapshot) -> Void)? { get set }
    func start()
    func stop()
}

final class MotionService: MotionServiceType {
    private let motionManager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.lapcoach.motion"
        return queue
    }()

    var onMotionUpdate: ((MotionSnapshot) -> Void)?

    init() {
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
    }

    func start() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let motion else { return }

            let snapshot = MotionSnapshot(
                timestampMs: Int64(Date().timeIntervalSince1970 * 1_000.0),
                ax: motion.userAcceleration.x * 9.80665,
                ay: motion.userAcceleration.y * 9.80665,
                az: motion.userAcceleration.z * 9.80665,
                gx: motion.rotationRate.x,
                gy: motion.rotationRate.y,
                gz: motion.rotationRate.z
            )
            self?.onMotionUpdate?(snapshot)
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
    }
}
