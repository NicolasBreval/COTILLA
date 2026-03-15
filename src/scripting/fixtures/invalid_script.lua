-- Invalid on purpose: the contract requires both
-- accumulate(state, measure) and finalize(state).
-- This script only defines finalize, so validation should fail
-- with MissingAccumulate.

function finalize(state)
    if state == nil then
        return 0
    end

    return state
end
