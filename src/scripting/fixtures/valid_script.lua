-- Valid script for contract validation tests.
-- It defines the two required global functions:
-- accumulate(state, measure)
-- finalize(state, measure)

function accumulate(state, measure)
    state = state or { sum = 0, count = 0 }
    state.sum = state.sum + measure
    state.count = state.count + 1
    return state
end

function finalize(state, measure)
    _ = measure
    if state == nil or state.count == 0 then
        return 0
    end

    return state.sum / state.count
end
