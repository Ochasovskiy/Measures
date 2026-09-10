//
//  Units.swift
//  MeasureGo
//
//  Length conversion and imperial formatting, done in Double.
//
//  ARKit hands us Float positions, and that is fine — over a 12 m pool a
//  Float32 represents position to about a micrometre, five orders of magnitude
//  below the tolerance we work to. What is not fine is doing the arithmetic and
//  the unit conversion at that precision and then truncating: Unity's formatter
//  did `(int)(fractionalFeet * 12)`, so 11.97" printed as 11" — up to a full
//  inch thrown away by display code, against a ±2" specification.
//

import Foundation
import simd

enum Units {

    /// One inch is *defined* as exactly 0.0254 m, so this is not an
    /// approximation. Unity multiplied by 3.280839895, a rounded form of
    /// 1/0.3048; dividing by the exact definition avoids that error entirely.
    static let metersPerInch = 0.0254
    static let inchesPerFoot = 12.0

    static func inches(fromMeters meters: Double) -> Double {
        meters / metersPerInch
    }

    static func meters(fromInches inches: Double) -> Double {
        inches * metersPerInch
    }

    /// Straight-line distance in metres, accumulated in Double.
    static func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Double {
        simd_distance(SIMD3<Double>(a), SIMD3<Double>(b))
    }

    /// Imperial reading in Unity's `12' 06"` form, rounded rather than
    /// truncated. Rounding to whole inches *before* splitting off the feet
    /// makes the carry fall out for free: 11.97" becomes 12", which becomes
    /// 1' 00" instead of the impossible 0' 12".
    static func feetInches(fromMeters meters: Double) -> String {
        let totalInches = inches(fromMeters: meters).rounded()
        let feet = (totalInches / inchesPerFoot).rounded(.down)
        let remainder = totalInches - feet * inchesPerFoot
        return String(format: "%d' %02d\"", Int(feet), Int(remainder))
    }

    /// Same reading for a pair of world positions.
    static func feetInches(from a: SIMD3<Float>, to b: SIMD3<Float>) -> String {
        feetInches(fromMeters: distance(a, b))
    }
}
