//
//  Promise.swift
//  Promise
//
//  Created by Luis Finke on 10/29/18.
//  Copyright © 2018 Luis Finke. All rights reserved.
//

import Foundation

class Promise<Result>
{
	typealias Resolver = (Result) -> Void;
	typealias Rejecter = (Error) -> Void;
	typealias Then<Return> = (Result) -> Return;
	
	// state to handle resolution / rejection
	private enum State {
		case executing;
		case resolved(result: Result);
		case rejected(error: Error);
		
		public var finished: Bool {
			get {
				switch(self) {
				case .executing:
					return false;
				case .resolved:
					return true;
				case .rejected:
					return true;
				}
			}
		}
		
		public var result: Result? {
			get {
				switch(self) {
				case .executing:
					return nil;
				case .resolved(let result):
					return result;
				case .rejected:
					return nil;
				}
			}
		}
		
		public var error: Error? {
			get {
				switch(self) {
				case .executing:
					return nil;
				case .resolved:
					return nil;
				case .rejected(let error):
					return error;
				}
			}
		}
	}
	private var state: State = .executing;
	
	private var resolvers: [Resolver] = [];
	private var rejecters: [Rejecter] = [];
	private var sync: NSLock = NSLock();
	
	
	// create and execute a promise
	public init(_ executor: (@escaping Resolver, @escaping Rejecter) -> Void) {
		executor({ (result: Result) in
			self.handleResolve(result);
		}, { (error: Error) in
			self.handleReject(error);
		});
	}
	
	// send promise result
	private func handleResolve(_ result: Result) {
		sync.lock();
		// ensure correct state
		var callbacks: [Resolver] = [];
		switch(state) {
		case .executing:
			state = State.resolved(result: result);
			callbacks = resolvers;
			resolvers.removeAll();
			rejecters.removeAll();
			sync.unlock();
			break;
		case .resolved: fallthrough
		case .rejected:
			sync.unlock();
			assert(false, "Cannot resolve a promise multiple times");
			break;
		}
		// call callbacks
		for callback in callbacks {
			callback(result);
		}
	}
	
	// send promise error
	private func handleReject(_ error: Error) {
		sync.lock();
		// ensure correct state
		var callbacks: [Rejecter] = [];
		switch(state) {
		case .executing:
			state = State.rejected(error: error);
			callbacks = rejecters;
			resolvers.removeAll();
			rejecters.removeAll();
			sync.unlock();
			break;
		case .resolved: fallthrough
		case .rejected:
			sync.unlock();
			assert(false, "Cannot resolve a promise multiple times");
			break;
		}
		// call callbacks
		for callback in callbacks {
			callback(error);
		}
	}
	
	
	
	// handle promise resolution / rejection
	@discardableResult
	public func then(queue: DispatchQueue = DispatchQueue.main, onresolve resolveHandler: @escaping Then<Void>, onreject rejectHandler: @escaping (Error) -> Void) -> Promise<Void> {
		return Promise<Void>({ (resolve, reject) in
			sync.lock();
			switch(state) {
			case .executing:
				resolvers.append({ (result: Result) in
					queue.async {
						resolveHandler(result);
						resolve(Void());
					}
				});
				rejecters.append({ (error: Error) in
					queue.async {
						rejectHandler(error);
					}
				});
				sync.unlock();
				break;
			case .resolved(let result):
				sync.unlock();
				queue.async {
					resolveHandler(result);
					resolve(Void());
				}
				break;
			case .rejected(let error):
				sync.unlock();
				queue.async {
					rejectHandler(error);
				}
				break;
			}
		});
	}
	
	// handle promise resolution
	@discardableResult
	public func then(queue: DispatchQueue = DispatchQueue.main, _ resolveHandler: @escaping Then<Void>) -> Promise<Void> {
		return Promise<Void>({ (resolve, reject) in
			sync.lock();
			switch(state) {
			case .executing:
				resolvers.append({ (result: Result) in
					queue.async {
						resolveHandler(result);
						resolve(Void());
					}
				});
				rejecters.append({ (error: Error) in
					reject(error);
				});
				sync.unlock();
				break;
			case .resolved(let result):
				sync.unlock();
				queue.async {
					resolveHandler(result);
					resolve(Void());
				}
				break;
			case .rejected(let error):
				sync.unlock();
				reject(error);
				break;
			}
		});
	}
	
