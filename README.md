# Promise.swift

A small promise library for swift that mimics JavaScript's Promise and await / async.

## Install

Add the following line to your `Podfile`:

```ruby
pod 'Promise', :git => 'https://github.com/lufinkey/Promise.swift.git'
```

## Usage

This Promise class functions nearly exactly like [JavaScript's Promise class](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise)

### Creating a Promise

To turn an asynchronous callback operation into a Promise, just wrap it in the Promise constructor:

```swift
func myAsyncFunction() -> Promise<Int> {
	// return a promise instance wrapping your callback function in a lambda
	return Promise<Int>({ (resolve, reject) in
		// call your callback function inside the Promise's lambda
		myCallbackFunction({ (error: Error?, result: Int?) in
			// check for an error
			if error != nil {
				// we have an error, so reject the promise
				reject(error!);
			}
			else {
				// no error, so return the result
				resolve(result!);
			}
		});
	});
}
```

### Handling a Promise

To retrieve the value from your Promise or handle an error, you can use `then` and `catch`. `then` handles the promise result, and `catch` handles promise failure:

```swift
let promise = myAsyncFunction();
promise.then({ (result: Int) in
	print("We have the result: \(result)");
}).catch({ (error: Error) -> Void in
	print("We caught an error: \(error)");
});
```

The `catch` function can be used to handle multiple types of errors:

```swift
let promise = myAsyncFunction();
promise.then({ (result: Int) in
	print("We have the result: \(result)");
}).catch({ (error: MySpecialError) -> Void in
	print("We caught an error of type MySpecialError: \(error)");
}).catch({ (error: MyOtherError) -> Void in
	print("We caught an error of type MyOtherError: \(error)");
}).catch({ (error: Error) -> Void in
	print("We caught a generic error: \(error)");
});
```

You can also chain `then` functions to call multiple asynchronous functions in a row:

```swift
let promise = myAsyncFunction();
promise.then({ (result: Int) -> Promise<String> in
	print("We have the 1st result: \(result)");
	return myAsyncStringFunction();
}).then({ (result: String) in
	print("We have the 2nd result: \(result)");
}).catch({ (error: Error) -> Void in
	print("We caught an error: \(error)");
});
```

After a `catch` callback is called, the promise chain will stop unless the callback returns another Promise with the expected result type:

```swift
let promise = myAsyncFunction();
promise.then({ (result: Int) -> Promise<String> in
	print("We have the 1st result: \(result)");
	return myAsyncStringFunction();
}).catch({ (error: Error) -> Void in
	// we caught an error, but we still want the next operation to happen
	// return a promise with a resolved String value
	return Promise<String>.resolve("hello world");
}).then({ (result: String) in
	print("We have the 2nd result: \(result)");
});
```

Note that this behaviour is different than JavaScript's Promise, [where the chain will continue executing after a `catch` callback](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise/catch).

### Await / Async

This library attempts to mimic the JavaScript [Await/Async](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/async_function) flow by providing global `await` and `async` functions.
These functions can be used to write asynchronous code linearly. You can also use do/try/catch blocks, or you can let the async block catch your errors and forward them to the returned Promise.

```swift
// handle errors with do/catch
func myLinearAsyncFunction1() -> Promise<Int>
	return async {
		do {
			let result1: Int = try await(myAsyncFunction());
			print("We have the 1st result: \(result1)");
			let result2: Int = try await(someOtherAsyncFunction());
			print("We have the 2nd result: \(result2)");
			return result1 + result2;
		}
		catch {
			print("We caught an error: \(error)");
			return 0;
		}
	};
}

// or let the async block catch your error and return a rejected Promise if something throws an Error
func myLinearAsyncFunction2() -> Promise<Int>
	return async {
		let result1: Int = try await(myAsyncFunction());
		print("We have the 1st result: \(result1)");
		let result2: Int = try await(someOtherAsyncFunction());
		print("We have the 2nd result: \(result2)");
		return result1 + result2;
	};
}
```


