// swift-tools-version: 6.2
//
//  Package.swift
//  DesignReviewKit
//
//  Created by Naveen Gaur on 11/06/2026.
//

import PackageDescription

let package = Package(
    name: "DesignReviewKit",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(
            name: "DesignReviewKit",
            targets: ["DesignReviewKit"]
        )
    ],
    targets: [
        .target(
            name: "DesignReviewKit",
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
