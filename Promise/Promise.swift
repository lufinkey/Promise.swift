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
	
	
	
	// handle promise resolution / rejection
	@discardableResult
	public func then(queue: DispatchQueue = DispatchQueue.main, onresolve resolveHandler: @escaping Then<Void>, onreject rejectHandler: @escaping Catch<Error,Void>) -> Promise<Void> {
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
	public func then(queue: DispatchQueue = DispatchQueue.main, _ resolveHandler: @escaping ThenThrows<Void>) -> Promise<Void> {
		return Promise<Void>({ (resolve, reject) in
			sync.lock();
			switch(state) {
			case .executing:
				resolvers.append({ (result: Result) in
					queue.async {
						do {
							try resolveHandler(result);
							resolve(());
						}
						catch {
							reject(error);
						}
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
					do {
						try resolveHandler(result);
						resolve(());
					}
					catch {
						reject(error);
					}
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
	
	// handle promise rejection with generic Error
	@discardableResult
	public func `catch`(queue: DispatchQueue = DispatchQueue.main, _ rejectHandler: @escaping CatchThrows<Error,Result>) -> Promise<Result> {
		return Promise<Result>({ (resolve, reject) in
			sync.lock();
			switch(state) {
			case .executing:
				resolvers.append({ (result: Result) in
					resolve(result);
				});
				rejecters.append({ (error: Error) in
					queue.async {
						do {
							let result = try rejectHandler(error);
							resolve(result);
						}
						catch {
							reject(error);
						}
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
				queue.async {
					do {
						let result = try rejectHandler(error);
						resolve(result);
					}
					catch {
						reject(error);
					}
				}
				break;
			}
		});
	}
	
	// handle promise rejection with specialized Error
	@discardableResult
	public func `catch`<ErrorType: Error>(queue: DispatchQueue = DispatchQueue.main, _ rejectHandler: @escaping CatchThrows<ErrorType,Result>) -> Promise<Result> {
		return Promise<Result>({ (resolve, reject) in
			sync.lock();
			switch(state) {
			case .executing:
				resolvers.append({ (result: Result) in
					resolve(result);
				});
				rejecters.append({ (error: Error) in
					if let error = error as? ErrorType {
						queue.async {
							do {
								let result = try rejectHandler(error);
								resolve(result);
							}
							catch {
								reject(error);
							}
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
				if let error = error as? ErrorType {
					queue.async {
						do {
							let result = try rejectHandler(error);
							resolve(result);
						}
						catch {
							reject(error);
						}
					}
				}
				else {
					reject(error);
				}
				break;
			}
		});
	}
	
	// handle promise rejection with generic Error + continue
	public func `catch`(queue: DispatchQueue = DispatchQueue.main, _ rejectHandler: @escaping Catch<Error,Promise<Result>>) -> Promise<Result> {
		return Promise<Result>({ (resolve, reject) in
			sync.lock();
			switch(state) {
			case .executing:
				resolvers.append({ (result: Result) in
					resolve(result);
				});
				rejecters.append({ (error: Error) in
					queue.async {
						rejectHandler(error).then(queue: queue,
						onresolve: { (result: Result) in
							resolve(result);
						},
						onreject: { (error: Error) in
							reject(error);
						});
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
				queue.async {
					rejectHandler(error).then(queue: queue,
					onresolve: { (result: Result) in
						resolve(result);
					},
					onreject: { (error: Error) in
						reject(error);
					});
				}
				break;
			}
		});
	}
	
	// handle promise rejection + continue
	public func `catch`<ErrorType: Error>(queue: DispatchQueue = DispatchQueue.main, _ rejectHandler: @escaping Catch<ErrorType,Promise<Result>>) -> Promise<Result> {
		return Promise<Result>({ (resolve, reject) in
			sync.lock();
			switch(state) {
			case .executing:
				resolvers.append({ (result: Result) in
					resolve(result);
				});
				rejecters.append({ (error: Error) in
					if let error = error as? ErrorType {
						queue.async {
							rejectHandler(error).then(queue: queue,
							onresolve: { (result: Result) in
								resolve(result);
							},
							onreject: { (error: Error) in
								reject(error);
							});
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
				if let error = error as? ErrorType {
					queue.async {
						rejectHandler(error).then(queue: queue,
						onresolve: { (result: Result) in
							resolve(result);
						},
						onreject: { (error: Error) in
							reject(error);
						});
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
	
	// map to another result type
	public func map<T>(queue: DispatchQueue = DispatchQueue.global(), _ transform: @escaping (Result) throws -> T) -> Promise<T> {
		return Promise<T>({ (resolve, reject) in
			self.then(
				queue: queue,
				onresolve: { (result) in
					do {
						let mappedResult = try transform(result);
						resolve(mappedResult);
					}
					catch {
						reject(error);
					}
				},
				onreject: { (error: Error) -> Void in
					reject(error);
				});
		});
	}
	
	// block and await the result of the promise
	public func await(queue: DispatchQueue = DispatchQueue.global()) throws -> Result {
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
			self.then(
				queue: queue,
				onresolve: { (result) in
					returnVal = result;
					group.leave();
				},
				onreject: { (error) in
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
	public func toAny(queue: DispatchQueue = DispatchQueue.global()) -> Promise<Any> {
		return Promise<Any>({ (resolve, reject) in
			self.then(
				queue: queue,
				onresolve: { (result) in
					resolve(result as Any);
				},
				onreject: { (error: Error) -> Void in
					reject(error);
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
				sharedData.sync.unlock();
				reject(error);
			};
			
			for (i, promise) in promises.enumerated() {
				promise.then(
					onresolve: { (result: Result) -> Void in
						resolveIndex(i, result);
					},
					onreject: { (error: Error) -> Void in
						rejectAll(error);
					}
				);
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
				promise.then(
					onresolve: { (result: Result) -> Void in
						resolveIndex(result);
					},
					onreject: { (error: Error) -> Void in
						rejectAll(error);
					}
				);
			}
		});
	}
}


public func async<Result>(_ executor: @escaping () throws -> Result) -> Promise<Result> {
	return Promise<Result>({ (resolve, reject) in
		DispatchQueue.global().async {
			do {
				let result = try executor();
				resolve(result);
			}
			catch {
				reject(error);
			}
		};
	});
}


public func sync<Result>(_ executor: @escaping () throws -> Result) -> Promise<Result> {
	return Promise<Result>({ (resolve, reject) in
		DispatchQueue.main.async {
			do {
				let result = try executor();
				resolve(result);
			}
			catch {
				reject(error);
			}
		};
	});
}


public func await<Result>(queue: DispatchQueue = DispatchQueue.global(), _ promise: Promise<Result>) throws -> Result {
	return try promise.await(queue: queue);
}
