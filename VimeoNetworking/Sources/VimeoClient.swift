//
//  VimeoClient.swift
//  VimeoNetworkingExample-iOS
//
//  Created by Huebner, Rob on 3/21/16.
//  Copyright © 2016 Vimeo. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

/// `VimeoClient` handles a rich assortment of functionality focused around interacting with the Vimeo API.  A client object tracks an authenticated account, handles the low-level execution of requests through a session manager with caching functionality, presents a high-level `Request` and `Response` interface, and notifies of globally relevant events and errors through `Notification`s
///
/// To start using a client, first instantiate an `AuthenticationController` to load a stored account or authenticate a new one.  Next, create `Request` instances and pass them into the `request` function, which returns `Response`s on success.

final public class VimeoClient {
    // MARK: -
    
    /// HTTP methods available for requests
    public enum Method: String {
        /// Retrieve a resource
        case GET
        
        /// Create a new resource
        case POST
        
        /// Set a resource
        case PUT
        
        /// Update a resource
        case PATCH
        
        /// Remove a resource
        case DELETE
    }
    
    /**
     *  `RequestToken` stores a reference to an in-flight request
     */
    public struct RequestToken {
        /// The path of the request
        public let path: String?
        
        /// The data task of the request
        public let task: URLSessionDataTask?
        
        /**
         Cancel the request
         */
        public func cancel() {
            self.task?.cancel()
        }
    }
    
        /// Dictionary containing URL parameters for a request
    public typealias RequestParametersDictionary = [String: Any]
    
        /// Array containing URL parameters for a request
    public typealias RequestParametersArray = [Any]
    
        /// Dictionary containing a JSON response
    public typealias ResponseDictionary = [String: Any]
    
        /// Domain for errors generated by `VimeoClient`
    public static let ErrorDomain = "VimeoClientErrorDomain"
    
    // MARK: -
    
        /// Session manager handles the http session data tasks and request/response serialization
    fileprivate var sessionManager: VimeoSessionManager? = nil
    
        /// response cache handles all memory and disk caching of response dictionaries
    private let responseCache = ResponseCache()
    
    struct Constants {
        fileprivate static let BearerQuery = "Bearer "
        fileprivate static let AuthorizationHeader = "Authorization"
        
        static let PagingKey = "paging"
        static let TotalKey = "total"
        static let PageKey = "page"
        static let PerPageKey = "per_page"
        static let NextKey = "next"
        static let PreviousKey = "previous"
        static let FirstKey = "first"
        static let LastKey = "last"
    }
    
    /// Create a new client
    ///
    /// - Parameters:
    ///   - appConfiguration: Your application's configuration
    ///   - configureSessionManagerBlock: a block to configure the session manager
    convenience public init(appConfiguration: AppConfiguration, configureSessionManagerBlock: ConfigureSessionManagerBlock?) {
        self.init(appConfiguration: appConfiguration, sessionManager: VimeoSessionManager.defaultSessionManager(appConfiguration: appConfiguration, configureSessionManagerBlock: configureSessionManagerBlock))
    }
    
    public init(appConfiguration: AppConfiguration?, sessionManager: VimeoSessionManager?) {
        if let appConfiguration = appConfiguration,
            let sessionManager = sessionManager {
            self.configuration = appConfiguration
            self.sessionManager = sessionManager
            
            VimeoReachability.beginPostingReachabilityChangeNotifications()
        }
    }
    
    // MARK: - Configuration
    
    /// The client's configuration
    public fileprivate(set) var configuration: AppConfiguration? = nil
    
    // MARK: - Authentication
    
        /// Stores the current account, if one exists
    public internal(set) var currentAccount: VIMAccount? {
        didSet {
            if let authenticatedAccount = self.currentAccount {
                self.sessionManager?.clientDidAuthenticate(with: authenticatedAccount)
            }
            else {
                self.sessionManager?.clientDidClearAccount()
            }
            
            self.notifyObserversAccountChanged(forAccount: self.currentAccount, previousAccount: oldValue)
        }
    }
    
