import Foundation
import Combine
import CoreLocation

@MainActor
final class DeviceInformationViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var snapshot: DeviceInfoSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var locationStatus: CLAuthorizationStatus

    private let locationManager = CLLocationManager()
    private var refreshAfterLocationAuthorization = false

    override init() {
        locationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
    }

    func loadIfNeeded() {
        guard snapshot == nil else { return }
        refresh()
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            let result = await Task.detached(priority: .utility) {
                DeviceInformationService.load()
            }.value
            snapshot = result
            isLoading = false
        }
    }

    func requestWiFiNameAccess() {
        guard locationStatus == .notDetermined else { return }
        refreshAfterLocationAuthorization = true
        locationManager.requestWhenInUseAuthorization()
    }

    func updateLocationStatus() {
        let previous = locationStatus
        locationStatus = locationManager.authorizationStatus
        if previous != locationStatus, locationStatus == .authorizedAlways {
            refresh()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationStatus = manager.authorizationStatus
        guard refreshAfterLocationAuthorization else { return }
        refreshAfterLocationAuthorization = false
        if locationStatus == .authorizedAlways {
            refresh()
        }
    }
}
