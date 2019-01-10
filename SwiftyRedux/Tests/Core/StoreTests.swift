import XCTest
@testable import SwiftyRedux

private typealias State = Int
private enum AnyAction: Int, Action { case one = 1, two, three, four, five }
private enum OpAction: Action, Equatable { case inc, mul }
private struct StringAction: Action {
    let value: String
    init(_ value: String) { self.value = value }
}

class StoreTests: XCTestCase {
    private var initialState: State!
    private var nopReducer: Reducer<State>!
    private var nopMiddleware: Middleware<State>!

    override func setUp() {
        super.setUp()

        initialState = 0
        nopReducer = { action, state in state }
        nopMiddleware = createFallThroughMiddleware { getState, dispatch in return { action in } }
    }

    func testMiddlewareIsExecutedOnlyOnceBeforeActionReceived() {
        var result = 0
        let middleware: Middleware<State> = createMiddleware { getState, dispatch, next in
            result += 1
            return { action in next(action) }
        }
        let store = Store(state: initialState, reducer: nopReducer, middleware: [middleware])

        store.dispatch(AnyAction.one)
        store.dispatch(AnyAction.two)
        store.dispatch(AnyAction.three)

        XCTAssertEqual(result, 1)
    }

    func testFallThroughMiddlewareIsExecutedOnlyOnceBeforeActionReceived() {
        var result = 0
        let middleware: Middleware<State> = createFallThroughMiddleware { getState, dispatch in
            result += 1
            return { action in }
        }
        let store = Store(state: initialState, reducer: nopReducer, middleware: [middleware])

        store.dispatch(AnyAction.one)
        store.dispatch(AnyAction.two)
        store.dispatch(AnyAction.three)

        XCTAssertEqual(result, 1)
    }

    func testMiddlewareExecutesActionBodyAsManyTimesAsActionsReceived() {
        var result = 0
        let middleware: Middleware<State> = createMiddleware { getState, dispatch, next in
            return { action in
                result += 1
                next(action)
            }
        }
        let store = Store(state: initialState, reducer: nopReducer, middleware: [middleware])

        store.dispatch(AnyAction.one)
        store.dispatch(AnyAction.two)
        store.dispatch(AnyAction.three)

        XCTAssertEqual(result, 3)
    }

    func testFallThroughMiddlewareExecutesActionBodyAsManyTimesAsActionsReceived() {
        var result = 0
        let middleware: Middleware<State> = createFallThroughMiddleware { getState, dispatch in
            return { action in result += 1 }
        }
        let store = Store(state: initialState, reducer: nopReducer, middleware: [middleware])

        store.dispatch(AnyAction.one)
        store.dispatch(AnyAction.two)
        store.dispatch(AnyAction.three)

        XCTAssertEqual(result, 3)
    }

    func testStore_afterSubscribeAndDispatchFlow_deinits_andAllDisposablesDispose() {
        weak var store: Store<State>?
        var disposable: Disposable!

        autoreleasepool {
            let deinitStore = Store(state: initialState, reducer: nopReducer, middleware: [nopMiddleware])
            store = deinitStore
            disposable = deinitStore.subscribe(observer: { state in })
            deinitStore.dispatch(AnyAction.one)
        }

        XCTAssertTrue(disposable.isDisposed)
        XCTAssertNil(store)
    }

    func testMiddleware_whenRunOnDefaultQueue_isExecutedSequentiallyWithReducer() {
        var result = [String]()
        let middleware: Middleware<State> = createMiddleware { getState, dispatch, next in
            return { action in
                result.append("m-\(action)")
                next(action)
            }
        }
        let reducer: Reducer<State> = { action, state in
            result.append("r-\(action)")
            return state
        }
        let store = Store<State>(state: initialState, reducer: reducer, middleware: [middleware])

        store.dispatch(AnyAction.one)
        store.dispatch(AnyAction.two)
        store.dispatch(AnyAction.three)
        store.dispatch(AnyAction.four)

        XCTAssertEqual(result, ["m-one", "r-one", "m-two", "r-two", "m-three", "r-three", "m-four", "r-four"])
    }

    func testMiddleware_evenIfRunOnDifferentQueues_isExecutedSequentially() {
        func asyncMiddleware(id: String, qos: DispatchQoS.QoSClass) -> Middleware<State> {
            let asyncExpectation = expectation(description: "\(id) async middleware expectation")
            return createMiddleware { getState, dispatch, next in
                return { action in
                    DispatchQueue.global(qos: qos).async {
                        let action = (action as! StringAction).value
                        next(StringAction("\(action) \(id)"))
                        asyncExpectation.fulfill()
                    }
                }
            }
        }

        var result = ""
        let reducer: Reducer<State> = { action, state in
            let action = (action as! StringAction).value
            result += action
            return state
        }
        let middleware1 = asyncMiddleware(id: "first", qos: .default)
        let middleware2 = asyncMiddleware(id: "second", qos: .userInteractive)
        let middleware3 = asyncMiddleware(id: "third", qos: .background)
        let store = Store<State>(state: initialState, reducer: reducer, middleware: [middleware1, middleware2, middleware3])

        store.dispatch(StringAction("action"))

        waitForExpectations(timeout: 0.1) { e in
            XCTAssertEqual(result, "action first second third")
        }
    }

