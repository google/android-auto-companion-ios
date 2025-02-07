// Copyright 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

@testable internal import AndroidAutoConnectedDeviceManager

/// A fake `PListLoader` that simply returns the overlay config that is set on it.
///
/// The overlay config can also be set after it has been created.
struct PListLoaderFake: PListLoader {
  var overlay: Overlay

  init(overlayValues: [String: Any] = [:]) {
    self.overlay = Overlay(overlayValues)
  }

  func loadOverlayValues() -> Overlay {
    return overlay
  }
}
