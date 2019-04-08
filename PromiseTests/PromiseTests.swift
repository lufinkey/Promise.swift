//
//  PromiseTests.swift
//  PromiseTests
//
//  Created by Luis Finke on 10/29/18.
//  Copyright © 2018 Luis Finke. All rights reserved.
//

import XCTest
@testable import Promise

class PromiseTests: XCTestCase {
	
	public enum TestError: Error {
		case basic(message: String);
		
		public var description: String {
			get {
				switch self {
				case let .basic(message):
					return message;
				}
			}
		}
	}

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() {
		let promise = Promise<Int>.resolve(5);
		promise.then({ (result: Int) -> Void in
			NSLog("then1 \(result)");
		}).then({ (_: Void) -> Promise<Void> in
			NSLog("then2");
			return Promise<Void>.reject(TestError.basic(message: "ayyy"));
		}).catch({ (error) -> Void in
			NSLog("catch1");
		});
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
