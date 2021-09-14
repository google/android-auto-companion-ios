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

package com.google.android.libraries.car.trustagent.testutils

import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.ScanRecord
import android.bluetooth.le.ScanResult
import android.os.ParcelUuid

// A collection to create fakes of Android platform classes.

/** Creates a [ScanRecord] with reflection since its constructor is private. */
fun createScanRecord(
  name: String?,
  serviceUuids: List<ParcelUuid>,
  serviceData: Map<ParcelUuid, ByteArray>
): ScanRecord {
  val constructor = ScanRecord::class.java.getDeclaredConstructor()
  constructor.setAccessible(true)

  val deviceNameField = ScanRecord::class.java.getDeclaredField("mDeviceName")
  deviceNameField.setAccessible(true)

  val serviceUuidsField = ScanRecord::class.java.getDeclaredField("mServiceUuids")
  serviceUuidsField.setAccessible(true)

  val serviceDataField = ScanRecord::class.java.getDeclaredField("mServiceData")
  serviceDataField.setAccessible(true)

  return constructor.newInstance().also {
    deviceNameField.set(it, name)
    serviceUuidsField.set(it, serviceUuids)
    serviceDataField.set(it, serviceData)
  }
}

/** Creates a [ScanResult] that contains [scanRecord]. */
fun createScanResult(scanRecord: ScanRecord) =
  ScanResult(
    BluetoothAdapter.getDefaultAdapter().getRemoteDevice("00:11:22:33:AA:BB"),
    /* eventType= */ 0,
    /* primaryPhy= */ 0,
    /* secondaryPhy= */ 0,
    /* advertisingSid= */ 0,
    /* txPower= */ 0,
    /* rssi= */ 0,
    /* periodicAdveritsingInterval= */ 0,
    scanRecord,
    System.currentTimeMillis()
  )
