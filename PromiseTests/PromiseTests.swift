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

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() {
		var promise = Promise<Int>({ (resolve, reject) in
			resolve(5);
		});
		promise.then(queue: DispatchQueue.main, { (result: Int) -> Void in
			NSLog("then1 %i", result);
		}).then({ () -> Void in
			NSLog("then2");
			return Promise<Void>.catch(Error("ayyyyyy"));
		}).catch({ (error) in
			NSLog("catch 1 %@", error.localizedDescription);
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
