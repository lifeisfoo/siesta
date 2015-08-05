//
//  ResourceData.swift
//  Siesta
//
//  Created by Paul on 2015/6/26.
//  Copyright © 2015 Bust Out Solutions. All rights reserved.
//

public struct ResourceData
    {
    public var payload: AnyObject
    public var mimeType: String
    public var charset: String?
    public var etag: String?
    internal var headers: [String:String]
    public private(set) var timestamp: NSTimeInterval = 0
    
    private init(
            payload: AnyObject,
            charset: String? = nil,
            headers rawHeaders: [String:String])
        {
        self.payload = payload
        
        self.headers = rawHeaders.mapDict { ($0.lowercaseString, $1) }
        
        self.mimeType = headers["content-type"] ?? "application/octet-stream"
        self.charset = charset
        self.etag = headers["etag"]
        
        self.timestamp = 0
        self.touch()
        }
    
    /// For handling network response
    
    public init(_ response: NSHTTPURLResponse?, _ payload: AnyObject)
        {
        let headers = (response?.allHeaderFields ?? [:])
            .flatMapDict { ($0 as? String, $1 as? String) }
        
        self.init(
            payload: payload,
            charset: response?.textEncodingName,
            headers: headers)
        }
    
    /// For local override
    
    public init(
            payload: AnyObject,
            mimeType: String,
            charset: String? = nil,
            var headers: [String:String] = [:])
        {
        headers["Content-Type"] = mimeType
        
        self.init(payload:payload, charset:charset, headers:headers)
        }
    
    public func header(key: String) -> String?
        { return headers[key.lowercaseString] }
    
    public mutating func touch()
        { timestamp = now() }
    }