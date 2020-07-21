//
//  Promise.swift
//  Promise
//
//  Created by Luis Finke on 10/29/18.
//  Copyright © 2018 Luis Finke. All rights reserved.
//

import Foundation

public class Promise<Result> {
	public typealias Resolver = (Result) -> Void;
	public typealias Rejecter = (Error) -> Void;
	public typealias Then<Return> = (Result) -> Return;
	public typealias ThenThrows<Return> = (Result) throws -> Return;
	public typealias Catch<ErrorType,Return> = (ErrorType) -> Return;
	public typealias CatchThrows<ErrorType,Return> = (ErrorType) throws -> Return;
	
	// state to handle resolution / rejection
	private enum State {
		case executing;
		case resolved(result: Result);
		case rejected(error: Error);
		
		var finished: Bool {
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
		
		var result: Result? {
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
		
		var error: Error? {
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
	
	// handle execution
	fileprivate func handleCompleted(on thenQueue: DispatchQueue?, then onresolve: Then<Void>?, on catchQueue: DispatchQueue?, catch onreject: Catch<Error,Void>?) {
		thenQueue?.registerQueueReferenceKey();
		catchQueue?.registerQueueReferenceKey();
		sync.lock();
		switch(state) {
		case .executing:
			if let onresolve = onresolve {
				resolvers.append({ (result) in
					if let thenQueue = thenQueue, !thenQueue.isLocal {
						thenQueue.async {
							onresolve(result);
						}
					} else {
						onresolve(result);
					}
				});
			}
			if let onreject = onreject {
				rejecters.append({ (error) in
					if let catchQueue = catchQueue, !catchQueue.isLocal {
						catchQueue.async {
							onreject(error);
						};
					} else {
						onreject(error);
					}
				});
			}
			
		case let .resolved(result):
			sync.unlock();
			if let onresolve = onresolve {
				if let thenQueue = thenQueue, !thenQueue.isLocal {
					thenQueue.async {
						onresolve(result);
					};
				} else {
					onresolve(result);
				}
			}
			
		case let .rejected(error):
			sync.unlock();
			if let onreject = onreject {
				if let catchQueue = catchQueue, !catchQueue.isLocal {
					catchQueue.async {
						onreject(error);
					};
				} else {
					onreject(error);
				}
			}
		}
	}
	
	
	
	// handle promise resolution / rejection
	@discardableResult
	public func then(on queue: DispatchQueue? = getDefaultPromiseQueue(), _ onresolve: ThenThrows<Void>?, _ onreject: CatchThrows<Error,Void>?) -> Promise<Void> {
		return Promise<Void>({ (resolve, reject) in
			let resolveHandler = (onresolve != nil) ? { (result: Result) in
				do {
					try onresolve!(result);
				} catch let err {
					reject(err);
					return;
				}
				resolve(());
			} : { _ in resolve(()); };
			let thenQueue = (onresolve != nil) ? queue : nil;
			let rejectHandler = (onreject != nil) ? { (error: Error) in
				do {
					try onreject!(error);
				} catch let err {
					reject(err);
					return;
				}
				resolve(());
			} : reject;
			let catchQueue = (onreject != nil) ? queue : nil;
			handleCompleted(on:thenQueue, then:resolveHandler, on:catchQueue, catch:rejectHandler);
		});
	}
	
	// handle promise resolution
	@discardableResult
	public func then(on queue: DispatchQueue? = getDefaultPromiseQueue(), _ onresolve: @escaping ThenThrows<Void>) -> Promise<Void> {
		return then(on:queue, onresolve, nil);
	}
	
	// handle promise resolution
	public func then<NextResult>(on queue: DispatchQueue? = getDefaultPromiseQueue(), _ onresolve: @escaping ThenThrows<Promise<NextResult>>) -> Promise<NextResult> {
		return Promise<NextResult>({ (resolve, reject) in
			handleCompleted(on:queue, then:{ (result: Result) in
				var nextPromise: Promise<NextResult>!;
				do {
					nextPromise = try onresolve(result);
				} catch let err {
					reject(err);
					return;
				}
				nextPromise.handleCompleted(on:nil, then:resolve, on:nil, catch:reject);
			}, on:nil, catch:reject);
		});
	}
	
	// handle promise rejection with generic Error
	@discardableResult
	public func `catch`(on queue: DispatchQueue? = getDefaultPromiseQueue(), _ onreject: @escaping CatchThrows<Error,Result>) -> Promise<Result> {
		return Promise<Result>({ (resolve, reject) in
			handleCompleted(on:nil, then:resolve, on:queue, catch:{ (error: Error) in
				var result: Result!;
				do {
					result = try onreject(error);
				} catch let err {
					reject(err);
					return;
				}
				resolve(result);
			});
		});
	}
	
	// handle promise rejection with specialized Error
	@discardableResult
	public func `catch`<ErrorType: Error>(on queue: DispatchQueue? = getDefaultPromiseQueue(), _ onreject: @escaping CatchThrows<ErrorType,Result>) -> Promise<Result> {
		return Promise<Result>({ (resolve, reject) in
			handleCompleted(on:nil, then:resolve, on:nil, catch:{ (error: Error) in
				if let error = error as? ErrorType {
					let rejectHandler = { (error: ErrorType) in
						var result: Result!;
						do {
							result = try onreject(error);
						} catch let err {
							reject(err);
							return;
						}
						resolve(result);
					};
					if let queue = queue, !queue.isLocal {
						queue.async {
							rejectHandler(error);
						}
					} else {
						rejectHandler(error);
					}
				} else {
					reject(error);
				}
			});
		});
	}
	
	// handle promise rejection with generic Error + continue
	public func `catch`(on queue: DispatchQueue? = getDefaultPromiseQueue(), _ onreject: @escaping CatchThrows<Error,Promise<Result>>) -> Promise<Result> {
		return Promise<Result>({ (resolve, reject) in
			handleCompleted(on:nil, then:resolve, on:queue, catch:{ (error: Error) in
				var nextPromise: Promise<Result>!;
				do {
					nextPromise = try onreject(error);
				} catch let err {
					reject(err);
					return;
				}
				nextPromise.handleCompleted(on:nil, then:resolve, on:nil, catch:reject);
			});
		});
	}
	
	// handle promise rejection + continue
	public func `catch`<ErrorType: Error>(on queue: DispatchQueue? = getDefaultPromiseQueue(), _ onreject: @escaping CatchThrows<ErrorType,Promise<Result>>) -> Promise<Result> {
		return Promise<Result>({ (resolve, reject) in
			handleCompleted(on:nil, then:resolve, on:queue, catch:{ (error: Error) in
				if let error = error as? ErrorType {
					var nextPromise: Promise<Result>!;
					do {
						nextPromise = try onreject(error);
					} catch let err {
						reject(err);
						return;
					}
					nextPromise.handleCompleted(on:nil, then:resolve, on:nil, catch:reject);
				} else {
					reject(error);
				}
			});
		});
	}
	
	// handle promise resolution / rejection
	@discardableResult
	public func finally(on queue: DispatchQueue? = getDefaultPromiseQueue(), _ onfinally: @escaping () -> Void) -> Promise<Result> {
		return Promise<Result>({ (resolve, reject) in
			handleCompleted(
				on:queue, then:{ (result: Result) in
					onfinally()
					resolve(result);
				},
				on:queue, catch:{ (error: Error) in
					onfinally();
					reject(error);
				});
		});
	}
	
	// map to another result type
	public func map<T>(on queue: DispatchQueue? = getDefaultPromiseQueue(), _ transform: @escaping (Result) throws -> T) -> Promise<T> {
		return Promise<T>({ (resolve, reject) in
			handleCompleted(on:queue, then:{ (result: Result) in
				var newResult: T!;
				do {
					newResult = try transform(result);
				} catch let err {
					reject(err);
					return;
				}
				resolve(newResult);
			}, on:nil, catch:reject);
		});
	}
	
	// block and await the result of the promise
	public func get() throws -> Result {
		sync.lock();
		switch(state) {
		case let .resolved(result):
			sync.unlock();
			return result;
			
		case let .rejected(error):
			sync.unlock();
			throw error;
			
		case .executing:
			sync.unlock();
			var returnVal: Result? = nil;
			var throwVal: Error? = nil;
			let group = DispatchGroup();
			group.enter();
			handleCompleted(on:nil, then:{ (result: Result) in
				returnVal = result;
				group.leave();
			}, on:nil, catch:{ (error: Error) in
				throwVal = error;
				group.leave();
			});
			group.wait();
			if let error = throwVal {
				throw error;
			}
			return returnVal!;
		}
	}
	
	// convert promise type to Any
	public func toAny() -> Promise<Any> {
		return self.map(on:nil, { (result) -> Any in
			return result as Any;
		});
	}
	
	// convert promise type to Void
	public func toVoid() -> Promise<Void> {
		return self.map(on:nil, { _ in });
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
	
	// helper class for Promise.all
	private class AllData {
		var sync: NSLock = NSLock();
		var results: [Result?] = [];
		var rejected: Bool = false;
		var counter: Int = 0;
		
		init(size: Int) {
			while results.count < size {
				results.append(nil);
			}
		}
	}
	
	// wait until all the promises are resolved and return the results
	public static func all(_ promises: [Promise<Result>]) -> Promise<[Result]> {
		return Promise<[Result]>({ (resolve, reject) in
			let promiseCount = promises.count;
			if promiseCount == 0 {
				resolve([]);
				return;
			}
			
			let sharedData = AllData(size: promiseCount);
			
			let resolveIndex = { (index: Int, result: Result) -> Void in
				sharedData.sync.lock();
				if sharedData.rejected {
					sharedData.sync.unlock();
					return;
				}
				sharedData.results[index] = result;
				sharedData.counter += 1;
				let finished = (promiseCount == sharedData.counter);
				sharedData.sync.unlock();
				if finished {
					let results = sharedData.results.map({ (result) -> Result in
						return result!;
					});
					resolve(results);
				}
			};
			
			let rejectAll = { (error: Error) -> Void in
				sharedData.sync.lock();
				if sharedData.rejected {
					sharedData.sync.unlock();
					return;
				}
				sharedData.rejected = true;
				sharedData.results = [];
				sharedData.sync.unlock();
				reject(error);
			};
			
			for (i, promise) in promises.enumerated() {
				promise.handleCompleted(on:nil, then:{ (result: Result) -> Void in
					resolveIndex(i, result);
				}, on:nil, catch:{ (error: Error) -> Void in
					rejectAll(error);
				});
			}
		});
	}
	
	// helper class for Promise.race
	private class RaceData {
		var sync: NSLock = NSLock();
		var finished: Bool = false;
	}
	
	// return the result of the first promise to finish
	public static func race(_ promises: [Promise<Result>]) -> Promise<Result> {
		return Promise<Result>({ (resolve, reject) in
			let sharedData = RaceData();
			
			let resolveIndex = { (result: Result) -> Void in
				sharedData.sync.lock();
				if sharedData.finished {
					sharedData.sync.unlock();
					return;
				}
				sharedData.finished = true;
				sharedData.sync.unlock();
				resolve(result);
			};
			
			let rejectAll = { (error: Error) -> Void in
				sharedData.sync.lock();
				if sharedData.finished {
					sharedData.sync.unlock();
					return;
				}
				sharedData.finished = true;
				sharedData.sync.unlock();
				reject(error);
			};
			
			for promise in promises {
				promise.handleCompleted(on: nil, then:{ (result: Result) -> Void in
					resolveIndex(result);
				}, on:nil, catch:{ (error: Error) -> Void in
					rejectAll(error);
				});
			}
		});
	}
}



public func getDefaultPromiseQueue() -> DispatchQueue {
	return DispatchQueue.main;
}

extension DispatchQueue {
	private struct QueueReference {
		weak var queue: DispatchQueue?;
	}
	
	private static let queueReferenceKey: DispatchSpecificKey<QueueReference> = {
		let key = DispatchSpecificKey<QueueReference>();
		let queues: [DispatchQueue] = [
			.main,
			.global(qos: .background),
			.global(qos: .default),
			.global(qos: .unspecified),
			.global(qos: .userInitiated),
			.global(qos: .userInteractive),
			.global(qos: .utility)
		];
		for queue in queues {
			queue.registerQueueReferenceKey(key);
		}
		return key;
	}();
	
	private func registerQueueReferenceKey(_ key: DispatchSpecificKey<QueueReference>) {
		setSpecific(key: key, value: QueueReference(queue: self));
	}
	func registerQueueReferenceKey() {
		registerQueueReferenceKey(DispatchQueue.queueReferenceKey);
	}
	
	public static var local: DispatchQueue? {
		return getSpecific(key: queueReferenceKey)?.queue;
	}
	public var isLocal: Bool {
		registerQueueReferenceKey();
		return DispatchQueue.local == self;
	}
}



fileprivate class PromiseThread: Thread {
	private var work: ()->Void;
	init(work: @escaping ()->Void) {
		self.work = work;
	}
	override func main() {
		work();
	}
}

public func async<Result>(_ executor: @escaping () throws -> Result) -> Promise<Result> {
	return Promise<Result>({ (resolve, reject) in
		PromiseThread(work: {
			let result: Result!;
			do {
				result = try executor();
			} catch let err {
				reject(err);
				return;
			}
			resolve(result);
		}).start();
	});
}

public func sync<Result>(on queue: DispatchQueue = getDefaultPromiseQueue(), _ executor: @escaping () throws -> Result) -> Promise<Result> {
	return Promise<Result>({ (resolve, reject) in
		queue.async {
			let result: Result!;
			do {
				result = try executor();
			} catch let err {
				reject(err);
				return;
			}
			resolve(result);
		};
	});
}

public func sync<Result>(on queue: DispatchQueue = getDefaultPromiseQueue(), _ executor: @escaping () throws -> Promise<Result>) -> Promise<Result> {
	return Promise<Result>({ (resolve, reject) in
		queue.async {
			let nextPromise: Promise<Result>!;
			do {
				nextPromise = try executor();
			} catch let err {
				reject(err);
				return;
			}
			nextPromise.handleCompleted(on:nil, then:resolve, on:nil, catch:reject);
		};
	});
}


public func await<Result>(_ promise: Promise<Result>) throws -> Result {
	return try promise.get();
}