	// handle promise resolution
	public func then<NextResult>(queue: DispatchQueue = DispatchQueue.main, _ resolveHandler: @escaping Then<Promise<NextResult>>) -> Promise<NextResult> {
		return Promise<NextResult>({ (resolve, reject) in
			sync.lock();
			switch(state) {
			case .executing:
				resolvers.append({ (result: Result) in
					queue.async {
						resolveHandler(result).then(
							onresolve: { (nextResult: NextResult) -> Void in
								resolve(nextResult);
							},
							onreject: { (nextError: Error) -> Void in
								reject(nextError);
							}
						);
					}
				});
				rejecters.append({ (error: Error) in
					reject(error);
				});
				sync.unlock();
				break;
			case .resolved(let result):
				sync.unlock();
				queue.async {
					resolveHandler(result).then(
						onresolve: { (nextResult: NextResult) -> Void in
							resolve(nextResult);
						},
						onreject: { (nextError: Error) -> Void in
							reject(nextError);
						}
					);
				}
				break;
			case .rejected(let error):
				sync.unlock();
				reject(error);
				break;
			}
		});
	}
	
	// handle promise rejection
	@discardableResult
	public func `catch`<ErrorType: Error>(queue: DispatchQueue = DispatchQueue.main, _ rejectHandler: @escaping (ErrorType) -> Void) -> Promise<Result> {
		return Promise<Result>({ (resolve, reject) in
			sync.lock();
			switch(state) {
			case .executing:
				resolvers.append({ (result: Result) in
					resolve(result);
				});
				rejecters.append({ (error: Error) in
					if error is ErrorType {
						queue.async {
							rejectHandler(error as! ErrorType);
						}
					}
					else {
						reject(error);
					}
				});
				sync.unlock();
				break;
			case .resolved(let result):
				sync.unlock();
				resolve(result);
				break;
			case .rejected(let error):
				sync.unlock();
				if error is ErrorType {
					queue.async {
						rejectHandler(error as! ErrorType);
					}
				}
				else {
					reject(error);
				}
				break;
			}
		});
	}
	
	// handle promise rejection + continue
	public func `catch`<ErrorType: Error>(queue: DispatchQueue = DispatchQueue.main, _ rejectHandler: @escaping (ErrorType) -> Promise<Result>) -> Promise<Result> {
		return Promise<Result>({ (resolve, reject) in
			sync.lock();
			switch(state) {
			case .executing:
				resolvers.append({ (result: Result) in
					resolve(result);
				});
				rejecters.append({ (error: Error) in
					if error is ErrorType {
						queue.async {
							rejectHandler(error as! ErrorType).then(
								onresolve: { (result: Result) in
									resolve(result);
								},
								onreject: { (error: Error) in
									reject(error);
								}
							);
						}
					}
					else {
						reject(error);
					}
				});
				sync.unlock();
				break;
			case .resolved(let result):
				sync.unlock();
				resolve(result);
				break;
			case .rejected(let error):
				sync.unlock();
				if error is ErrorType {
					queue.async {
						rejectHandler(error as! ErrorType).then(
							onresolve: { (result: Result) in
								resolve(result);
							},
							onreject: { (error: Error) in
								reject(error);
							}
						);
					}
				}
				else {
					reject(error);
				}
				break;
			}
		});
	}
	
	// handle promise resolution / rejection
	@discardableResult
	public func finally(queue: DispatchQueue = DispatchQueue.main, _ finallyHandler: @escaping () -> Void) -> Promise<Void> {
		return Promise<Void>({ (resolve, reject) in
			self.then(queue: queue,
			onresolve: { (result: Result) in
				finallyHandler();
				resolve(Void());
			},
			onreject: { (error: Error) in
				finallyHandler();
				resolve(Void());
			});
		});
	}
	
	// handle promise resolution / rejection
	public func finally<NextResult>(queue: DispatchQueue = DispatchQueue.main, _ finallyHandler: @escaping () -> Promise<NextResult>) -> Promise<NextResult> {
		return Promise<NextResult>({ (resolve, reject) in
			self.then(queue: queue,
			onresolve: { (result: Result) in
				finallyHandler().then(
				onresolve: { (result: NextResult) in
					resolve(result);
				},
				onreject: { (error: Error) in
					reject(error);
				});
			},
			onreject: { (error: Error) in
				finallyHandler().then(
				onresolve: { (result: NextResult) in
					resolve(result);
				},
				onreject: { (error: Error) in
					reject(error);
				});
			});
		});
	}
	
	// create a resolved promise
	public static func resolve(_ result: Result) -> Promise<Result> {
		return Promise<Result>({ (resolve, reject) in
			resolve(result);
		});
	}
	
	// create a rejected promise
	public static func reject(_ error: Error) -> Promise<Result> {
		return Promise<Result>({ (resolve, reject) in
			reject(error);
		});
	}
}