    public func notifyObserversAccountChanged(forAccount account: VIMAccount?, previousAccount: VIMAccount?) {
        NetworkingNotification.authenticatedAccountDidChange.post(object: account,
                                                        userInfo: [UserInfoKey.previousAccount.rawValue as String : previousAccount ?? NSNull()])
    }
    
    // MARK: - Request
    
    /**
     Executes a `Request`
    
     - parameter request:         `Request` object containing all the required URL and policy information
     - parameter completionQueue: dispatch queue on which to execute the completion closure
     - parameter completion:      a closure executed one or more times, containing a `Result`
     
     - returns: a `RequestToken` for the in-flight request
     */
    public func request<ModelType>(_ request: Request<ModelType>, completionQueue: DispatchQueue = DispatchQueue.main, completion: @escaping ResultCompletion<Response<ModelType>>.T) -> RequestToken {
        if request.useCache {
            self.responseCache.response(forRequest: request) { result in
                
                switch result {
                case .success(let responseDictionary):
                    
                    if let responseDictionary = responseDictionary {
                        self.handleTaskSuccess(forRequest: request, task: nil, responseObject: responseDictionary, isCachedResponse: true, completionQueue: completionQueue, completion: completion)
                    }
                    else {
                        let error = NSError(domain: type(of: self).ErrorDomain, code: LocalErrorCode.cachedResponseNotFound.rawValue, userInfo: [NSLocalizedDescriptionKey: "Cached response not found"])
                        
                        self.handleError(error, request: request)
                        
                        completionQueue.async {
                            
                            completion(.failure(error: error))
                        }
                    }
                    
                case .failure(let error):
                    
                    self.handleError(error, request: request)
                    
                    completionQueue.async {
                        
                        completion(.failure(error: error))
                    }
                }
            }

            return RequestToken(path: request.path, task: nil)
        }
        else {
            let success: (URLSessionDataTask, Any?) -> Void = { (task, responseObject) in
                
                DispatchQueue.global(qos: .userInitiated).async {
                    
                    self.handleTaskSuccess(forRequest: request, task: task, responseObject: responseObject, completionQueue: completionQueue, completion: completion)
                }
            }
            
            let failure: (URLSessionDataTask?, Error) -> Void = { (task, error) in
                
                DispatchQueue.global(qos: .userInitiated).async {

                    self.handleTaskFailure(forRequest: request, task: task, error: error as NSError, completionQueue: completionQueue, completion: completion)
                }
            }
            
            let path = request.path
            let parameters = request.parameters
            
            let task: URLSessionDataTask?
            
            switch request.method {
            case .GET:
                task = self.sessionManager?.get(path, parameters: parameters, headers: nil, progress: nil, success: success, failure: failure)
            case .POST:
                task = self.sessionManager?.post(path, parameters: parameters, headers: nil, progress: nil, success: success, failure: failure)
            case .PUT:
                task = self.sessionManager?.put(path, parameters: parameters, headers: nil, success: success, failure: failure)
            case .PATCH:
                task = self.sessionManager?.patch(path, parameters: parameters, headers: nil, success: success, failure: failure)
            case .DELETE:
                task = self.sessionManager?.delete(path, parameters: parameters, headers: nil, success: success, failure: failure)
            }
            
            guard let requestTask = task else {
                let description = "Session manager did not return a task"
                
                assertionFailure(description)
                
                let error = NSError(domain: type(of: self).ErrorDomain, code: LocalErrorCode.requestMalformed.rawValue, userInfo: [NSLocalizedDescriptionKey: description])
                
                self.handleTaskFailure(forRequest: request, task: task, error: error, completionQueue: completionQueue, completion: completion)
                
                return RequestToken(path: request.path, task: nil)
            }
            
            return RequestToken(path: request.path, task: requestTask)
        }
    }
    
