// Copyright 2023 Your Name
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "shell/browser/api/geolocation_manager.h"
#include "services/device/public/cpp/geolocation/location_manager_delegate.h"

namespace device {

SystemGeolocationSourceAppleCustom::SystemGeolocationSourceAppleCustom()
    : SystemGeolocationSourceApple() {
  custom_location_manager = [[CLLocationManager alloc] init];
  custom_delegate = SystemGeolocationSourceApple::GetDelegateForTesting();
  custom_location_manager.delegate = custom_delegate;
  SystemGeolocationSourceApple::SetLocationManagerForTesting(
      custom_location_manager);
}

SystemGeolocationSourceAppleCustom::~SystemGeolocationSourceAppleCustom() =
    default;

// static
std::unique_ptr<GeolocationSystemPermissionManager>
SystemGeolocationSourceAppleCustom::CreateGeolocationSystemPermissionManager() {
  return std::make_unique<GeolocationSystemPermissionManager>(
      std::make_unique<SystemGeolocationSourceAppleCustom>());
}

void SystemGeolocationSourceAppleCustom::RequestPermission() {
  LocationSystemPermissionStatus status = GetCurrentSystemPermission();
  if (status == LocationSystemPermissionStatus::kNotDetermined) {
    [custom_location_manager requestWhenInUseAuthorization];
  } else if (status == LocationSystemPermissionStatus::kDenied) {
    OpenSystemPermissionSetting();
  }
}

std::pair<double, double>
SystemGeolocationSourceAppleCustom::GetCurrentLocation() {
  RequestPermission();
  double latitude = [custom_location_manager location].coordinate.latitude;
  double longitude = [custom_location_manager location].coordinate.longitude;
  return {latitude, longitude};
}

LocationSystemPermissionStatus
SystemGeolocationSourceAppleCustom::GetCurrentSystemPermission() const {
  if (![custom_delegate permissionInitialized]) {
    return LocationSystemPermissionStatus::kNotDetermined;
  }
  if ([custom_delegate hasPermission]) {
    return LocationSystemPermissionStatus::kAllowed;
  }
  return LocationSystemPermissionStatus::kDenied;
}

}  // namespace device