    func testStore_whenSubscribing_startReceivingStateUpdates() {
        let reducer: Reducer<State> = { action, state in
            switch action {
            case let action as OpAction where action == OpAction.mul: return state * 2
            case let action as OpAction where action == OpAction.inc: return state + 3
            default: return state
            }
        }
        let store = Store<State>(state: 3, reducer: reducer)

        var result: [State] = []
        store.subscribe { state in
            result.append(state)
        }
        store.dispatch(OpAction.mul)
        store.dispatch(OpAction.inc)

        XCTAssertEqual(result, [6, 9])
    }

    func testSubscribeToStore_whenSkippingRepeats_receiveUniqueStateUpdates() {
        let actions: [AnyAction] = [.one, .two, .one, .one, .three, .three, .five, .two]
        let reducer: Reducer<State> = { action, state in
            (action as! AnyAction).rawValue
        }
        let store = Store<State>(state: initialState, reducer: reducer)

        var result: [State] = []
        store.subscribe(skipRepeats: true) { state in
            result.append(state)
        }
        actions.forEach(store.dispatch)

        XCTAssertEqual(result, [1, 2, 1, 3, 5, 2])
    }

    func testSubscribeToStore_whenNotSkippingRepeats_receiveDuplicatedStateUpdates() {
        let actions: [AnyAction] = [.one, .two, .one, .one, .three, .three, .five, .two]
        let reducer: Reducer<State> = { action, state in
            (action as! AnyAction).rawValue
        }
        let store = Store<State>(state: initialState, reducer: reducer)

        var result: [State] = []
        store.subscribe(skipRepeats: false) { state in
            result.append(state)
        }
        actions.forEach(store.dispatch)

        XCTAssertEqual(result, [1, 2, 1, 1, 3, 3, 5, 2])
    }

    func testStore_whenSubscribing_ReceiveStateUpdatesOnSelectedQueue() {
        let id = "testStore_whenSubscribing_ReceiveStateUpdatesOnSelectedQueue"
        let queueId = DispatchSpecificKey<String>()
        let queue = DispatchQueue(label: id)
        queue.setSpecific(key: queueId, value: id)
        let store = Store<State>(state: initialState, reducer: nopReducer)

        var result: String!
        let queueExpectation = expectation(description: id)
        store.subscribe(on: queue) { state in
            result = DispatchQueue.getSpecific(key: queueId)
            queueExpectation.fulfill()
        }
        store.dispatch(AnyAction.one)

        waitForExpectations(timeout: 0.1) { e in
            queue.setSpecific(key: queueId, value: nil)

            XCTAssertEqual(result, id)
        }
    }

    func testStore_whenSubscribingWithoutSelectedQueue_butDidSoBefore_receiveStateUpdatesOnDefaultQueue() {
        let id = "testStore_whenSubscribingWithoutSelectedQueue_butDidSoBefore_receiveStateUpdatesOnDefaultQueue"
        let queueId = DispatchSpecificKey<String>()
        let queue = DispatchQueue(label: id)
        queue.setSpecific(key: queueId, value: id)
        let store = Store<State>(state: initialState, reducer: nopReducer)

        var result: String!
        let onQueueExpectation = expectation(description: "\(id) on queue")
        let defaultQueueExpectation = expectation(description: "\(id) default queue")
        store.subscribe(on: queue) { state in
            onQueueExpectation.fulfill()
        }
        store.subscribe { state in
            defaultQueueExpectation.fulfill()
            result = DispatchQueue.getSpecific(key: queueId)
        }
        store.dispatch(AnyAction.one)

        waitForExpectations(timeout: 0.1) { e in
            queue.setSpecific(key: queueId, value: nil)

            XCTAssertNotEqual(result, id)
        }
    }

    func testStore_whenUnsubscribing_stopReceivingStateUpdates() {
        let reducer: Reducer<State> = { action, state in
            (action as! AnyAction).rawValue
        }
        let store = Store<State>(state: initialState, reducer: reducer)

        var result: [State] = []
        let disposable = store.subscribe { state in
            result.append(state)
        }
        store.dispatch(AnyAction.one)
        store.dispatch(AnyAction.two)
        store.dispatch(AnyAction.three)

        disposable.dispose()
        store.dispatch(AnyAction.four)
        store.dispatch(AnyAction.five)

        XCTAssertEqual(result, [1, 2, 3])
    }

    func testStore_whenObserving_andSubscribingToObserver_startReceivingStateUpdates() {
        let reducer: Reducer<State> = { action, state in
            switch action {
            case let action as OpAction where action == .mul: return state * 2
            case let action as OpAction where action == .inc: return state + 3
            default: return state
            }
        }
        let store = Store<State>(state: 3, reducer: reducer)

        var result: [State] = []
        store.observe().subscribe { state in
            result.append(state)
        }
        store.dispatch(OpAction.mul)
        store.dispatch(OpAction.inc)

        XCTAssertEqual(result, [6, 9])
    }

    func testStore_whenUnsubscribingFromObserver_stopReceivingStateUpdates() {
        let reducer: Reducer<State> = { action, state in
            (action as! AnyAction).rawValue
        }
        let store = Store<State>(state: initialState, reducer: reducer)

        var result: [State] = []
        let disposable = store.observe().subscribe { state in
            result.append(state)
        }
        store.dispatch(AnyAction.one)
        store.dispatch(AnyAction.two)
        store.dispatch(AnyAction.three)

        disposable.dispose()
        store.dispatch(AnyAction.four)
        store.dispatch(AnyAction.five)

        XCTAssertEqual(result, [1, 2, 3])
    }
}