    /**
     Removes any cached responses for a given `Request`
     
     - parameter request: the `Request` for which to remove all cached responses
     */
    public func removeCachedResponse(forKey key: String) {
        self.responseCache.removeResponse(forKey: key)
    }
    
    /**
     Clears a client's cache of all stored responses
     */
    public func removeAllCachedResponses() {
        self.responseCache.clear()
    }
    
    // MARK: - Private task completion handlers
    
    private func handleTaskSuccess<ModelType>(forRequest request: Request<ModelType>, task: URLSessionDataTask?, responseObject: Any?, isCachedResponse: Bool = false, completionQueue: DispatchQueue, completion: @escaping ResultCompletion<Response<ModelType>>.T) {
        guard let responseDictionary = responseObject as? ResponseDictionary
        else {
            if ModelType.self == VIMNullResponse.self {
                let nullResponseObject = VIMNullResponse()
                
                // Swift complains that this cast always fails, but it doesn't seem to ever actually fail, and it's required to call completion with this response [RH] (4/12/2016)
                // It's also worth noting that (as of writing) there's no way to direct the compiler to ignore specific instances of warnings in Swift :S [RH] (4/13/16)
                let response = Response(model: nullResponseObject, json: [:]) as! Response<ModelType>

                completionQueue.async {
                    completion(.success(result: response as Response<ModelType>))
                }
            }
            else {
                let description = "VimeoClient requestSuccess returned invalid/absent dictionary"
                
                assertionFailure(description)
                
                let error = NSError(domain: type(of: self).ErrorDomain, code: LocalErrorCode.invalidResponseDictionary.rawValue, userInfo: [NSLocalizedDescriptionKey: description])
                
                self.handleTaskFailure(forRequest: request, task: task, error: error, completionQueue: completionQueue, completion: completion)
            }
            
            return
        }
        
        do {
            let modelObject: ModelType = try VIMObjectMapper.mapObject(responseDictionary: responseDictionary, modelKeyPath: request.modelKeyPath)
            
            var response: Response<ModelType>
            
            if let pagingDictionary = responseDictionary[Constants.PagingKey] as? ResponseDictionary {
                let totalCount = responseDictionary[Constants.TotalKey] as? Int ?? 0
                let currentPage = responseDictionary[Constants.PageKey] as? Int ?? 0
                let itemsPerPage = responseDictionary[Constants.PerPageKey] as? Int ?? 0
                
                var nextPageRequest: Request<ModelType>? = nil
                var previousPageRequest: Request<ModelType>? = nil
                var firstPageRequest: Request<ModelType>? = nil
                var lastPageRequest: Request<ModelType>? = nil
                
                if let nextPageLink = pagingDictionary[Constants.NextKey] as? String {
                    nextPageRequest = request.associatedPageRequest(withNewPath: nextPageLink)
                }
                
                if let previousPageLink = pagingDictionary[Constants.PreviousKey] as? String {
                    previousPageRequest = request.associatedPageRequest(withNewPath: previousPageLink)
                }
                
                if let firstPageLink = pagingDictionary[Constants.FirstKey] as? String {
                    firstPageRequest = request.associatedPageRequest(withNewPath: firstPageLink)
                }
                
                if let lastPageLink = pagingDictionary[Constants.LastKey] as? String {
                    lastPageRequest = request.associatedPageRequest(withNewPath: lastPageLink)
                }
                
                response = Response<ModelType>(model: modelObject,
                                               json: responseDictionary,
                                               isCachedResponse: isCachedResponse,
                                               totalCount: totalCount,
                                               page: currentPage,
                                               itemsPerPage: itemsPerPage,
                                               nextPageRequest: nextPageRequest,
                                               previousPageRequest: previousPageRequest,
                                               firstPageRequest: firstPageRequest,
                                               lastPageRequest: lastPageRequest)
            }
            else {
                response = Response<ModelType>(model: modelObject, json: responseDictionary, isCachedResponse: isCachedResponse)
            }
            
            // To avoid a poisoned cache, explicitly wait until model object parsing is successful to store responseDictionary [RH]
            if request.cacheResponse {
                self.responseCache.setResponse(responseDictionary: responseDictionary, forRequest: request)
            }
            
            completionQueue.async {
                completion(.success(result: response))
            }
        }
        catch let error {
            self.responseCache.removeResponse(forKey: request.cacheKey)
            
            self.handleTaskFailure(forRequest: request, task: task, error: error as NSError, completionQueue: completionQueue, completion: completion)
        }
    }
    
