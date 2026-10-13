import Foundation
import Combine
import CoreLocation

@MainActor
final class DeviceInformationViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var snapshot: DeviceInfoSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var locationStatus: CLAuthorizationStatus
    @Published private(set) var didRequestWiFiNameAccess = false
    @Published private(set) var locationRequestIssue: String?

    private let locationManager = CLLocationManager()
    private var refreshAfterLoading = false

    override init() {
        locationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func loadIfNeeded() {
        guard snapshot == nil else { return }
        refresh()
    }

    func refresh() {
        guard !isLoading else {
            refreshAfterLoading = true
            return
        }
        isLoading = true
        Task {
            let result = await Task.detached(priority: .utility) {
                DeviceInformationService.load()
            }.value
            snapshot = result
            isLoading = false
            if refreshAfterLoading {
                refreshAfterLoading = false
                refresh()
            }
        }
    }

    func requestWiFiNameAccess() {
        guard locationStatus == .notDetermined else { return }
        didRequestWiFiNameAccess = true
        locationRequestIssue = nil
        locationManager.requestWhenInUseAuthorization()
        // macOS 在实际启动定位服务时显示授权弹窗；坐标结果不用于设备信息。
        locationManager.requestLocation()
    }

    func updateLocationStatus() {
        let previous = locationStatus
        locationStatus = locationManager.authorizationStatus
        if locationStatus != .notDetermined {
            didRequestWiFiNameAccess = false
            locationRequestIssue = nil
        }
        if previous != locationStatus, hasLocationAccess {
            refresh()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let previous = locationStatus
        locationStatus = manager.authorizationStatus
        guard locationStatus != .notDetermined else { return }
        didRequestWiFiNameAccess = false
        locationRequestIssue = nil
        if previous != locationStatus, hasLocationAccess {
            refresh()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 只用一次性请求触发系统授权，不读取或保存坐标。
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        updateLocationStatus()
        if locationStatus == .notDetermined {
            locationRequestIssue = "系统未能完成定位授权请求：\(error.localizedDescription)"
        }
    }

    private var hasLocationAccess: Bool {
        locationStatus == .authorizedAlways
    }
}
