//
//  Siesta-ObjC.swift
//  Siesta
//
//  Created by Paul on 2015/7/14.
//  Copyright © 2015 Bust Out Solutions. All rights reserved.
//

/*
    Glue for using Siesta from Objective-C.

    Siesta follows a Swift-first design approach. It uses the full expressiveness of the
    language to make everything feel “Swift native,” both in interface and implementation.
    
    This means many Siesta APIs can’t simply be marked @objc, and require a separate
    compatibility layer. Rather than sprinkle that mess throughout the code, it’s all
    quarrantined here.
    
    Features exposed to Objective-C:
    
     * Resource path navigation (child, relative, etc.)
     * Resource state
     * Observers
     * Request / load
     * Request completion callbacks
     * UI components
    
    Some things are not exposed in the compatibility layer, and must be done in Swift:
    
     * Subclassing Service
     * Custom ResponseTransformers
     * Custom TransportProviders
     * Logging config
*/

// MARK: - Because Swift structs aren’t visible to Obj-C

// (Why not just make Entity and Error classes and avoid all these
// shenanigans? Because Swift’s lovely mutable/immutable struct handling lets Resource
// expose the full struct to Swift clients sans copying, yet still force mutations to
// happen via localEntityOverride() so that observers always know about changes.)

@objc(BOSEntity)
public class _objc_Entity: NSObject
    {
    public var content: AnyObject
    public var mimeType: String
    public var charset: String?
    public var etag: String?
    private var headers: [String:String]
    public private(set) var timestamp: NSTimeInterval = 0
    
    public init(content: AnyObject, mimeType: String, headers: [String:String])
        {
        self.content = content
        self.mimeType = mimeType
        self.headers = headers
        }

    public convenience init(content: AnyObject, mimeType: String)
        { self.init(content: content, mimeType: mimeType, headers: [:]) }
    
    internal init(_ entity: Entity)
        {
        self.content  = entity.content
        self.mimeType = entity.mimeType
        self.charset  = entity.charset
        self.etag     = entity.etag
        self.headers  = entity.headers
        }
    
    public func header(key: String) -> String?
        { return headers[key.lowercaseString] }
    }

internal extension Entity
    {
    init(entity: _objc_Entity)
        {
        self.init(content: entity.content, mimeType: entity.mimeType, charset: entity.charset, headers: entity.headers)
        self.etag = entity.etag
        }
    }

@objc(BOSError)
public class _objc_Error: NSObject
    {
    public var httpStatusCode: Int?
    public var nsError: NSError?
    public var userMessage: String
    public var entity: _objc_Entity?
    public let timestamp: NSTimeInterval

    internal init(_ error: Error)
        {
        self.httpStatusCode = error.httpStatusCode
        self.nsError        = error.nsError
        self.userMessage    = error.userMessage
        self.timestamp      = error.timestamp
        if let errorData = error.entity
            { self.entity = _objc_Entity(errorData) }
        }
    }

public extension Resource
    {
    @objc(latestData)
    public var _objc_latestData: _objc_Entity?
        {
        if let latestData = latestData
            { return _objc_Entity(latestData) }
        else
            { return nil }
        }
    
    @objc(dictContent)
    public var _objc_dictContent: [String:AnyObject]
        { return dictContent }
    
    @objc(arrayContent)
    public var _objc_arrayContent: [AnyObject]
        { return arrayContent }
    
    @objc(textContent)
    public var _objc_textContent: String
        { return textContent }
    }

// MARK: - Because Swift closures aren’t exposed as Obj-C blocks

@objc(BOSRequest)
public class _objc_Request: NSObject
    {
    let request: Request
    
    private init(_ request: Request)
        { self.request = request }
    
    public var completion: @convention(block) ((_objc_Entity?, _objc_Error?) -> Void) -> _objc_Request
        {
        return
            {
            objcCallback in
            self.request.completion
                {
                switch($0)
                    {
                    case .Success(let entity):
                        objcCallback(_objc_Entity(entity), nil)
                    case .Failure(let error):
                        objcCallback(nil, _objc_Error(error))
                    }
                }
            return self
            }
        }

    public var success: @convention(block) (_objc_Entity -> Void) -> _objc_Request
        {
        return
            {
            objcCallback in
            self.request.success { entity in objcCallback(_objc_Entity(entity)) }
            return self
            }
        }
    
    public var newData: @convention(block) (_objc_Entity -> Void) -> _objc_Request
        {
        return
            {
            objcCallback in
            self.request.newData { entity in objcCallback(_objc_Entity(entity)) }
            return self
            }
        }

    public var notModified: @convention(block) (Void -> Void) -> _objc_Request
        {
        return
            {
            objcCallback in
            self.request.notModified(objcCallback)
            return self
            }
        }

    public var failure: @convention(block) (_objc_Error -> Void) -> _objc_Request
        {
        return
            {
            objcCallback in
            self.request.failure { error in objcCallback(_objc_Error(error)) }
            return self
            }
        }

    public func cancel()
        { request.cancel() }
    }

