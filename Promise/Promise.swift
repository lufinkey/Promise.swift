//
//  Promise.swift
//  Promise
//
//  Created by Luis Finke on 10/29/18.
//  Copyright © 2018 Luis Finke. All rights reserved.
//

import Foundation

public class Promise<Result>
{
	public typealias Resolver = (Result) -> Void;
	public typealias Rejecter = (Error) -> Void;
	public typealias Then<Return> = (Result) -> Return;
	public typealias Catch<ErrorType,Return> = (ErrorType) -> Return;
	
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
	public func `catch`<ErrorType>(queue: DispatchQueue = DispatchQueue.main, _ rejectHandler: @escaping Catch<ErrorType,Void>) -> Promise<Result> {
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
	public func `catch`<ErrorType>(queue: DispatchQueue = DispatchQueue.main, _ rejectHandler: @escaping Catch<ErrorType,Promise<Result>>) -> Promise<Result> {
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
				if error is ErrorType {
					queue.async {
						rejectHandler(error as! ErrorType).then(
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
	
	// cast to another promise type
	public func `as`<T>(_ type: T.Type) -> Promise<T> {
		return Promise<T>({ (resolve, reject) in
			self.then(onresolve: { (result) in
				if let tResult = result as? T {
					resolve(tResult);
				}
				else {
					reject(PromiseError.badCast);
				}
			}, onreject: { (error: Error) -> Void in
				reject(error);
			});
		});
	}
	
	// cast to another promise type
	public func `maybeAs`<T>(_ type: T.Type) -> Promise<T?> {
		return Promise<T?>({ (resolve, reject) in
			self.then(onresolve: { (result) in
				resolve(result as? T);
			}, onreject: { (error: Error) -> Void in
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


public func await<Result>(_ promise: Promise<Result>) throws -> Result {
	var returnVal: Result? = nil;
	var throwVal: Error? = nil;
	
	let group = DispatchGroup();
	group.enter();
	
	promise.then(
	onresolve: { (result) in
		returnVal = result;
		group.leave();
	},
	onreject: { (error) in
		throwVal = error;
		group.leave();
	});
	
	group.wait();
	if throwVal != nil {
		throw throwVal!
	}
	return returnVal!;
}


public enum PromiseError: Error {
	case badCast;
}
