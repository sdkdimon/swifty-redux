//
//  Reducer.swift
//  SwiftyRedux
//
//  Created by Alexander Voronov on 12/16/18.
//  Copyright © 2018 Alex Voronov. All rights reserved.
//

/// from https://redux.js.org/basics/reducers
/// Reducers specify how the application's state changes in response to actions sent to the store.
/// Remember that actions only describe what happened, but don't describe how the application's state changes.

/// It's the only place that can change application or domain state.
/// Reducers are pure functions that return new state depending on action and previous state.
/// They can be nested and combined together.
/// And it's better if they are split into smaller reducers that are focused on a small domain state.

public typealias Reducer<State> = (_ action: Action, _ state: State) -> State

public func combineReducers<State>(_ first: @escaping Reducer<State>, _ rest: Reducer<State>...) -> Reducer<State> {
    return { action, state in
        rest.reduce(first(action, state)) { state, reducer in
            reducer(action, state)
        }
    }
}