public extension Resource
    {
    @objc(load)
    public func _objc_load() -> _objc_Request
        { return _objc_Request(self.load()) }
    
    @objc(loadIfNeeded)
    public func _objc_loadIfNeeded() -> _objc_Request?
        {
        if let req = self.loadIfNeeded()
            { return _objc_Request(req) }
        else
            { return nil }
        }
    }

// MARK: - Because Swift enums aren’t exposed to Obj-C

@objc(BOSResourceObserver)
public protocol _objc_ResourceObserver
    {
    func resourceChanged(resource: Resource, event: String)
    optional func resourceRequestProgress(resource: Resource)
    optional func stoppedObservingResource(resource: Resource)
    }

private class _objc_ResourceObserverGlue: ResourceObserver, CustomDebugStringConvertible
    {
    weak var objcObserver: _objc_ResourceObserver?
    
    init(objcObserver: _objc_ResourceObserver)
        { self.objcObserver = objcObserver }

    func resourceChanged(resource: Resource, event: ResourceEvent)
        { objcObserver?.resourceChanged(resource, event: event.rawValue) }
    
    func resourceRequestProgress(resource: Resource)
        { objcObserver?.resourceRequestProgress?(resource) }
    
    func stoppedObservingResource(resource: Resource)
        { objcObserver?.stoppedObservingResource?(resource) }
    
    var debugDescription: String
        {
        if objcObserver != nil
            { return debugStr(objcObserver) }
        else
            { return "_objc_ResourceObserverGlue<deallocated delegate>" }
        }
    }

public extension Resource
    {
    @objc(addObserver:)
    public func _objc_addObserver(observerAndOwner: protocol<_objc_ResourceObserver, AnyObject>) -> Self
        { return addObserver(_objc_ResourceObserverGlue(objcObserver: observerAndOwner), owner: observerAndOwner) }

    @objc(addObserver:owner:)
    public func _objc_addObserver(objcObserver: _objc_ResourceObserver, owner: AnyObject) -> Self
        { return addObserver(_objc_ResourceObserverGlue(objcObserver: objcObserver), owner: owner) }

    @objc(addObserverWithOwner:callback:)
    public func addObserver(owner owner: AnyObject, callback: @convention(block) (Resource,String) -> Void) -> Self
        {
        return addObserver(owner: owner)
            { callback($0, $1.rawValue) }
        }
    }

extension ResourceStatusOverlay: _objc_ResourceObserver
    {
    public func resourceChanged(resource: Resource, event: String)
        { self.resourceChanged(resource, event: ResourceEvent(rawValue: event)!) }
    }

public extension Resource
    {
    @objc(requestWithMethod:requestMutation:)
    public func _objc_request(
            method:          String,
            requestMutation: (@convention(block) NSMutableURLRequest -> ())?)
        -> _objc_Request
        {
        return _objc_Request(
            request(
                RequestMethod(rawValue: method)!)
                    { requestMutation?($0) })
        }


    @objc(requestWithMethod:data:mimeType:requestMutation:)
    public func _objc_request(
            method:          String,
            data:            NSData,
            mimeType:        String,
            requestMutation: (@convention(block) NSMutableURLRequest -> ())?)
        -> _objc_Request
        {
        return _objc_Request(
            request(
                RequestMethod(rawValue: method)!, data: data, mimeType: mimeType)
                    { requestMutation?($0) })
        }

     @objc(requestWithMethod:text:)
     public func _objc_request(
             method:          String,
             text:            String)
         -> _objc_Request
         {
         return _objc_Request(
             request(
                 RequestMethod(rawValue: method)!, text: text))
         }

     @objc(requestWithMethod:text:mimeType:encoding:requestMutation:)
     public func _objc_request(
             method:          String,
             text:            String,
             mimeType:        String,
             encoding:        NSStringEncoding = NSUTF8StringEncoding,
             requestMutation: (@convention(block) NSMutableURLRequest -> ())?)
         -> _objc_Request
         {
         return _objc_Request(
             request(
                 RequestMethod(rawValue: method)!, text: text, mimeType: mimeType, encoding: encoding)
                     { requestMutation?($0) })
         }

     @objc(requestWithMethod:json:)
     public func _objc_request(
             method:          String,
             json:            NSObject)
         -> _objc_Request
         {
         return _objc_Request(
             request(
                 RequestMethod(rawValue: method)!, json: json as! NSJSONConvertible))
         }

     @objc(requestWithMethod:json:mimeType:requestMutation:)
     public func _objc_request(
             method:          String,
             json:            NSObject,
             mimeType:        String,
             requestMutation: (@convention(block) NSMutableURLRequest -> ())?)
         -> _objc_Request
         {
         return _objc_Request(
             request(
                 RequestMethod(rawValue: method)!, json: json as! NSJSONConvertible, mimeType: mimeType)
                     { requestMutation?($0) })
         }

     @objc(requestWithMethod:urlEncoded:requestMutation:)
     public func _objc_request(
             method:            String,
             urlEncoded params: [String:String],
             requestMutation:   (@convention(block) NSMutableURLRequest -> ())?)
         -> _objc_Request
         {
         return _objc_Request(
             request(
                 RequestMethod(rawValue: method)!)
                     { requestMutation?($0) })
         }

    }
