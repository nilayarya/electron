// Copyright 2023 Your Name
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef ELECTRON_SHELL_BROWSER_API_GEOLOCATION_MANAGER_H_
#define ELECTRON_SHELL_BROWSER_API_GEOLOCATION_MANAGER_H_

#include "services/device/public/cpp/geolocation/system_geolocation_source_apple.h"

@class CLLocationManager;
@class LocationManagerDelegate;

namespace device {

class SystemGeolocationSourceAppleCustom : public SystemGeolocationSourceApple {
 public:
  SystemGeolocationSourceAppleCustom();
  ~SystemGeolocationSourceAppleCustom() override;

  static std::unique_ptr<GeolocationSystemPermissionManager>
  CreateGeolocationSystemPermissionManager();

  void RequestPermission() override;
  std::pair<double, double> GetCurrentLocation();
  LocationSystemPermissionStatus GetCurrentSystemPermission() const;

 private:
  CLLocationManager* __strong custom_location_manager;
  LocationManagerDelegate* __strong custom_delegate;
};

}  // namespace device

#endif  // GEOLOCATION_MANAGER_H_
