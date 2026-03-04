//
//  NotificationObservers.swift
//  Procyon
//
//  Created by Italo Mandara on 24/02/2026.
//

import Combine
import AppKit

final class MountObserver {
    private var cancellables = Set<AnyCancellable>()

    init(onMount: @escaping () -> Void,
         onUnmount: @escaping () -> Void) {

        let center = NSWorkspace.shared.notificationCenter

        center.publisher(for: NSWorkspace.didMountNotification)
            .sink { _ in
                onMount()
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didUnmountNotification)
            .sink { _ in
                onUnmount()
            }
            .store(in: &cancellables)
    }
}

final class LaunchObserver {
    private var cancellables = Set<AnyCancellable>()

    init(onLaunch: @escaping (_: NotificationCenter.Publisher.Output) -> Void,
         onTerminate: @escaping (_: NotificationCenter.Publisher.Output) -> Void) {

        let center = NSWorkspace.shared.notificationCenter

        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { app in
                onLaunch(app)
            }
            .store(in: &cancellables)

        center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { app in
                onTerminate(app)
            }
            .store(in: &cancellables)
    }
}
