-- Invalid on purpose: finalize has only one parameter.
-- The contract requires both accumulate and finalize to accept two parameters.

function accumulate(state, measure)
    state = state or { sum = 0, count = 0 }
    state.sum = state.sum + measure
    state.count = state.count + 1
    return state
end

function finalize(state)
    return state
end
