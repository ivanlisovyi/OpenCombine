//
//  NSObject.swift
//  
//
//  Created by Ivan Lisovyi on 13.04.20.
//

import Foundation
import OpenCombine

public protocol _KeyValueCodingAndObservingPublishing {}

extension NSObject: _KeyValueCodingAndObservingPublishing {}

public extension _KeyValueCodingAndObservingPublishing where Self: NSObject {
    var ocombine: OCombine<Self> { return OCombine(subject: self) }
    
    #if !canImport(Combine)
    func publisher<Value>(
        for keyPath: KeyPath<Self, Value>,
        options: NSKeyValueObservingOptions = [.initial, .new]
    ) -> OCombine<Self>.KeyValueObservingPublisher<Self, Value> {
        return ocombine.publisher(for: keyPath, options: options)
    }
    
    typealias KeyValueObservingPublisher = OCombine<Self>.KeyValueObservingPublisher
    #endif
}

extension NSObject {
    public class OCombine<Subject: NSObject> {
        public let subject: Subject
        
        public init(subject: Subject) {
            self.subject = subject
        }
        
        public struct KeyValueObservingPublisher<Subject, Value>: OpenCombine.Publisher where Subject: NSObject {
            public typealias Output = Value
            public typealias Failure = Never
            
            public let subject: Subject
            public let keyPath: KeyPath<Subject, Value>
            public let options: NSKeyValueObservingOptions
            
            public init(
                subject: Subject,
                keyPath: KeyPath<Subject, Value>,
                options: NSKeyValueObservingOptions
            ) {
                self.subject = subject
                self.keyPath = keyPath
                self.options = options
            }
            
            public func receive<Downstream: Subscriber>(subscriber: Downstream)
                where Downstream.Failure == Never, Downstream.Input == Value
            {
                let subscription = KeyValueObservingSubscription(
                    subject: subject,
                    keyPath: keyPath,
                    options: options,
                    downstream: subscriber
                )
                subscriber.receive(subscription: subscription)
            }
        }
        
        public func publisher<Value>(
            for keyPath: KeyPath<Subject, Value>,
            options: NSKeyValueObservingOptions = [.initial, .new]
        ) ->  OCombine.KeyValueObservingPublisher<Subject, Value> {
            KeyValueObservingPublisher(subject: subject, keyPath: keyPath, options: options)
        }
    }
}

extension NSObject {
    fileprivate final class KeyValueObservingSubscription<DownStream: Subscriber, Subject: NSObject, Value>:
        OpenCombine.Subscription,
        CustomStringConvertible,
        CustomReflectable,
        CustomPlaygroundDisplayConvertible
        where DownStream.Input == Value, DownStream.Failure == Never
    {
        private let lock = UnfairLock.allocate()
        fileprivate let downstreamLock = UnfairRecursiveLock.allocate()
        
        private var demand = Subscribers.Demand.none
        private var downstream: DownStream
        
        private var subject: Subject?
        private let keyPath: KeyPath<Subject, Value>
        private let options: NSKeyValueObservingOptions
        
        private var observation: NSKeyValueObservation?
        
        fileprivate init(
            subject: Subject,
            keyPath: KeyPath<Subject, Value>,
            options: NSKeyValueObservingOptions,
            downstream: DownStream
        ) {
            self.subject = subject
            self.keyPath = keyPath
            self.options = options
            self.downstream = downstream
        }
        
        deinit {
            lock.deallocate()
            downstreamLock.deallocate()
        }
        
        func request(_ demand: Subscribers.Demand) {
            lock.lock()
            
            guard let subject = subject else {
                lock.unlock()
                return
            }
            
            self.demand += demand
            
            let keyPath = self.keyPath
            let options = self.options
            let handleChange = self.handleChange
            lock.unlock()
            
            let observation = subject.observe(keyPath, options: options, changeHandler: handleChange)
            
            lock.lock()
            self.observation = observation
            lock.unlock()
        }
        
        func cancel() {
            lock.lock()
            observation?.invalidate()
            observation = nil
            subject = nil
            lock.unlock()
        }
        
        private func handleChange(_ subject: Subject, change: NSKeyValueObservedChange<Value>) {
            lock.lock()
            guard demand > 0 else {
                lock.unlock()
                return
            }
            demand -= 1
            lock.unlock()
            
            downstreamLock.lock()
            let newDemand = downstream.receive(change.newValue!)
            downstreamLock.unlock()
            
            lock.lock()
            demand += newDemand
            lock.unlock()
        }
        
        fileprivate var description: String { "KeyValueObservingPublisher" }
        
        fileprivate var customMirror: Mirror {
            lock.lock()
            defer { lock.unlock() }
            let children: [Mirror.Child] = [
                ("subject", subject as Any),
                ("keyPath", keyPath),
                ("options", options),
                ("demand", demand)
            ]
            return Mirror(self, children: children)
        }
        
        fileprivate var playgroundDescription: Any { description }
    }
}
