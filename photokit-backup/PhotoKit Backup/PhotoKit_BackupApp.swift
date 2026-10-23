//
//  PhotoKit_BackupApp.swift
//  PhotoKit Backup
//
//  Created by Tinus de Roode on 20/10/2026.
//

import SwiftUI
@preconcurrency import UserNotifications

@main
struct PhotoKit_BackupApp: App {
  init() {
    UNUserNotificationCenter.current().delegate = StayOpenNotificationDelegate.shared
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}

private nonisolated final class StayOpenNotificationDelegate: NSObject,
  UNUserNotificationCenterDelegate
{
  static let shared = StayOpenNotificationDelegate()

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    let identifier = notification.request.identifier
    guard identifier.hasPrefix(BackupModel.fastBackupStayOpenNotice) else { return [] }
    return [.banner, .list]
  }
}
