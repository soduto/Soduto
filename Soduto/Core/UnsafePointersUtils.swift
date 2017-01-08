//
//  UnsafePointersUtils.swift
//  Soduto
//
//  Created by Admin on 2016-08-03.
//  Copyright © 2016 Soduto. All rights reserved.
//

import Foundation

func bridge<T : AnyObject>(obj : T) -> UnsafeMutableRawPointer {
    return UnsafeMutableRawPointer(Unmanaged.passUnretained(obj).toOpaque())
    // return unsafeAddressOf(obj) // ***
}

func bridge<T : AnyObject>(ptr : UnsafeRawPointer) -> T {
    return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
    // return unsafeBitCast(ptr, T.self) // ***
}

func cast<T,U>(pointer: UnsafeMutablePointer<T>) -> UnsafeMutablePointer<U> {
    return unsafeBitCast(pointer, to: UnsafeMutablePointer<U>.self)
}

func cast<T,U>(pointer: UnsafePointer<T>) -> UnsafePointer<U> {
    return unsafeBitCast(pointer, to: UnsafePointer<U>.self)
}

func castToMutablePointer<T,U>(array: Array<T>) -> UnsafeMutablePointer<U> {
    return array.withUnsafeBufferPointer({ (ptr:UnsafeBufferPointer<T>) -> UnsafeMutablePointer<U> in
        return unsafeBitCast(ptr, to: UnsafeMutablePointer<U>.self)
    })
}

func castToPointer<T,U>(array: Array<T>) -> UnsafePointer<U> {
    return array.withUnsafeBufferPointer({ (ptr:UnsafeBufferPointer<T>) -> UnsafePointer<U> in
        return unsafeBitCast(ptr, to: UnsafePointer<U>.self)
    })
}