    private func handleTaskFailure<ModelType>(forRequest request: Request<ModelType>, task: URLSessionDataTask?, error: NSError?, completionQueue: DispatchQueue, completion: @escaping ResultCompletion<Response<ModelType>>.T) {
        let error = error ?? NSError(domain: type(of: self).ErrorDomain, code: LocalErrorCode.undefined.rawValue, userInfo: [NSLocalizedDescriptionKey: "Undefined error"])
        
        if error.code == NSURLErrorCancelled {
            return
        }
        
        self.handleError(error, request: request, task: task)
        
        if case .multipleAttempts(let attemptCount, let initialDelay) = request.retryPolicy, attemptCount > 1 {
            var retryRequest = request
            
            retryRequest.retryPolicy = .multipleAttempts(attemptCount: attemptCount - 1, initialDelay: initialDelay * 2)
            
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(initialDelay * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)) {
                let _ = self.request(retryRequest, completionQueue: completionQueue, completion: completion)
            }
        }
        
        completionQueue.async {
            completion(.failure(error: error))
        }
    }
    
    // MARK: - Private error handling
    
    private func handleError<ModelType>(_ error: NSError, request: Request<ModelType>, task: URLSessionDataTask? = nil) {
        if error.isServiceUnavailableError {
            NetworkingNotification.clientDidReceiveServiceUnavailableError.post(object: nil)
        }
        else if error.isInvalidTokenError {
            NetworkingNotification.clientDidReceiveInvalidTokenError.post(object: self.token(fromTask: task))
        }
    }
    
    private func token(fromTask task: URLSessionDataTask?) -> String? {
        guard let bearerHeader = task?.originalRequest?.allHTTPHeaderFields?[Constants.AuthorizationHeader],
            let range = bearerHeader.range(of: Constants.BearerQuery) else {
            return nil
        }
        var str = bearerHeader
        str.removeSubrange(range)
        return str
    }
}

extension VimeoClient {
    /// Singleton instance for VimeoClient. Applications must call configureSharedClient(withAppConfiguration appConfiguration:)
    /// before it can be accessed.
    public static var sharedClient: VimeoClient {
        guard let _ = self._sharedClient.configuration,
            let _ = self._sharedClient.sessionManager else {
            assertionFailure("VimeoClient.sharedClient must be configured before accessing")
            return self._sharedClient
        }
        
        return self._sharedClient
    }
    private static let _sharedClient = VimeoClient(appConfiguration: nil, sessionManager: nil)
    
    /// Configures the singleton sharedClient instance. This function allows applications to provide
    /// client specific app configurations at start time.
    ///
    /// - Parameters:
    ///   - appConfiguration: An AppConfiguration instance
    ///   - configureSessionManagerBlock: a block to configure the session manager
    public static func configureSharedClient(withAppConfiguration appConfiguration: AppConfiguration, configureSessionManagerBlock: ConfigureSessionManagerBlock?) {
        self._sharedClient.configuration = appConfiguration
        
        let defaultSessionManager = VimeoSessionManager.defaultSessionManager(appConfiguration: appConfiguration, configureSessionManagerBlock: configureSessionManagerBlock)
        
        self._sharedClient.sessionManager?.invalidateSessionCancelingTasks(false, resetSession: false)
        self._sharedClient.sessionManager = defaultSessionManager
        
        VimeoReachability.beginPostingReachabilityChangeNotifications()
    }
}
